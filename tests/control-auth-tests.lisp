;;;; control-auth-tests.lisp --- the phase-0 gate (docs/spec-agent-fs.md).
;;;; The control server was an unauthenticated loopback RCE (POST /action
;;;; eval executed arbitrary Lisp for any local process). These tests pin
;;;; the retrofit: every route except /ping demands the daemon's token,
;;;; both header spellings pass, the minted file is 0600, oversized
;;;; bodies are refused without allocation, and authorized eval still
;;;; answers. The listener here is real (127.0.0.1 on an ephemeral port)
;;;; with a PRE-BOUND token — the real state dir's control.token is never
;;;; minted or overwritten, and control-url is saved/restored.
;;;;
;;;; Run: sbcl --load tests/run-tests.lisp

(in-package #:ymacs)

(defun auth-http-raw (port request)
  "One raw HTTP conversation against 127.0.0.1:PORT; the full wire
response as a string, or :closed when the server just closed."
  (handler-case
      (let ((sock (make-instance 'sb-bsd-sockets:inet-socket :type :stream :protocol :tcp)))
        (sb-bsd-sockets:socket-connect sock (sb-bsd-sockets:make-inet-address "127.0.0.1") port)
        (let ((stream (sb-bsd-sockets:socket-make-stream sock :input t :output t
                                                         :element-type 'character
                                                         :external-format :utf-8)))
          (write-string request stream)
          (force-output stream)
          (prog1
              (with-output-to-string (out)
                (loop for ch = (read-char stream nil nil)
                      while ch do (write-char ch out)))
            (ignore-errors (sb-bsd-sockets:socket-close sock)))))
    (error () :closed)))

(defun auth-port-from-url (url)
  (parse-integer (second (split-once (second (split-once url "://")) ":"))))

(defun auth-contains-p (r needle)
  "Boolean containment: SEARCH returns a position, not T."
  (and (stringp r) (search needle r) t))

(defun run-control-auth-tests ()
  (setf *test-pass* 0 *test-fail* 0)
  (format t "ymacs control-auth tests~%")

  (test "token-equal-p: wrong length, wrong byte, empty — all rejected"
    (assert-eq* t (token-equal-p "abc123" "abc123"))
    (assert-eq* nil (token-equal-p "abc123" "abc124"))
    (assert-eq* nil (token-equal-p "abc123" "abc1234"))
    (assert-eq* nil (token-equal-p "" "abc123"))
    (assert-eq* nil (token-equal-p nil "abc123")))

  (test "minted control.token is 64 hex chars at 0600"
    (let* ((dir "/tmp/ymacs-auth-test-mint/")
           (path (merge-pathnames "control.token" (pathname dir))))
      (ensure-directories-exist dir)
      (ignore-errors (delete-file path))
      (let ((tok (mint-control-token path)))
        (assert-eq* 64 (length tok))
        (assert-eq* t (every (lambda (ch) (digit-char-p ch 16)) tok))
        (assert-eq* #o600 (logand #o777 (sb-posix:stat-mode (sb-posix:stat (namestring path)))))
        ;; a mint over an existing file re-mints, still 0600
        (let ((tok2 (mint-control-token path)))
          (assert-eq* 64 (length tok2))
          (assert-eq* #o600 (logand #o777 (sb-posix:stat-mode (sb-posix:stat (namestring path)))))))
      (ignore-errors (delete-file path))))

  ;; Live listener. Pre-bind the token (never touches the real
  ;; control.token) and restore the real control-url afterwards — a
  ;; live daemon on this host must not find the test's dead port there.
  (let* ((*control-token* "test-token-0123456789abcdef")
         (url-file (control-url-file))
         (saved-url (read-token-file url-file)))
    (when *control-server-running* (stop-control-server))
    (let* ((url (start-control-server :port 0))
           (port (auth-port-from-url url)))
      (unwind-protect
           (progn
             (test "ping answers without a token (shell liveness law)"
               (let ((r (auth-http-raw port "GET /ping HTTP/1.1
Host: t

")))
                 (assert-eq* t (auth-contains-p r "200"))
                 (assert-eq* t (auth-contains-p r "document_version"))))

             (test "GET /pane/doc without a token is 401"
               (let ((r (auth-http-raw port "GET /pane/doc HTTP/1.1
Host: t

")))
                 (assert-eq* t (auth-contains-p r "401"))))

             (test "eval WITHOUT a token is 401 — the phase-0 RCE is closed"
               (let ((r (auth-http-raw port "POST /action HTTP/1.1
Host: t
Content-Type: application/json
Content-Length: 34
Connection: close

{\"action\":\"eval\",\"form\":\"(+ 1 2)\"}")))
                 (assert-eq* t (auth-contains-p r "401"))
                 (assert-eq* nil (and (stringp r) (search "\"result\"" r)))))

             (test "eval with a WRONG token is 401"
               (let ((r (auth-http-raw port "POST /action HTTP/1.1
Host: t
Content-Type: application/json
X-Ychrome-Control: wrong-token
Content-Length: 34
Connection: close

{\"action\":\"eval\",\"form\":\"(+ 1 2)\"}")))
                 (assert-eq* t (auth-contains-p r "401"))))

             (test "X-Ychrome-Control spelling passes (the shell's contract)"
               (let ((r (auth-http-raw port "GET /pane/doc HTTP/1.1
Host: t
X-Ychrome-Control: test-token-0123456789abcdef
Connection: close

")))
                 (assert-eq* t (auth-contains-p r "200"))
                 (assert-eq* nil (auth-contains-p r "401"))))

             (test "Authorization: Bearer spelling passes (the spec/CLI spelling)"
               (let ((r (auth-http-raw port "GET /pane/doc HTTP/1.1
Host: t
Authorization: Bearer test-token-0123456789abcdef
Connection: close

")))
                 (assert-eq* t (auth-contains-p r "200"))))

             (test "authorized eval still evaluates"
               (let* ((body "{\"action\":\"eval\",\"form\":\"(+ 6 7)\"}")
                      (r (auth-http-raw port
                                        (format nil "POST /action HTTP/1.1~c~cHost: t~c~cContent-Type: application/json~c~cAuthorization: Bearer test-token-0123456789abcdef~c~cContent-Length: ~a~c~cConnection: close~c~c~c~c~a"
                                                #\Return #\Newline #\Return #\Newline #\Return #\Newline #\Return #\Newline
                                                (length body) #\Return #\Newline #\Return #\Newline #\Return #\Newline
                                                body))))
                 (assert-eq* t (auth-contains-p r "result"))
                 (assert-eq* t (auth-contains-p r "13"))))

             (test "mutation with X-Ymacs-Agent provenance is accepted"
               (let* ((probe-file "/tmp/ymacs-auth-test-open.txt")
                      (body (format nil "{\"path\":\"~a\"}" probe-file))
                      (_ (with-open-file (s probe-file :direction :output
                                            :if-exists :supersede :if-does-not-exist :create)
                           (write-string "x" s)))
                      (r (auth-http-raw port
                                        (format nil "POST /open HTTP/1.1~c~cHost: t~c~cContent-Type: application/json~c~cX-Ymacs-Agent: agent:test-suite~c~cAuthorization: Bearer test-token-0123456789abcdef~c~cContent-Length: ~a~c~cConnection: close~c~c~c~c~a"
                                                #\Return #\Newline #\Return #\Newline #\Return #\Newline #\Return #\Newline #\Return #\Newline
                                                (length body) #\Return #\Newline #\Return #\Newline #\Return #\Newline
                                                body))))
                 (declare (ignore _))
                 (assert-eq* t (auth-contains-p r "\"ok\":true"))
                 (ignore-errors (delete-file probe-file))))

             (test "oversized Content-Length refused without waiting for a body"
               (let ((r (auth-http-raw port "POST /action HTTP/1.1
Host: t
Content-Type: application/json
Authorization: Bearer test-token-0123456789abcdef
Content-Length: 999999999
Connection: close

")))
                 (assert-eq* t (auth-contains-p r "too large")))))
        (stop-control-server)
        (if saved-url
            (with-open-file (s url-file :direction :output :if-exists :supersede
                                       :external-format :utf-8)
              (write-string saved-url s))
            (ignore-errors (delete-file url-file))))))

  (format t "~a passed, ~a failed~%" *test-pass* *test-fail*)
  (zerop *test-fail*))

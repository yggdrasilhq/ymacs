;;;; main.lisp --- Entry point, daemon/client split, CLI, literate init.org

(in-package #:ymacs)

(defvar *ymacs-version* "0.1.2")
(defvar *daemon-url* nil)
(defvar *startup-time* nil)

(defun ymacs-home ()
  (or (sb-ext:posix-getenv "HOME") "/home/user"))

(defun ymacs-state-dir ()
  (state-dir))

(defun start (&key (file nil) (config nil))
  (write-manifest-best-effort)
  (format t "~&[ymacs] Initializing ymacs ~a on libyggterm...~%" *ymacs-version*)
  (setf *startup-time* (get-internal-real-time))
  (register-probe :ymacs-startup :description "Measures cold start time" :fields '(latency-ms))
  (restore-session)
  (start-control-server)
  (which-key-register-modern-defaults)
  (modern-helpers-register-which-key)
  (make-new-buffer "*scratch*" ";; ymacs 0.1.2 — GNU Emacs on libyggterm (SBCL/ECL, ytrace, vertico/consult/corfu)
;; Welcome to ymacs — modern Emacs with sane defaults.

;; Quick start:
;;   C-x C-f  find file (vertico + consult)    C-x C-b  switch buffer
;;   C-x C-s  save (revision guarded)         C-x C-k  kill buffer
;;   C-c s    toggle Buffers sidebar          M-x      vertico command palette
;;   which-key shows pending prefixes in the Which Key pane (rail)

;; Buffers live in the single sidebar (max 1 pane) — no window clutter.
;; Packages: (use-package vertico :ensure t :init (vertico-mode 1))
;;           (use-package which-key :ensure t :config (which-key-mode 1))
;; Discarded: ido/helm/ivy/company/linum — modern helpers replace them.
;; See docs/elpa-melpa-compatibility.md and init.org (literate book).

;; Try M-x eval: (+ 40 2)  — or open a file: ymacs ~/gh/ymacs/README.md
")
  (when file
    (ignore-errors (open-file-buffer (pathname file))))
  (when config
    (tangle-init-org config))
  (let ((latency-ms (round (* 1000 (/ (- (get-internal-real-time) *startup-time*) internal-time-units-per-second)))))
    (fire-probe :ymacs-startup :latency-ms latency-ms)
    (format t "~&[ymacs] Ready (~a ms). Control: ~a~%" latency-ms *control-url*))
  t)

(defun stop ()
  (persist-session)
  (stop-control-server)
  (format t "~&[ymacs] Clean shutdown completed.~%"))

;;; ---- Daemon / client split (emacsclient model) -------------------------

(defun ping-daemon (url)
  "Return document_version if daemon at URL answers, else nil."
  (handler-case
      (let* ((hostport (second (split-once url "://")))
             (hostport (first (split-once hostport "/"))))
        (require :sb-bsd-sockets)
        (let* ((sock (make-instance 'sb-bsd-sockets:inet-socket :type :stream :protocol :tcp))
               (parts (split-once hostport ":"))
               (host (first parts)) (port (parse-integer (second parts) :junk-allowed t)))
          (sb-bsd-sockets:socket-connect sock (sb-bsd-sockets:make-inet-address host) port)
          (let ((stream (sb-bsd-sockets:socket-make-stream sock :input t :output t :element-type 'character :external-format :utf-8)))
            (format stream "GET /ping HTTP/1.1~C~CHost: ~a~C~CConnection: close~C~C~C~C" #\Return #\Newline host #\Return #\Newline #\Return #\Newline #\Return #\Newline)
            (force-output stream)
            (let* ((raw (with-output-to-string (out) (loop for ch = (read-char stream nil nil) while ch do (write-char ch out))))
                   (body (second (split-once raw (format nil "~C~C~C~C" #\Return #\Newline #\Return #\Newline)))))
              (sb-bsd-sockets:socket-close sock)
              (when body
                (let ((ver (extract-json-string body "document_version")))
                  ver))))))
    (error () nil)))

(defun post-to-daemon (url path body-json)
  (handler-case
      (let* ((hostport (second (split-once url "://")))
             (hostport (first (split-once hostport "/"))))
        (require :sb-bsd-sockets)
        (let* ((sock (make-instance 'sb-bsd-sockets:inet-socket :type :stream :protocol :tcp))
               (parts (split-once hostport ":"))
               (host (first parts)) (port (parse-integer (second parts) :junk-allowed t)))
          (sb-bsd-sockets:socket-connect sock (sb-bsd-sockets:make-inet-address host) port)
          (let ((stream (sb-bsd-sockets:socket-make-stream sock :input t :output t :element-type 'character :external-format :utf-8)))
            ;; Byte length: --eval forms with non-ASCII (emoji strings,
            ;; unicode paths) are more bytes than characters on the wire.
            (format stream "POST ~a HTTP/1.1~C~CHost: ~a~C~CContent-Type: application/json~C~CContent-Length: ~a~C~CConnection: close~C~C~C~C~a"
                    path #\Return #\Newline host #\Return #\Newline #\Return #\Newline (utf8-byte-length body-json) #\Return #\Newline #\Return #\Newline #\Return #\Newline body-json)
            (force-output stream)
            (let* ((raw (with-output-to-string (out) (loop for ch = (read-char stream nil nil) while ch do (write-char ch out))))
                   (body (second (split-once raw (format nil "~C~C~C~C" #\Return #\Newline #\Return #\Newline)))))
              (sb-bsd-sockets:socket-close sock)
              body))))
    (error (e) (format nil "{\"ok\":false,\"error\":\"~a\"}" e))))

(defun extract-json-string (json key)
  (let* ((needle (format nil "\"~a\":" key))
         (pos (search needle json)))
    (when pos
      (let* ((start (+ pos (length needle)))
             (q1 (position #\" json :start start)))
        (when q1
          (let ((q2 (position #\" json :start (1+ q1))))
            (when q2 (subseq json (1+ q1) q2))))))))

(defun ensure-daemon ()
  "Return live daemon URL, spawning one if needed. URL file only trusted when it pings."
  (let ((path (control-url-file)))
    (when (probe-file path)
      (let* ((url (string-trim '(#\Space #\Newline #\Return) (read-file-string path))))
        (when (and url (plusp (length url)) (ping-daemon url))
          (return-from ensure-daemon url)))))
  ;; Spawn daemon: current sbcl image with --daemon
  (let* ((exe (or (sb-ext:posix-getenv "YMACS_BIN") (first sb-ext:*posix-argv*)))
         (home (ymacs-home)))
    (sb-ext:run-program "/bin/sh" (list "-c" (format nil "nohup ~a --daemon >~a/.yggterm/ymacs/daemon.log 2>&1 &" exe home))
                        :wait t :search t))
  ;; Wait up to 15s for daemon to write and answer — the 39MB core
  ;; restore takes >5s cold on loaded hosts (5s made every first --eval
  ;; on a quiet box a coin flip).
  (loop repeat 150 do
    (sleep 0.1)
    (when (probe-file (control-url-file))
      (let* ((url (string-trim '(#\Space #\Newline #\Return) (read-file-string (control-url-file)))))
        (when (and url (plusp (length url)) (ping-daemon url))
          (return url))))
  finally (error "ymacs daemon did not come up within 15s")))

(defvar *ymacs-manual-path-override* nil
  "Test/diagnostic override for the shipped manual location.")

(defun ymacs-manual-path ()
  "First existing candidate for the shipped Ymacs manual (docs/manual.org):
the test override, $YMACS_MANUAL_PATH, the installed share
(~/.local/share/ymacs/manual.org — install.sh puts it there), the docs/
sibling of the shipped book the settings schema resolved to, the daemon
cwd's docs/manual.org. NIL when unreachable — the daemon then falls
back to *scratch*."
  (or (and *ymacs-manual-path-override*
           (probe-file *ymacs-manual-path-override*)
           *ymacs-manual-path-override*)
      (let ((env (sb-ext:posix-getenv "YMACS_MANUAL_PATH")))
        (and env (plusp (length env)) (probe-file env) env))
      (let ((share (merge-pathnames ".local/share/ymacs/manual.org"
                                    (pathname (concatenate 'string (ymacs-home) "/")))))
        (and (probe-file share) share))
      (let ((book (ignore-errors (settings-schema-path))))
        (when (and book (string-equal (or (pathname-type book) "") "org"))
          (let* ((dir (pathname-directory (pathname book)))
                 (sib (make-pathname :directory (append (butlast dir)
                                                       (last dir)
                                                       '(:relative "docs"))
                                     :name "manual" :type "org")))
            (and (probe-file sib) sib))))
      (let ((cwd (merge-pathnames "docs/manual.org" (truename "."))))
        (and (probe-file cwd) cwd))))

(defun ensure-default-buffer ()
  "Bare-boot current buffer: the shipped manual when no buffer exists.
A restored session keeps its buffers — this never hijacks one."
  (when (null (list-all-buffers))
    (let ((manual (ignore-errors (ymacs-manual-path))))
      (if manual
          (ignore-errors (open-file-buffer manual))
          (make-new-buffer "*scratch*"
                           ";; ymacs — M-x opens the command palette.\n"))))
  *current-buffer*)

(defun run-daemon ()
  "Durable half: store + control endpoint, forever."
  (restore-session)
  (ensure-default-buffer)
  (let ((url (start-control-server)))
    (format t "~&[ymacs daemon] Control at ~a (~a)~%" url (sb-ext:posix-getenv "HOME"))
    ;; SBCL invokes signal handlers with (signal code context) — 3 args.
    ;; The v0.1.x 1-arg lambdas died on the FIRST detached-terminal SIGHUP.
    (flet ((graceful (&rest args)
             (declare (ignore args))
             (ignore-errors (persist-session))
             (sb-ext:quit)))
      (sb-sys:enable-interrupt sb-unix:sigint #'graceful)
      (sb-sys:enable-interrupt sb-unix:sigterm #'graceful))
    ;; The daemon must SURVIVE a loop error: log it, keep serving. A daemon
    ;; that takes its process down on one bad tick strands every frame.
    (loop
      (handler-case (sleep 1)
        (error (e)
          (format *error-output* "~&[ymacs] DAEMON LOOP ERROR: ~a~%" e)
          (sb-debug:backtrace 12 *error-output*)
          (sleep 1))))))

;;; ---- CLI ---------------------------------------------------------------

(defun print-help ()
  (format t "ymacs ~a — GNU Emacs on libyggterm~%" *ymacs-version*)
  (format t "Usage: ymacs [options] [file...]~%")
  (format t "  --daemon          Run durable daemon (auto-spawned; you rarely call this directly)~%")
  (format t "  --close           Close this terminal's ymacs surface (daemon keeps running)~%")
  (format t "  --eval FORM       Evaluate Lisp form in daemon (headless)~%")
  (format t "  --config FILE     Tangle and load literate init.org~%")
  (format t "  --help            Show this help~%")
  (format t "  --version         Show version~%"))

(defun handle-cli (args)
  (write-manifest-best-effort)
  (let ((files nil) (do-daemon nil) (do-close nil) (eval-forms nil) (config nil))
    (loop for a in args do
      (cond
        ((string= a "--daemon") (setf do-daemon t))
        ((string= a "--close") (setf do-close t))
        ((string= a "--help") (print-help) (sb-ext:quit))
        ((string= a "--version") (format t "~a~%" *ymacs-version*) (sb-ext:quit))
        ((string= a "--eval")
         ;; next arg is form; collect it via state machine (simplified: treat remaining as one form)
         nil)
        ((and (>= (length a) 7) (string= (subseq a 0 7) "--eval="))
         (push (subseq a 7) eval-forms))
        ((and (>= (length a) 9) (string= (subseq a 0 9) "--config="))
         (setf config (subseq a 9)))
        ((string= a "--config") nil)
        (t (push a files))))
    ;; Handle --eval with separate next arg (look ahead)
    (let ((eval-args nil))
      (loop for i from 0 below (length args)
            for a = (nth i args)
            when (string= a "--eval")
            do (when (< (1+ i) (length args))
                 (push (nth (1+ i) args) eval-args)))
      (dolist (f eval-args) (push f eval-forms)))
    (cond
      (do-daemon (run-daemon))
      (do-close
       (let ((sess (or (sb-ext:posix-getenv "YGGTERM_SESSION_ID") (sb-ext:posix-getenv "LC_YGGTERM_SESSION_ID") "")))
         (if (string= sess "")
             (progn (format t "ymacs --close needs yggterm session (YGGTERM_SESSION_ID unset)~%") (sb-ext:quit :unix-status 1))
             (progn (emit-close sess) (format t "ymacs: surface closed (daemon keeps running).~%") (sb-ext:quit)))))
      (eval-forms
       (let ((url (ensure-daemon)))
         (dolist (form (nreverse eval-forms))
           (let ((reply (post-to-daemon url "/action" (format nil "{\"action\":\"eval\",\"form\":~a}" (json-string form)))))
             (format t "~a~%" reply)))
         (sb-ext:quit)))
      (t
       (let ((url (ensure-daemon)))
         ;; Resolve files against client cwd and POST /open
         (dolist (f (nreverse files))
           (let* ((path (if (and (> (length f) 0) (char= (char f 0) #\/)) f
                               (concatenate 'string (sb-ext:posix-getenv "PWD") "/" f)))
                  (body (format nil "{\"path\":~a}" (json-string path))))
             (post-to-daemon url "/open" body)))
         (let ((sess (or (sb-ext:posix-getenv "YGGTERM_SESSION_ID") (sb-ext:posix-getenv "LC_YGGTERM_SESSION_ID") "")))
           (if (string= sess "")
               (progn
                 (format t "ymacs: not inside yggterm (YGGTERM_SESSION_ID unset). Daemon at ~a; GUI needed for surface.~%" url)
                 (sb-ext:quit))
               (let ((ver (ping-daemon url)))
                 (emit-declare sess url (or ver "1"))
                 (format t "ymacs: document surface opened — ymacs --close to close it.~%")
                 (sb-ext:quit)))))))))

;;; ---- Literate init.org tangle ------------------------------------------

(defun tangle-init-org (path)
  (format t "~&[ymacs] Tangling ~a~%" path)
  (handler-case
      (with-open-file (s path :direction :input :external-format :utf-8)
        (let ((in-src nil) (buf (make-string-output-stream)))
          (loop for line = (read-line s nil nil)
                while line do
                  (cond
                    ((and (>= (length line) 11) (string= (subseq line 0 11) "#+begin_src"))
                     (setf in-src t))
                    ((and (>= (length line) 9) (string= (subseq line 0 9) "#+end_src"))
                     (setf in-src nil)
                     (let ((code (get-output-stream-string buf)))
                       (ignore-errors (eval (read-from-string (format nil "(progn ~a)" code))))))
                    (in-src (write-line line buf)))))
        t)
    (error (e) (format t "~&[ymacs] tangle failed: ~a~%" e) nil)))

;;; ---- Agent headless verbs (JSON) ---------------------------------------

(defun ymacs-verb-eval (form-string)
  (let ((form (ignore-errors (read-from-string form-string))))
    (if form
        (let ((result (ignore-errors (eval form))))
          (format nil "{\"ok\":true,\"result\":~a}" (json-string (princ-to-string result))))
        (format nil "{\"ok\":false,\"error\":\"read failed\"}"))))

(defun ymacs-verb-buffer-list ()
  (let ((bufs (list-all-buffers)))
    (with-output-to-string (out)
      (write-char #\[ out)
      (loop for (buf . rest) on bufs do
        (format out "{\"id\":\"~a\",\"name\":\"~a\",\"path\":~a,\"modified\":~a,\"value_key\":\"~a\"}"
                (json-escape-string (buffer-id buf))
                (json-escape-string (buffer-name buf))
                (if (buffer-file-path buf) (format nil "\"~a\"" (json-escape-string (namestring (buffer-file-path buf)))) "null")
                (if (buffer-modified-p buf) "true" "false")
                (json-escape-string (buffer-value-key buf)))
        when rest do (write-char #\, out))
      (write-char #\] out))))

(defun ymacs-verb-buffers-json ()
  (ymacs-verb-buffer-list))

;;; ---- Entry point for built image ---------------------------------------

(defun main ()
  (let ((args (cdr sb-ext:*posix-argv*)))
    ;; Quick SBCL startup probe (sub-15ms target measured without ASDF reload)
    (if (null args)
        (handle-cli nil)
        (handle-cli args))))

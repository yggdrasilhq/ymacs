;;;; control-server.lisp --- Loopback HTTP control endpoint
(in-package #:ymacs)

(defvar *control-listener* nil)
(defvar *control-url* nil)
(defvar *control-port* nil)
(defvar *control-server-running* nil)

(defun control-url-file ()
  (merge-pathnames "control-url" (state-dir)))

(defun start-control-server (&key (port 0))
  (when *control-listener*
    (return-from start-control-server *control-url*))
  (require :sb-bsd-sockets)
  (let* ((sock (make-instance 'sb-bsd-sockets:inet-socket :type :stream :protocol :tcp))
         (addr (sb-bsd-sockets:make-inet-address "127.0.0.1")))
    (sb-bsd-sockets:socket-bind sock addr (or port 0))
    (sb-bsd-sockets:socket-listen sock 32)
    (let* ((bound-port (nth 1 (multiple-value-list (sb-bsd-sockets:socket-name sock))))
           (url (format nil "http://127.0.0.1:~a" bound-port)))
      (setf *control-listener* sock
            *control-url* url
            *control-port* bound-port
            *control-server-running* t)
      (ensure-state-dir)
      (with-open-file (s (control-url-file) :direction :output :if-exists :supersede :external-format :utf-8)
        (write-string url s))
      (sb-thread:make-thread
       (lambda ()
         (loop while *control-server-running* do
           (handler-case
               (let ((client (sb-bsd-sockets:socket-accept sock)))
                 (sb-thread:make-thread
                  (lambda ()
                    (handler-case (handle-client client)
                      (error (e) (ignore-errors (sb-bsd-sockets:socket-close client)))))))
             (error () (sleep 0.1)))))
       :name "ymacs-control-acceptor")
      (format t "~&[ymacs] Control server at ~a~%" url)
      url)))

(defun stop-control-server ()
  (setf *control-server-running* nil)
  (when *control-listener*
    (ignore-errors (sb-bsd-sockets:socket-close *control-listener*))
    (setf *control-listener* nil
          *control-url* nil)))

(define-condition json-parse-error (error)
  ((pos :initarg :pos :reader json-error-pos)
   (msg :initarg :msg :reader json-error-msg))
  (:report (lambda (c s)
             (format s "JSON parse error at ~a: ~a"
                     (json-error-pos c) (json-error-msg c)))))

(defun json-ws-p (ch)
  (find ch '(#\Space #\Tab #\Return #\Newline #\Null)))

(defun json-parse (str)
  "Parse STR (a JSON document) into alists/lists: objects become alists
with string keys (the handle-action contract), arrays become lists,
true/false/null become T/:FALSE/NIL, numbers become numbers. Signals
JSON-PARSE-ERROR on malformed input — the flat scanner it replaces
could not see nested objects at all, so every GUI action carrying
values (keys, drafts, palette input) arrived as garbage."
  (multiple-value-bind (value pos) (json-read-value str 0)
    (let ((end (json-skip-ws str pos)))
      (unless (>= end (length str))
        (error 'json-parse-error :pos end :msg "trailing characters"))
      value)))

(defun json-skip-ws (str pos)
  (let ((len (length str)))
    (loop while (and (< pos len) (json-ws-p (char str pos))) do (incf pos))
    pos))

(defun json-read-value (str pos)
  (let ((pos (json-skip-ws str pos)))
    (unless (< pos (length str))
      (error 'json-parse-error :pos pos :msg "unexpected end"))
    (let ((ch (char str pos)))
      (cond
        ((char= ch #\{) (json-read-object str (1+ pos)))
        ((char= ch #\[) (json-read-array str (1+ pos)))
        ((char= ch #\") (json-read-string str (1+ pos)))
        ((char= ch #\t) (json-read-literal str pos "true" t))
        ((char= ch #\f) (json-read-literal str pos "false" :false))
        ((char= ch #\n) (json-read-literal str pos "null" nil))
        (t (json-read-number str pos))))))

(defun json-read-literal (str pos spelling value)
  (unless (and (<= (+ pos (length spelling)) (length str))
               (string= str spelling :start1 pos :end1 (+ pos (length spelling))))
    (error 'json-parse-error :pos pos :msg (format nil "bad literal, wanted ~a" spelling)))
  (values value (+ pos (length spelling))))

(defun json-read-number (str pos)
  (let ((len (length str)) (end pos))
    (loop while (and (< end len)
                     (find (char str end) "-+0123456789.eE"))
          do (incf end))
    (when (= end pos)
      (error 'json-parse-error :pos pos :msg "bad value"))
    (let ((token (subseq str pos end)))
      (unless (ignore-errors
               (if (find-if (lambda (c) (find c ".eE")) token)
                   (let ((*read-eval* nil)) (read-from-string token))
                   (parse-integer token)))
        (error 'json-parse-error :pos pos :msg "bad number"))
      (values (if (find-if (lambda (c) (find c ".eE")) token)
                  (let ((*read-eval* nil)) (read-from-string token))
                  (parse-integer token))
              end))))

(defun json-hex4 (str pos)
  (let ((n 0))
    (dotimes (k 4 n)
      (let* ((ch (if (< (+ pos k) (length str)) (char str (+ pos k)) #\Space))
             (d (digit-char-p ch 16)))
        (unless d
          (error 'json-parse-error :pos (+ pos k) :msg "bad \\u escape"))
        (setf n (+ (* n 16) d))))))

(defun json-read-string (str pos)
  "STR/POS just past the opening quote. Returns (values string new-pos)
with new-pos past the closing quote."
  (let ((len (length str)) (out (make-string-output-stream)))
    (loop while t do
      (unless (< pos len)
        (error 'json-parse-error :pos pos :msg "unterminated string"))
      (let ((ch (char str pos)))
        (cond
          ((char= ch #\")
           (return (values (get-output-stream-string out) (1+ pos))))
          ((char= ch #\\)
           (incf pos)
           (unless (< pos len)
             (error 'json-parse-error :pos pos :msg "lone backslash"))
           (let ((esc (char str pos)))
             (case esc
               (#\" (write-char #\" out))
               (#\\ (write-char #\\ out))
               (#\/ (write-char #\/ out))
               (#\b (write-char #\Backspace out))
               (#\f (write-char #\Page out))
               (#\n (write-char #\Newline out))
               (#\r (write-char #\Return out))
               (#\t (write-char #\Tab out))
               (#\u
                (let ((hi (json-hex4 str (1+ pos))))
                  (cond
                    ;; High surrogate: must pair with \uDC00-DFFF.
                    ((and (<= #xD800 hi) (<= hi #xDBFF))
                     (unless (and (< (+ pos 5) len)
                                  (char= (char str (+ pos 5)) #\\)
                                  (< (+ pos 6) len)
                                  (char= (char str (+ pos 6)) #\u))
                       (error 'json-parse-error :pos pos :msg "lone surrogate"))
                     (let ((lo (json-hex4 str (+ pos 7))))
                       (unless (and (<= #xDC00 lo) (<= lo #xDFFF))
                         (error 'json-parse-error :pos pos :msg "lone surrogate"))
                       (write-char (code-char (+ #x10000
                                                 (* (- hi #xD800) #x400)
                                                 (- lo #xDC00)))
                                   out))
                     (incf pos 10))
                    ;; Lone low surrogate: replacement, never a crash.
                    ((and (<= #xDC00 hi) (<= hi #xDFFF))
                     (write-char #\Replacement_Character out)
                     (incf pos 4))
                    (t (write-char (code-char hi) out)
                       (incf pos 4)))))
               (t (error 'json-parse-error :pos pos :msg "bad escape"))))
           (incf pos))
          (t (write-char ch out) (incf pos)))))))

(defun json-read-object (str pos)
  (let ((len (length str)) (pairs nil))
    (setf pos (json-skip-ws str pos))
    (when (and (< pos len) (char= (char str pos) #\}))
      (return-from json-read-object (values nil (1+ pos))))
    (loop while t do
      (setf pos (json-skip-ws str pos))
      (unless (and (< pos len) (char= (char str pos) #\"))
        (error 'json-parse-error :pos pos :msg "object key must be a string"))
      (multiple-value-bind (key p2) (json-read-string str (1+ pos))
        (setf pos (json-skip-ws str p2))
        (unless (and (< pos len) (char= (char str pos) #\:))
          (error 'json-parse-error :pos pos :msg "object needs :"))
        (multiple-value-bind (val p3) (json-read-value str (1+ pos))
          (push (cons key val) pairs)
          (setf pos (json-skip-ws str p3))
          (unless (< pos len)
            (error 'json-parse-error :pos pos :msg "unterminated object"))
          (let ((ch (char str pos)))
            (cond
              ((char= ch #\,) (incf pos))
              ((char= ch #\}) (return (values (nreverse pairs) (1+ pos))))
              (t (error 'json-parse-error :pos pos :msg "object needs , or }")))))))))

(defun json-read-array (str pos)
  (let ((len (length str)) (items nil))
    (setf pos (json-skip-ws str pos))
    (when (and (< pos len) (char= (char str pos) #\]))
      (return-from json-read-array (values nil (1+ pos))))
    (loop while t do
      (multiple-value-bind (val p2) (json-read-value str pos)
        (push val items)
        (setf pos (json-skip-ws str p2))
        (unless (< pos len)
          (error 'json-parse-error :pos pos :msg "unterminated array"))
        (let ((ch (char str pos)))
          (cond
            ((char= ch #\,) (setf pos (1+ pos)))
            ((char= ch #\]) (return (values (nreverse items) (1+ pos))))
            (t (error 'json-parse-error :pos pos :msg "array needs , or ]"))))))))

(defun read-byte-line (stream)
  "One ASCII line from binary STREAM (CR stripped). Second value is NIL
on EOF before any byte."
  (let ((out (make-string-output-stream)) (got nil))
    (loop for b = (read-byte stream nil nil)
          while (and b (/= b 10))
          do (setf got t)
             (unless (= b 13) (write-char (code-char b) out)))
    (values (get-output-stream-string out) (or got (not (null out))))))

(defun read-byte-headers (stream)
  (loop for (line ok) = (multiple-value-list (read-byte-line stream))
        while (and ok (plusp (length line)))
        collect (let ((colon (position #\: line)))
                  (when colon
                    (cons (string-trim '(#\Space) (subseq line 0 colon))
                          (string-trim '(#\Space #\Return) (subseq line (1+ colon))))))))

(defun read-byte-body (stream nbytes)
  (let ((octets (make-array nbytes :element-type '(unsigned-byte 8))))
    (loop for i from 0 below nbytes
          for b = (read-byte stream nil nil)
          while b do (setf (aref octets i) b)
          finally (return (sb-ext:octets-to-string
                           (if (= i nbytes) octets (subseq octets 0 i))
                           :external-format :utf-8)))))

(defun write-bytes (stream string)
  (write-sequence (sb-ext:string-to-octets string :external-format :utf-8)
                  stream)
  (force-output stream))

(defun handle-client (sock)
  ;; Binary stream throughout: Content-Length counts BYTES, and a
  ;; character stream would block asking for N *characters* when a
  ;; non-ASCII body holds fewer (the old read hung every emoji draft).
  (let* ((stream (sb-bsd-sockets:socket-make-stream sock :input t :output t
                                                    :element-type '(unsigned-byte 8)
                                                    :buffering :none))
         (start (get-internal-real-time)))
    (unwind-protect
         (let* ((request-line (read-byte-line stream))
                (parts (when (plusp (length request-line)) (split-whitespace request-line)))
                (method (first parts))
                (target (second parts))
                (path (when target (first (split-once target "?"))))
                (query (when target (second (split-once target "?"))))
                (headers (read-byte-headers stream))
                (content-length (parse-integer (or (cdr (assoc "content-length" headers :test #'string-equal)) "0") :junk-allowed t))
                (body (when (and content-length (> content-length 0))
                        (read-byte-body stream content-length)))
                (body-json (when (and body (plusp (length body)))
                             (handler-case (json-parse body)
                               (json-parse-error (e)
                                 (list (cons "__parse_error" (princ-to-string e))))))))
           (let ((response
                   (handler-case
                       (cond
                          ((cdr (assoc "__parse_error" body-json :test #'string=))
                           (json-encode-response `(("ok" . nil) ("error" . "bad request json"))))
                          ((and (string= method "GET") (string= path "/ping"))
                           (json-encode-response `(("ok" . t) ("app_name" . "ymacs") ("document_version" . ,(document-version)))))
                          ((and (string= method "GET") (string= path "/pane/doc"))
                           (json-encode-response (document-schema)))
                          ((and (string= method "GET") (string= path "/pane/ymacs"))
                            ;; The ONE rail pane: views multiplex here.
                            ;; The per-view routes below stay as debuggable
                            ;; sub-views of it, never as declared panes.
                            (json-encode-response (sidebar-pane-schema)))
                           ((and (string= method "GET") (string= path "/pane/buffers"))
                           (json-encode-response (buffers-schema)))
                          ((and (string= method "GET") (or (string= path "/pane/which-key") (string= path "/pane/whichkey")))
                           (json-encode-response (which-key-schema query)))
                          ((and (string= method "GET") (string= path "/pane/outline"))
                           (json-encode-response (outline-schema)))
                          ((and (string= method "GET") (string= path "/pane/settings"))
                           (json-encode-response (settings-pane-schema)))
                          ((and (string= method "POST") (string= path "/open"))
                           (let* ((raw (cdr (assoc "path" body-json :test #'string=)))
                                  (result (when raw (ignore-errors (open-file-buffer (pathname raw))))))
                             (if result
                                 (json-encode-response `(("ok" . t) ("id" . ,(buffer-id result)) ("document_version" . ,(document-version))))
                                 (json-encode-response `(("ok" . nil) ("error" . "open failed"))))))
                          ((and (string= method "POST") (string= path "/action"))
                           (let ((reply (handle-action body-json)))
                             (json-encode-response reply)))
                          (t (json-encode-response `(("ok" . nil) ("error" . "not found")))))
                     (error (e) (json-encode-response `(("ok" . nil) ("error" . ,(princ-to-string e))))))))
             (fire-probe :ymacs-control-request :method method :path path
                         :latency-us (round (* 1000000 (/ (- (get-internal-real-time) start) internal-time-units-per-second))))
             (write-response stream 200 response)))
      (ignore-errors (close stream)))))

;;;; NOTE: parse-flat-json is SUPERSEDED on ingress (json-parse owns
;;;; request bodies): it cannot see nested objects. Kept for the tested
;;;; escape-scan behavior only.
(defun parse-flat-json (str)
  (let ((result nil) (i 0) (len (length str)))
    (loop while (< i len) do
      (let ((k1 (position #\" str :start i)))
        (unless k1 (return))
        (let ((k2 (position #\" str :start (1+ k1))))
          (unless k2 (return))
          (let ((key (subseq str (1+ k1) k2)))
            (let ((colon (position #\: str :start (1+ k2))))
              (unless colon (return))
              (let ((vstart (1+ colon)))
                (loop while (and (< vstart len) (member (char str vstart) '(#\Space #\Tab #\Return #\Newline))) do (incf vstart))
                (if (and (< vstart len) (char= (char str vstart) #\"))
                    ;; String value: scan to the CLOSING quote, honouring
                    ;; \" escapes, and UNESCAPE per JSON (\" → ", \\ → \,
                    ;; \n \t \r) — the value the app receives must be the
                    ;; value the client sent. Without unescaping, a form
                    ;; like (string-upcase \"abc\") reached the reader with
                    ;; literal backslash-quotes OUTSIDE string context and
                    ;; could never be read.
                    (let ((v1 vstart) (p (1+ vstart)) (v2 nil))
                      (loop while (and (< p len) (null v2)) do
                        (let ((ch (char str p)))
                          (cond
                            ((and (char= ch #\\) (< (1+ p) len)) (incf p 2))
                            ((char= ch #\") (setf v2 p))
                            (t (incf p)))))
                      (when v2
                        (let ((raw (subseq str (1+ v1) v2)))
                          (declare (dynamic-extent raw))
                          (push (cons key (json-unescape raw)) result))
                        (setf i (1+ v2))))
                    (let ((vend vstart))
                      (loop while (and (< vend len) (not (member (char str vend) '(#\, #\} #\Space #\Tab #\Return #\Newline)))) do (incf vend))
                      (let ((val (string-trim '(#\Space #\Tab #\Return #\Newline) (subseq str vstart vend))))
                        (push (cons key val) result)
                        (setf i vend))))))))))
    (nreverse result)))

(defun json-unescape (s)
  "Decode the JSON string escapes a client may have sent (\\\" \\\\ \\n \\t
\\r); unknown escapes keep the character after the backslash. Values
arrive RAW in the alist — this is the JSON contract, not an option."
  (let ((out (make-string-output-stream)))
    (let ((i 0) (len (length s)))
      (loop while (< i len) do
        (let ((ch (char s i)))
          (if (and (char= ch #\\) (< (1+ i) len))
              (let ((next (char s (1+ i))))
                (cond
                  ((char= next #\") (write-char #\" out))
                  ((char= next #\\) (write-char #\\ out))
                  ((char= next #\n) (write-char #\Newline out))
                  ((char= next #\t) (write-char #\Tab out))
                  ((char= next #\r) (write-char #\Return out))
                  (t (write-char next out)))
                (incf i 2))
              (progn (write-char ch out) (incf i 1))))))
    (get-output-stream-string out)))

(defun extract-json-field (json-str field)
  (cdr (assoc field (parse-flat-json json-str) :test #'string=)))

(defun read-headers (stream)
  (loop for line = (read-line stream nil nil)
        while (and line (not (string= (string-trim '(#\Return #\Space) line) "")))
        collect (let ((colon (position #\: line)))
                  (when colon
                    (cons (string-trim '(#\Space) (subseq line 0 colon))
                          (string-trim '(#\Space #\Return) (subseq line (1+ colon))))))))

(defun split-whitespace (s)
  (let ((out nil) (i 0) (len (length s)))
    (loop while (< i len) do
      (loop while (and (< i len) (member (char s i) '(#\Space #\Tab #\Return #\Newline))) do (incf i))
      (when (< i len)
        (let ((j i))
          (loop while (and (< j len) (not (member (char s j) '(#\Space #\Tab #\Return #\Newline)))) do (incf j))
          (push (subseq s i j) out)
          (setf i j))))
    (nreverse out)))

(defun split-once (s sep)
  (let ((pos (search sep s)))
    (if pos (list (subseq s 0 pos) (subseq s (+ pos (length sep))))
        (list s))))

(defun json-escape-string (s)
  (with-output-to-string (out)
    (loop for ch across s do
      (case ch
        (#\" (write-string "\\\"" out))
        (#\\ (write-string "\\\\" out))
        (#\Newline (write-string "\\n" out))
        (#\Return (write-string "\\r" out))
        (#\Tab (write-string "\\t" out))
        (otherwise (write-char ch out))))))

(defun json-bool (x)
  "Strict JSON boolean for schema slots: the GUI validator rejects null
where it expects a boolean, and Lisp nil is the common nothing. T stays
T, everything else is an explicit false — never null."
  (if x t :false))

(defun settings-get-bool (id fallback)
  "Boolean setting with a compiled FALLBACK: when the book is unreachable
there is no authority, so the shipped default stands in — the schema must
still validate. Reachable book: override-or-default, strictly."
  (if (ignore-errors (settings-schema-path))
      (json-bool (settings-get id))
      (json-bool fallback)))

(defun json-value-encode (v)
  (cond
    ((eq v t) "true")
    ((eq v :false) "false")
    ((null v) "null")
    ((stringp v) (format nil "\"~a\"" (json-escape-string v)))
    ((numberp v) (princ-to-string v))
    ((vectorp v) (format nil "[~{~a~^,~}]" (map 'list #'json-value-encode v)))
    ((and (listp v) (every #'consp v)) (json-encode-response v))
    ((listp v) (format nil "[~{~a~^,~}]" (mapcar #'json-value-encode v)))
    ((hash-table-p v) (json-encode-response (loop for k being the hash-keys of v using (hash-value hv) collect (cons k hv))))
    (t (format nil "\"~a\"" (json-escape-string (princ-to-string v))))))

(defun json-encode-response (obj)
  (cond
    ((and (listp obj) (every #'consp obj))
     (with-output-to-string (out)
       (write-char #\{ out)
       (loop for (pair . rest) on obj
             for (k . v) = pair
             do (format out "\"~a\":~a" (json-escape-string (princ-to-string k)) (json-value-encode v))
             when rest do (write-char #\, out))
       (write-char #\} out)))
    ((hash-table-p obj) (json-encode-response (loop for k being the hash-keys of obj using (hash-value v) collect (cons k v))))
    ((vectorp obj) (json-value-encode obj))
    (t (json-value-encode obj))))

(defun write-response (stream status body)
  ;; Content-Length counts UTF-8 BYTES on the wire, not characters:
  ;; document schemas carry emoji labels (💾 ⚙ 🗂 ⌨), 1 char = 4 bytes.
  ;; (length body) under-counts and truncates every schema fetch.
  (write-bytes stream
               (format nil "HTTP/1.1 ~a OK~C~CContent-Type: application/json~C~CContent-Length: ~a~C~CConnection: close~C~C~C~C~a"
          status #\Return #\Newline #\Return #\Newline (utf8-byte-length body) #\Return #\Newline #\Return #\Newline #\Return #\Newline body)))

(defun document-schema-widgets (base)
  "BASE widgets plus the palette's widgets while a read is in flight."
  (let ((mb (minibuffer-schema-widgets)))
    (if mb
        (coerce (append (coerce base 'list) mb) 'vector)
        base)))

(defun document-toolbar-buttons (buf)
  "The tool-bar-mode buttons, shared by every ribbon. Save reads BUF
(nil when no buffer is current — its primary flag is then false and
the action toasts No file instead of touching anything)."
  (vector
   `(("action" . "save") ("label" . "💾 Save") ("title" . "Save (C-x C-s)")
     ("primary" . ,(json-bool (and buf (buffer-modified-p buf)))))
   `(("action" . "settings") ("label" . "⚙ Settings") ("title" . "Settings (M-x settings)"))
   `(("action" . "toggle-sidebar") ("label" . "🗂 Buffers") ("title" . "Toggle Buffers (C-c s)"))
   `(("action" . "which-key") ("label" . "⌨ Which-Key") ("title" . "Which Key"))))

(defparameter *ribbon-tab* "home"
  "The active ribbon tab (Excel shape: tabs switch the command groups).")

(defun ribbon-group (label &rest args)
  "ARGS is buttons followed by an optional :right marker (the group
right-aligns — Excel's Comments/Share slot)."
  (let* ((right (eq (first (last args)) :right))
         (buttons (if right (butlast args) args)))
    `(("label" . ,label) ("buttons" . ,(apply #'vector buttons))
      ("right" . ,(json-bool right)))))

(defun ribbon-button (action label title &optional primary)
  `(("action" . ,action) ("label" . ,label) ("title" . ,title)
    ("primary" . ,(json-bool primary))))

(defun ribbon-groups (tab buf)
  "The command groups per ribbon tab. Every button fires a REAL action —
named commands through the choke point, or an existing document action.
No decorative chrome; a button that cannot do its thing yet does not
ship (honesty law)."
  (let ((save-primary (and buf (buffer-modified-p buf))))
    (cond
      ((string= tab "edit")
       (vector
        (ribbon-group "Clipboard"
                      (ribbon-button "command:kill-region" "✂ Cut" "Cut region (C-w)")
                      (ribbon-button "command:kill-ring-save" "⧉ Copy" "Copy region (M-w)")
                      (ribbon-button "command:yank" "📋 Paste" "Paste (C-y)")
                      (ribbon-button "command:yank-pop" "⇅ Paste Prev" "Yank pop (M-y)"))
        (ribbon-group "Line"
                      (ribbon-button "command:kill-line" "✂ Kill Line" "Kill to end of line (C-k)"))
        (ribbon-group "Search"
                      (ribbon-button "command:isearch-forward" "🔍 Search" "Search forward (C-s)"))
        (ribbon-group "" (ribbon-button "command:execute-extended-command" "M-x" "Run a command by name" t) :right)))
      ((string= tab "view")
       (vector
        (ribbon-group "Panes"
                      (ribbon-button "toggle-sidebar" "🗂 Buffers" "Toggle the Buffers pane (C-c s)")
                      (ribbon-button "which-key" "⌨ Which-Key" "Which Key"))
        (ribbon-group "System"
                      (ribbon-button "settings" "⚙ Settings" "Settings (M-x settings)")
                      (ribbon-button "command:sidebar/profiles" "◂▸ Profiles" "Switch profile (M-x sidebar/profiles)"))
        (ribbon-group "" (ribbon-button "kill-daemon" "⏻ Quit" "Save buffers and kill ymacs") :right)))
      ((string= tab "help")
       (vector
        (ribbon-group "Documentation"
                      (ribbon-button "command:info" "📖 Manual" "The ymacs manual (Info)"))
        (ribbon-group "" (ribbon-button "about" "ⓘ About" "Version and provenance") :right)))
      (t
       (vector
        (ribbon-group "File"
                      (ribbon-button "command:find-file" "📂 Open" "Find file (C-x C-f)")
                      (ribbon-button "save" "💾 Save" "Save buffer (C-x C-s)" save-primary))
        (ribbon-group "Edit"
                      (ribbon-button "command:undo" "↶ Undo" "Undo (C-/)")
                      (ribbon-button "command:isearch-forward" "🔍 Search" "Search forward (C-s)"))
        (ribbon-group "" (ribbon-button "command:execute-extended-command" "M-x" "Run a command by name" t) :right))))))

(defun ribbon-bar-widget (buf)
  `(("kind" . "ribbon-bar") ("id" . "ribbon")
    ("action" . "ribbon-tab") ("active" . ,*ribbon-tab*)
    ("tabs" . ,(vector `(("id" . "home") ("label" . "Home"))
                       `(("id" . "edit") ("label" . "Edit"))
                       `(("id" . "view") ("label" . "View"))
                       `(("id" . "help") ("label" . "Help"))))
    ("groups" . ,(ribbon-groups *ribbon-tab* buf))))

(defun document-ribbon (buf label-text)
  "The ribbon region for the document schema: an Excel-shape ribbon bar
(tabs over grouped commands) plus the pending-key label, or NIL when
tool-bar-mode is off (the host then gives the card the full rect).
LABEL-TEXT carries the pending key sequence, so the top bar's removal
costs no which-key signal."
  (when *tool-bar-visible*
    (vector
     (ribbon-bar-widget buf)
     `(("kind" . "label") ("text" . ,label-text)))))

(defun document-schema ()
  ;; While settings are open the settings document OWNS the viewport
  ;; (M-x settings); the shell keeps native key handling there — the
  ;; widgets are the interaction, the rail is the section column.
  (if *settings-open*
      (settings-document-schema)
      (let ((buf *current-buffer*))
        (if buf
            (let ((content (buffer-content buf))
                  (id (buffer-id buf))
                  (name (buffer-name buf))
                  (mod (if (buffer-modified-p buf) " — modified" ""))
                  (pending (key-sequence-string)))
              `(("title" . ,(format nil "ymacs — ~a~a" name mod))
                ("key_capture" . t)
                ("ribbon" . ,(document-ribbon
                               buf
                               (format nil "Buffer: ~a~a  •  ~a lines~@[  [~a]~]" name mod (count-lines content) (and (plusp (length pending)) pending))))
                ("widgets" . ,(document-schema-widgets
                               (vector
                                `(("kind" . "text-input") ("id" . "editor") ("multiline" . t)
                                  ("line_numbers" . ,(settings-get-bool "editor.line-numbers" t))
                                  ("word_wrap" . ,(settings-get-bool "editor.word-wrap" t))
                                  ("value" . ,content) ("value_key" . ,id)
                                  ("placeholder" . ";; ymacs — type here, C-x C-s to save, C-c s for Buffers")))))))
            `(("title" . "ymacs")
              ("key_capture" . t)
              ("ribbon" . ,(document-ribbon nil "ymacs — GNU Emacs on libyggterm"))
              ("widgets" . ,(document-schema-widgets
                             (vector
                              `(("kind" . "label") ("text" . "ymacs — GNU Emacs on libyggterm"))
                              `(("kind" . "label") ("muted" . t) ("text" . "No buffer open. Use M-x open-file or the Buffers pane."))))))))))

(defun buffers-schema ()
  (let ((widgets nil))
    (push `(("kind" . "search-box") ("id" . "search") ("placeholder" . "Filter buffers…") ("value" . "") ("action" . "filter-buffers")) widgets)
    (push `(("kind" . "section") ("text" . ,(format nil "Buffers (~a)" (hash-table-count *buffers*)))) widgets)
    (dolist (buf (list-all-buffers))
      (let ((bid (buffer-id buf))
            (title (buffer-name buf))
            (subtitle (if (buffer-file-path buf) (namestring (buffer-file-path buf)) ""))
            (modified (buffer-modified-p buf))
            (active (and *current-buffer* (string= (buffer-id *current-buffer*) (buffer-id buf)))))
        (push `(("kind" . "list-row") ("id" . ,bid) ("title" . ,title) ("subtitle" . ,subtitle)
                ("selected" . ,(json-bool active)) ("status" . ,(if modified "transient" "durable"))
                ("row_action" . "switch-buffer")
                ("actions" . ,(vector `(("action" . "close-buffer") ("label" . "✕") ("title" . "Close"))))
                ("menu" . ,(vector `(("action" . "rename-buffer") ("label" . "Rename"))
                                   `(("action" . "close-buffer") ("label" . "Close"))))
                ) widgets)))
    `(("title" . "Buffers") ("widgets" . ,(coerce (nreverse widgets) 'vector)))))

(defun which-key-schema (query)
  (declare (ignore query))
  (let ((entries (which-key-entries)))
    `(("title" . "Which Key") ("widgets" . ,(coerce (cons `(("kind" . "label") ("text" . "Which-key — pending prefix"))
                                                           (mapcar (lambda (e) `(("kind" . "list-row") ("id" . ,(car e)) ("title" . ,(car e)) ("subtitle" . ,(cdr e)))) entries)) 'vector)))))

(defun outline-schema ()
  (let ((buf *current-buffer*))
    (if (and buf (buffer-content buf))
        (let* ((content (buffer-content buf))
               ;; Node-driven when the buffer is org-mode: the rows come
               ;; from the typed org tree (step 6, spec-primitives §1.1) —
               ;; level indent, workflow keyword, tags. Other buffers keep
               ;; the legacy `*`-line extract.
               (headings (if (and (buffer-major-mode buf)
                                  (string= (buffer-major-mode buf) "org-mode"))
                             (org-outline-rows content)
                             (extract-headings content))))
          `(("title" . "Outline") ("widgets" . ,(coerce (mapcar (lambda (h) `(("kind" . "list-row") ("id" . ,(car h)) ("title" . ,(cdr h)) ("row_action" . "goto-line"))) headings) 'vector))))
        `(("title" . "Outline") ("widgets" . ,(vector `(("kind" . "label") ("muted" . t) ("text" . "No outline"))))))))

(defun extract-headings (content)
  (let (out)
    (loop for line in (split-lines content)
          for i from 1
          when (and (> (length line) 0) (char= (char line 0) #\*))
          do (push (cons (format nil "line-~a" i) (string-trim '(#\Space #\* ) line)) out))
    (nreverse out)))

(defun split-lines (s)
  (loop for start = 0 then (1+ pos)
        for pos = (position #\Newline s :start start)
        collect (subseq s start (or pos (length s)))
        while pos))

(defun handle-action (body-json)
  ;; Settings actions (settings, settings-section, settings-close,
  ;; settings-set:<id>:<value>) are the settings module's namespace.
  (let ((settings (settings-handle-action
                   (cdr (assoc "action" body-json :test #'string=))
                   body-json
                   (cdr (assoc "values" body-json :test #'string=)))))
    (when settings
      (return-from handle-action (second settings))))
  (let* ((action (cdr (assoc "action" body-json :test #'string=)))
         (values-alist (cdr (assoc "values" body-json :test #'string=)))
         (value-keys (cdr (assoc "value_keys" body-json :test #'string=)))
         (target-id (or (cdr (assoc "rename:buffers" values-alist :test #'string=))
                        (cdr (assoc "value" values-alist :test #'string=))
                        (cdr (assoc "editor" values-alist :test #'string=)))))
    (declare (ignore target-id))
    (cond
      ((and action (>= (length action) 11)
            (string= "ribbon-tab:" action :end2 11))
       (let ((tab (subseq action 11)))
         (when (plusp (length tab))
           (setf *ribbon-tab* tab)
           (bump-document-version)
           (fire-probe :ymacs-ribbon :event "tab" :tab tab)))
       `(("ok" . t) ("document_version" . ,(document-version))))
      ((and action (>= (length action) 8)
            (string= "command:" action :end2 8))
       (command-execute-or-prompt
        (intern (string-upcase (subseq action 8)) :ymacs))
       (if *echo-message*
           `(("ok" . t) ("toast" . ,*echo-message*)
             ("document_version" . ,(document-version)))
           `(("ok" . t) ("document_version" . ,(document-version)))))
      ((and action (string= action "about"))
       (setf *echo-message*
             (format nil "ymacs ~a — GNU Emacs on libyggterm (GPL-3)"
                     *ymacs-version*))
       `(("ok" . t) ("toast" . ,*echo-message*)))
      ((and action (string= action "save"))
       (let* ((draft (cdr (assoc "editor" values-alist :test #'string=)))
              (key (cdr (assoc "editor" value-keys :test #'string=)))
              (buf (and key (get-buffer-by-id key))))
         (when (and draft buf)
           (setf (buffer-rope buf) (rope-from-string draft))
           (setf (buffer-modified-p buf) t)
           (persist-draft buf))
         (when (and draft (not buf) *current-buffer*)
           (setf (buffer-rope *current-buffer*) (rope-from-string draft))
           (setf (buffer-modified-p *current-buffer*) t)
           (persist-draft *current-buffer*))
         (let ((toast (when *current-buffer*
                           (let ((res (buffer-save *current-buffer*)))
                             (cond
                               ((eq res :saved) "Saved")
                               ((eq res :conflict) "Conflict — file changed on disk")
                               (t "No file"))))))
            (if toast
                `(("ok" . t) ("toast" . ,toast) ("document_version" . ,(document-version)))
                `(("ok" . t) ("document_version" . ,(document-version)))))))
      ((and action (string= action "switch-buffer"))
       (let ((id (cdr (assoc "value" values-alist :test #'string=))))
         (when id (switch-to-buffer-by-id id))
         `(("ok" . t) ("document_version" . ,(document-version)))))
      ((and action (string= action "close-buffer"))
       (let ((id (cdr (assoc "value" values-alist :test #'string=))))
         (when id (kill-buffer-by-id id))
         `(("ok" . t) ("document_version" . ,(document-version)))))
      ((and action (string= action "filter-buffers"))
       `(("ok" . t)))
      ((and action (string= action "ymacs-switch-profile"))
       (let ((id (or (cdr (assoc "value" values-alist :test #'string=))
                     (cdr (assoc "new-profile" values-alist :test #'string=)))))
         (when (and id (plusp (length id)))
           (ymacs-switch-profile (string-trim '(#\Space #\Tab) id)))
         `(("ok" . t) ("document_version" . ,(document-version)))))
      ((and action (string= action "kill-daemon"))
       (save-buffers-kill-ymacs)
       `(("ok" . t)))
      ((and action (string= action "toggle-sidebar"))
       (toggle-sidebar)
       `(("ok" . t) ("document_version" . ,(sidebar-document-version))))
      ((and action (string= action "which-key"))
       (spawn-sidebar "which-key")
       `(("ok" . t) ("document_version" . ,(sidebar-document-version))))
      ((and action (string= action "key"))
       ;; The key plane (docs/spec-key-plane.md): one chord per POST,
       ;; dispatched through the command layer, fresh schema in the reply.
       (let ((chord (cdr (assoc "key" values-alist :test #'string=))))
         (ymacs-handle-key (or chord ""))))
      ((and action (string= action "minibuffer-accept"))
       ;; RET in the palette's own field.
       (when *minibuffer-active*
         (let ((draft (cdr (assoc "minibuffer" values-alist :test #'string=))))
           (when draft
             (setf *minibuffer-input* draft)
             (minibuffer-refilter))))
       (minibuffer-accept)
       (key-plane-reply))
      ((and action (string= action "minibuffer-select"))
       ;; A clicked candidate: select it by id, then accept. Mouse gestures
       ;; are never recorded — the invocation carries the values.
       (when *minibuffer-active*
         (let ((cand (cdr (assoc "value" values-alist :test #'string=))))
           (let ((pos (position cand *minibuffer-candidates* :test #'string=)))
             (when pos (setf *minibuffer-selected* pos)))
           (when cand
             (setf *minibuffer-input* cand)
             (minibuffer-refilter))
           (minibuffer-accept)))
       (key-plane-reply))
      ((and *minibuffer-active*
            (assoc "minibuffer" values-alist :test #'string=))
       ;; Draft sync from the palette field (native typing fallback).
       (setf *minibuffer-input* (cdr (assoc "minibuffer" values-alist :test #'string=)))
       (minibuffer-refilter)
       (key-plane-reply))
      ((and action (string= action "eval"))
       ;; The headless verb: ymacs --eval posts here (main.lisp CLI).
       ;; v0.1.x had ymacs-verb-eval but NO arm — every --eval silently
       ;; no-opped. Agents drive ymacs through this door; it must answer
       ;; with the result, not a generic ok.
       (let* ((form-string (cdr (assoc "form" body-json :test #'string=)))
              (form (and form-string
                         ;; Read in the ymacs package: a headless form must
                         ;; resolve ymacs symbols (v0.1.x read in whatever
                         ;; *package* the image started in and every symbol
                         ;; uninterned to CL-USER).
                         (let ((*package* (find-package :ymacs)))
                           (ignore-errors (read-from-string form-string))))))
         (if form
             (let ((result (ignore-errors (multiple-value-list (eval form)))))
               (if result
                   `(("ok" . t)
                     ("result" . ,(json-string (format nil "~{~a~^ ; ~}" result)))
                     ("document_version" . ,(document-version)))
                   `(("ok" . t) ("result" . "nil")
                     ("document_version" . ,(document-version)))))
             `(("ok" . nil) ("error" . "unreadable form")))))
      ((and action (string= action "goto-line"))
       ;; Node-driven headline nav: the Outline rows carry the heading's
       ;; 1-based line as their id; the nav MOVES BUFFER POINT (the
       ;; buffer is the truth; pure motion never bumps the version).
       (let* ((value (cdr (assoc "value" values-alist :test #'string=)))
              (n (and value (stringp value)
                      (>= (length value) 5)
                      (string= value "line-" :end1 5 :end2 5)
                      (parse-integer value :start 5 :junk-allowed t))))
         (when (and n *current-buffer*)
           (org-goto-line *current-buffer* n)))
       `(("ok" . t)))
      (t `(("ok" . t) ("document_version" . ,(document-version)))))))

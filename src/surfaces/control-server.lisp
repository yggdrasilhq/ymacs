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

(defun handle-client (sock)
  (let* ((stream (sb-bsd-sockets:socket-make-stream sock :input t :output t
                                                    :element-type 'character
                                                    :external-format :utf-8
                                                    :buffering :none))
         (start (get-internal-real-time)))
    (unwind-protect
         (let* ((request-line (read-line stream nil nil))
                (parts (when request-line (split-whitespace request-line)))
                (method (first parts))
                (target (second parts))
                (path (when target (first (split-once target "?"))))
                (query (when target (second (split-once target "?"))))
                (headers (read-headers stream))
                (content-length (parse-integer (or (cdr (assoc "content-length" headers :test #'string-equal)) "0") :junk-allowed t))
                (body (when (and content-length (> content-length 0))
                        (let ((buf (make-string content-length)))
                          (read-sequence buf stream)
                          buf)))
                (body-json (when body (or (ignore-errors (parse-flat-json body)) (ignore-errors (json-decode body))))))
           (let ((response
                   (handler-case
                       (cond
                          ((and (string= method "GET") (string= path "/ping"))
                           (json-encode-response `(("ok" . t) ("app_name" . "ymacs") ("document_version" . ,(document-version)))))
                          ((and (string= method "GET") (string= path "/pane/doc"))
                           (json-encode-response (document-schema)))
                          ((and (string= method "GET") (string= path "/pane/buffers"))
                           (json-encode-response (buffers-schema)))
                          ((and (string= method "GET") (or (string= path "/pane/which-key") (string= path "/pane/whichkey")))
                           (json-encode-response (which-key-schema query)))
                          ((and (string= method "GET") (string= path "/pane/outline"))
                           (json-encode-response (outline-schema)))
                          ((and (string= method "GET") (string= path "/pane/settings"))
                           (json-encode-response (settings-pane-schema)))
                          ((and (string= method "POST") (string= path "/open"))
                           (let* ((raw (or (cdr (assoc "path" body-json :test #'string=))
                                           (extract-json-field body "path")))
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

(defun json-value-encode (v)
  (cond
    ((eq v t) "true")
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
  (format stream "HTTP/1.1 ~a OK~C~CContent-Type: application/json~C~CContent-Length: ~a~C~CConnection: close~C~C~C~C~a"
          status #\Return #\Newline #\Return #\Newline (length body) #\Return #\Newline #\Return #\Newline #\Return #\Newline body)
  (force-output stream))

(defun document-schema-widgets (base)
  "BASE widgets plus the palette's widgets while a read is in flight."
  (let ((mb (minibuffer-schema-widgets)))
    (if mb
        (coerce (append (coerce base 'list) mb) 'vector)
        base)))

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
                ("widgets" . ,(document-schema-widgets
                               (vector
                                `(("kind" . "label") ("text" . ,(format nil "Buffer: ~a~a  •  ~a lines~@[  [~a]~]" name mod (count-lines content) (and (plusp (length pending)) pending))) ("muted" . t))
                                `(("kind" . "text-input") ("id" . "editor") ("multiline" . t)
                                  ("line_numbers" . ,(settings-get "editor.line-numbers"))
                                  ("word_wrap" . ,(settings-get "editor.word-wrap"))
                                  ("value" . ,content) ("value_key" . ,id)
                                  ("placeholder" . ";; ymacs — type here, C-x C-s to save, C-c s for Buffers"))
                                `(("kind" . "toolbar") ("id" . "doc-toolbar")
                                  ("buttons" . ,(vector
                                                 `(("action" . "save") ("label" . "💾 Save") ("title" . "Save (C-x C-s)") ("primary" . ,(buffer-modified-p buf)))
                                                 `(("action" . "settings") ("label" . "⚙ Settings") ("title" . "Settings (M-x settings)"))
                                                 `(("action" . "toggle-sidebar") ("label" . "🗂 Buffers") ("title" . "Toggle Buffers (C-c s)"))
                                                 `(("action" . "which-key") ("label" . "⌨ Which-Key") ("title" . "Which Key"))))))))))
            `(("title" . "ymacs")
              ("key_capture" . t)
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
                ("selected" . ,active) ("status" . ,(if modified "transient" "durable"))
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
                        (cdr (assoc "value" body-json :test #'string=))
                        (cdr (assoc "editor" values-alist :test #'string=)))))
    (declare (ignore target-id))
    (cond
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
         (when *current-buffer*
           (let ((res (buffer-save *current-buffer*)))
             (cond
               ((eq res :saved) `(( "toast" . "Saved")))
               ((eq res :conflict) `(( "toast" . "Conflict — file changed on disk") ("conflict" . t)))
               (t `(( "toast" . "No file"))))))
         `(("ok" . t) ("document_version" . ,(document-version)))))
      ((and action (string= action "switch-buffer"))
       (let ((id (cdr (assoc "value" body-json :test #'string=))))
         (when id (switch-to-buffer id))
         `(("ok" . t) ("document_version" . ,(document-version)))))
      ((and action (string= action "close-buffer"))
       (let ((id (cdr (assoc "value" body-json :test #'string=))))
         (when id (kill-buffer id))
         `(("ok" . t) ("document_version" . ,(document-version)))))
      ((and action (string= action "filter-buffers"))
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
         (let ((cand (cdr (assoc "value" body-json :test #'string=))))
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
       (let* ((value (cdr (assoc "value" body-json :test #'string=)))
              (n (and value (stringp value)
                      (>= (length value) 5)
                      (string= value "line-" :end1 5 :end2 5)
                      (parse-integer value :start 5 :junk-allowed t))))
         (when (and n *current-buffer*)
           (org-goto-line *current-buffer* n)))
       `(("ok" . t)))
      (t `(("ok" . t) ("document_version" . ,(document-version)))))))

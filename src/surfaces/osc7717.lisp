;;;; osc7717.lisp --- libyggterm OSC 7717 escape emitter
;;;; Contract: ESC ] 7717 ; <verb> ; <action> ; <base64-json> BEL

(in-package #:ymacs)

(defvar *ymacs-session-id* nil)

(defun ymacs-session-id ()
  (or *ymacs-session-id*
      (sb-ext:posix-getenv "YGGTERM_SESSION_ID")
      (sb-ext:posix-getenv "LC_YGGTERM_SESSION_ID")
      ""))

(defun base64-encode (str)
  (let* ((alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
         (bytes (map 'vector #'char-code str))
         (out (make-string-output-stream))
         (len (length bytes)))
    (loop for i from 0 below len by 3
          for b0 = (aref bytes i)
          for b1 = (if (< (1+ i) len) (aref bytes (1+ i)) 0)
          for b2 = (if (< (+ i 2) len) (aref bytes (+ i 2)) 0)
          for remaining = (- len i)
          do (let* ((n (logior (ash b0 16) (ash b1 8) b2))
                    (c0 (aref alphabet (ldb (byte 6 18) n)))
                    (c1 (aref alphabet (ldb (byte 6 12) n)))
                    (c2 (aref alphabet (ldb (byte 6 6) n)))
                    (c3 (aref alphabet (ldb (byte 6 0) n))))
               (write-char c0 out)
               (write-char c1 out)
               (if (< remaining 2) (write-char #\= out) (write-char c2 out))
               (if (< remaining 3) (write-char #\= out) (write-char c3 out))))
    (get-output-stream-string out)))

(defun emit-osc-7717 (verb action payload-json)
  (let ((encoded (base64-encode payload-json)))
    (format t "~c]7717;~a;~a;~a~c" (code-char 27) verb action encoded (code-char 7))
    (force-output)))

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

(defun json-string (obj)
  (cond
    ((null obj) "null")
    ((stringp obj) (format nil "\"~a\"" (json-escape-string obj)))
    ((numberp obj) (princ-to-string obj))
    ((eq obj t) "true")
    ((consp obj)
     (if (and (consp (car obj)) (stringp (caar obj)))
         (format nil "{~{~a~^,~}}" (mapcar (lambda (pair) (format nil "\"~a\":~a" (car pair) (json-string (cdr pair)))) obj))
         (format nil "[~{~a~^,~}]" (mapcar #'json-string obj))))
    ((vectorp obj) (format nil "[~{~a~^,~}]" (map 'list #'json-string obj)))
    ((hash-table-p obj)
     (let (pairs) (maphash (lambda (k v) (push (cons (princ-to-string k) v) pairs)) obj) (json-string pairs)))
    (t (format nil "\"~a\"" (json-escape-string (princ-to-string obj))))))

(defun emit-declare (session control document-version)
  (let* ((title (if *current-buffer* (buffer-name *current-buffer*) "ymacs"))
         (payload (format nil "{\"session\":\"~a\",\"control\":\"~a\",\"app_name\":\"ymacs\",\"document_version\":\"~a\",\"panes\":[{\"id\":\"doc\",\"icon\":\"📝\",\"title\":\"ymacs — ~a\",\"placement\":\"viewport\"},{\"id\":\"buffers\",\"icon\":\"🗂\",\"title\":\"Buffers\",\"placement\":\"rail\"},{\"id\":\"which-key\",\"icon\":\"⌨\",\"title\":\"Which Key\",\"placement\":\"rail\"},{\"id\":\"outline\",\"icon\":\"≡\",\"title\":\"Outline\",\"placement\":\"rail\"}]}"
                          (json-escape-string session)
                          (json-escape-string control)
                          (json-escape-string document-version)
                          (json-escape-string title))))
    (emit-osc-7717 "sidebar" "declare" payload)))

(defun emit-close (session)
  (let ((payload (format nil "{\"session\":\"~a\"}" (json-escape-string session))))
    (emit-osc-7717 "sidebar" "close" payload)))

(defun ymacs-buffer-display-name (buf)
  (if buf (buffer-name buf) " *scratch*"))

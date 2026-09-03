;;;; osc7717.lisp --- libyggterm OSC 7717 escape emitter
;;;; Contract: ESC ] 7717 ; <verb> ; <action> ; <base64-json> BEL

(in-package #:ymacs)

(defvar *ymacs-session-id* nil)

(defun ymacs-session-id ()
  (or *ymacs-session-id*
      (sb-ext:posix-getenv "YGGTERM_SESSION_ID")
      (sb-ext:posix-getenv "LC_YGGTERM_SESSION_ID")
      ""))

(defun utf8-bytes (str)
  "UTF-8 octets of STR. The OSC channel and HTTP both count BYTES —
char-codes are not bytes once a pane icon leaves ASCII (📝 is 1 char,
4 bytes: F0 9F 93 9D). The old base64 fed char-codes straight into the
6-bit groups, so every declare carrying an emoji decoded to invalid
UTF-8 and the GUI dropped it silently — `ymacs` printed 'surface
opened' over a declare nothing could parse."
  (sb-ext:string-to-octets str :external-format :utf-8))

(defun utf8-byte-length (str)
  (length (utf8-bytes str)))

(defun base64-encode (str)
  (let* ((alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
         (bytes (utf8-bytes str))
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

(defun base64-decode-to-octets (str)
  "Decode base64 STR to a byte vector. Test-only inverse of base64-encode: lets the contract test prove the declare round-trips through UTF-8."
  (let* ((alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
         (vals (make-array 128 :initial-element 0))
         (out (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0)))
    (loop for i from 0 below (length alphabet)
          do (setf (aref vals (char-code (char alphabet i))) i))
    (loop for i from 0 below (length str) by 4
          for c0 = (aref vals (char-code (char str i)))
          for c1 = (aref vals (char-code (char str (+ i 1))))
          for ch2 = (char str (+ i 2))
          for ch3 = (char str (+ i 3))
          for c2 = (if (char= ch2 #\=) 0 (aref vals (char-code ch2)))
          for c3 = (if (char= ch3 #\=) 0 (aref vals (char-code ch3)))
          for n = (logior (ash c0 18) (ash c1 12) (ash c2 6) c3)
          do (vector-push-extend (ldb (byte 8 16) n) out)
          when (char/= ch2 #\=) do (vector-push-extend (ldb (byte 8 8) n) out)
          when (char/= ch3 #\=) do (vector-push-extend (ldb (byte 8 0) n) out))
    out))

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
         (payload (format nil "{\"session\":\"~a\",\"control\":\"~a\",\"app_name\":\"ymacs\",\"document_version\":\"~a\",\"panes\":[{\"id\":\"doc\",\"icon\":\"📝\",\"title\":\"ymacs — ~a\",\"placement\":\"viewport\"},{\"id\":\"buffers\",\"icon\":\"🗂\",\"title\":\"Buffers\",\"placement\":\"rail\"},{\"id\":\"which-key\",\"icon\":\"⌨\",\"title\":\"Which Key\",\"placement\":\"rail\"},{\"id\":\"outline\",\"icon\":\"≡\",\"title\":\"Outline\",\"placement\":\"rail\"},{\"id\":\"settings\",\"icon\":\"⚙\",\"title\":\"Settings\",\"placement\":\"rail\"}]}"
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

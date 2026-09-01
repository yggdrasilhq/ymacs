;;;; modeline.lisp --- Mode line for ymacs
;;;; Like Emacs, the mode line shows buffer name, major mode, position, and
;;;; VC info. In libyggterm it is a footer widget pinned at rail bottom.

(in-package #:ymacs)

(defun mode-line-format (buf)
  (let* ((name (if buf (buffer-name buf) "*scratch*"))
         (mode (if buf (buffer-major-mode buf) "fundamental"))
         (mod (if (and buf (buffer-modified-p buf)) "**" "--"))
         (ro (if buf "" "%%"))
         (line (if buf (1+ (count #\Newline (buffer-content buf) :end (buffer-point buf))) 1))
         (col (if buf (let ((content (buffer-content buf)) (pt (buffer-point buf)))
                        (1+ (- pt (or (position #\Newline content :end pt :from-end t) -1))))
                    1))
         (pct (if buf (let ((len (length (buffer-content buf))))
                        (if (zerop len) "Top" (format nil "~a%" (round (* 100 (/ (buffer-point buf) (max 1 len)))))))
                  "All")))
    (format nil "~a ~a:%s  (~a)  L~a C~a  ~a  ymacs" mod ro mode line col pct)))

(defun mode-line-widgets (buf)
  (vector
   `(( "kind" . "label") ("text" . ,(mode-line-format buf)) ("muted" . t))
   `(( "kind" . "button") ("id" . "modeline-buffers") ("label" . "Buffers") ("action" . "toggle-sidebar"))))

(defun header-line-format (buf)
  (when buf
    (let ((file (when (buffer-file-path buf) (namestring (buffer-file-path buf)))))
      (if file (format nil "~a" file) (format nil "~a" (buffer-name buf))))))

(defun vc-mode-line (buf)
  (declare (ignore buf))
  "")

(defun which-function-mode-line (buf)
  (declare (ignore buf))
  "")

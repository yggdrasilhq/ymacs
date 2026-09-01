;;;; python-mode.lisp --- Python mode for ymacs

(in-package #:ymacs)

(define-major-mode "python-mode"
  :doc "Python mode — indentation, REPL, lint."
  :hook (lambda (buf) (declare (ignore buf)) t))

(defvar *python-indent-offset* 4)
(defvar *python-shell-interpreter* "python3")

(defun python-indent-line (buf)
  (let* ((content (buffer-content buf))
         (pt (buffer-point buf))
         (line-start (or (position #\Newline content :end pt :from-end t) 0))
         (prev-line-end line-start)
         (prev-line-start (or (position #\Newline content :end (max 0 (1- line-start)) :from-end t) 0))
         (prev-line (when (> line-start 0) (subseq content prev-line-start prev-line-end)))
         (prev-indent (if prev-line (length (subseq prev-line 0 (- (length prev-line) (length (string-trim '(#\Space #\Tab) prev-line))))) 0))
         (prev-trimmed (if prev-line (string-trim '(#\Space #\Tab #\Newline) prev-line) ""))
         (current-line (subseq content line-start (or (position #\Newline content :start pt) (length content))))
         (current-trimmed (string-trim '(#\Space #\Tab) current-line))
         (increase (and prev-trimmed (char= (char prev-trimmed (1- (length prev-trimmed))) #\:)))
         (decrease (and current-trimmed (or (search "return" current-trimmed) (search "break" current-trimmed) (search "continue" current-trimmed) (search "pass" current-trimmed)))))
    (let ((new-indent (cond (increase (+ prev-indent *python-indent-offset*))
                            (decrease (max 0 (- prev-indent *python-indent-offset*)))
                            (t prev-indent))))
      (let ((trimmed (string-trim '(#\Space #\Tab) current-line)))
        (buffer-delete buf line-start (length current-line))
        (buffer-insert buf line-start (format nil "~a~a" (make-string new-indent :initial-element #\Space) trimmed))
        (setf (buffer-point buf) (+ line-start new-indent (length trimmed)))))))

(defun python-shell-send-buffer (buf)
  (let ((content (buffer-content buf)))
    (eshell-send-input (or (find-if (lambda (b) (string= (buffer-major-mode b) "eshell-mode")) (list-all-buffers))
                           (eshell))
                       (format nil "~a -c ~a" *python-shell-interpreter* (cl:write-to-string content)))))

(defun python-check-syntax (buf)
  (let ((path (when (buffer-file-path buf) (namestring (buffer-file-path buf)))))
    (when path
      (let ((result (with-output-to-string (out)
                      (sb-ext:run-program *python-shell-interpreter* (list "-m" "py_compile" path) :output out :error out :search t :wait t))))
        (if (string= result "") "OK" result)))))

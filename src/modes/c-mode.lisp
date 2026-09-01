;;;; c-mode.lisp --- C/C++ mode for ymacs

(in-package #:ymacs)

(define-major-mode "c-mode"
  :doc "C mode."
  :hook (lambda (buf) (declare (ignore buf)) t))

(define-major-mode "c++-mode"
  :doc "C++ mode."
  :parent "c-mode")

(defvar *c-indent-offset* 4)
(defvar *c-continued-statement-offset* 4)

(defun c-indent-line (buf)
  (let* ((content (buffer-content buf))
         (pt (buffer-point buf))
         (line-start (or (position #\Newline content :end pt :from-end t) 0))
         (line-end (or (position #\Newline content :start pt) (length content)))
         (line (subseq content line-start line-end))
         (trimmed (string-trim '(#\Space #\Tab) line))
         (prev-line-start (or (position #\Newline content :end (max 0 (1- line-start)) :from-end t) 0))
         (prev-line (when (> line-start 0) (subseq content prev-line-start line-start)))
         (prev-trimmed (when prev-line (string-trim '(#\Space #\Tab #\Newline) prev-line))))
    (let ((indent 0))
      (when prev-trimmed
        (let ((prev-indent (- (length prev-line) (length (string-trim '(#\Space #\Tab) prev-line)))))
          (cond
            ((and (> (length prev-trimmed) 0) (char= (char prev-trimmed (1- (length prev-trimmed))) #\{))
             (setf indent (+ prev-indent *c-indent-offset*)))
            ((and (> (length trimmed) 0) (char= (char trimmed 0) #\}))
             (setf indent (max 0 (- prev-indent *c-indent-offset*))))
            ((and prev-trimmed (char= (char prev-trimmed (1- (length prev-trimmed))) #\;))
             (setf indent prev-indent))
            (t (setf indent prev-indent)))))
      (buffer-delete buf line-start (length line))
      (buffer-insert buf line-start (format nil "~a~a" (make-string indent :initial-element #\Space) trimmed))
      (setf (buffer-point buf) (+ line-start indent (length trimmed))))))

(defun c-font-lock-keywords ()
  '("if" "else" "for" "while" "do" "switch" "case" "break" "continue" "return"
    "struct" "union" "enum" "typedef" "static" "extern" "const" "volatile"
    "int" "char" "float" "double" "void" "long" "short" "unsigned" "signed"
    "class" "public" "private" "protected" "virtual" "override" "template" "typename"
    "namespace" "using" "new" "delete" "try" "catch" "throw"))

(defun c-mode-hook (buf)
  (set-buffer-major-mode buf "c-mode")
  t)

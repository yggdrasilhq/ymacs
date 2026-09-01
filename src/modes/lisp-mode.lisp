;;;; lisp-mode.lisp --- Lisp interaction mode for ymacs

(in-package #:ymacs)

(define-major-mode "lisp-interaction-mode"
  :doc "Lisp Interaction — eval in scratch."
  :parent "lisp-mode")

(define-major-mode "emacs-lisp-mode"
  :doc "Emacs Lisp mode."
  :parent "lisp-mode")

(defvar *lisp-indent-width* 2)
(defvar *lisp-paren-highlight* t)
(defvar *lisp-repl-history* nil)

(defun lisp-calculate-indent (content pos)
  (let ((depth 0) (in-string nil) (escape nil))
    (loop for i from 0 below pos
          for ch = (char content i)
          do (cond (escape (setf escape nil))
                   ((char= ch #\\) (setf escape t))
                   ((char= ch #\") (setf in-string (not in-string)))
                   ((and (not in-string) (char= ch #\()) (incf depth))
                   ((and (not in-string) (char= ch #\))) (decf depth))))
    (* depth *lisp-indent-width*)))

(defun lisp-indent-line (buf)
  (let* ((content (buffer-content buf))
         (pt (buffer-point buf))
         (line-start (or (position #\Newline content :end pt :from-end t) 0))
         (line-end (or (position #\Newline content :start pt) (length content)))
         (line (subseq content line-start line-end))
         (indent (lisp-calculate-indent content line-start))
         (current-indent (- (length line) (length (string-trim '(#\Space #\Tab) line)))))
    (unless (= current-indent indent)
      (let ((trimmed (string-trim '(#\Space #\Tab) line)))
        (buffer-delete buf line-start (length line))
        (buffer-insert buf line-start (format nil "~a~a" (make-string indent :initial-element #\Space) trimmed))
        (setf (buffer-point buf) (+ line-start indent (length trimmed)))))))

(defun lisp-forward-sexp (buf)
  (let* ((content (buffer-content buf))
         (pt (buffer-point buf))
         (len (length content))
         (depth 0) (in-string nil) (started nil) (result nil))
    (loop for i from pt below len
          for ch = (char content i)
          do (cond ((char= ch #\") (setf in-string (not in-string)))
                   ((and (not in-string) (char= ch #\()) (incf depth) (setf started t))
                   ((and (not in-string) (char= ch #\))) (decf depth)
                    (when (and started (zerop depth))
                      (setf (buffer-point buf) (1+ i))
                      (setf result i)
                      (return)))))
    (unless started
      (let ((next (position-if (lambda (c) (member c '(#\Space #\Newline #\Tab #\( #\)))) content :start pt)))
        (when next (setf (buffer-point buf) next) (setf result next))))
    result))

(defun lisp-backward-sexp (buf)
  (let* ((content (buffer-content buf))
         (pt (buffer-point buf))
         (depth 0) (in-string nil) (result nil))
    (loop for i from (1- pt) downto 0
          for ch = (char content i)
          do (cond ((char= ch #\") (setf in-string (not in-string)))
                   ((and (not in-string) (char= ch #\))) (incf depth))
                   ((and (not in-string) (char= ch #\()) (decf depth)
                    (when (zerop depth)
                      (setf (buffer-point buf) i)
                      (setf result i)
                      (return)))))
    result))

(defun lisp-eval-last-sexp (buf)
  (let* ((content (buffer-content buf))
         (pt (buffer-point buf))
         (start (let ((p pt))
                  (lisp-backward-sexp buf)
                  (prog1 (buffer-point buf) (setf (buffer-point buf) p))))
         (end pt)
         (form-str (when (and start end (< start end)) (subseq content start end))))
    (when form-str
      (let ((result (ignore-errors (eval (read-from-string form-str)))))
        (buffer-insert buf pt (format nil " => ~a" result))
        result))))

(defun lisp-eval-buffer (buf)
  (let ((content (buffer-content buf)))
    (handler-case
        (with-input-from-string (s content)
          (loop for form = (read s nil nil)
                while form
                do (eval form)
                finally (return t)))
      (error (e) (format nil "Error: ~a" e)))))

(defun lisp-describe-function (sym)
  (when (fboundp sym)
    (let ((doc (documentation sym 'function)))
      (format nil "~a: ~a" sym (or doc "No documentation")))))

(defun lisp-find-definition (sym)
  (declare (ignore sym))
  nil)

(defun lisp-complete-symbol (prefix)
  (let ((pkg (find-package :ymacs)))
    (remove-if-not (lambda (sym)
                     (let ((name (symbol-name sym)))
                       (and (>= (length name) (length prefix))
                            (string-equal prefix (subseq name 0 (length prefix))))))
                   (loop for sym being the symbols in pkg collect sym))))

(defun lisp-mode-hook (buf)
  (set-buffer-major-mode buf "lisp-mode")
  (local-set-key "lisp-mode" "C-M-f" 'lisp-forward-sexp)
  (local-set-key "lisp-mode" "C-M-b" 'lisp-backward-sexp)
  (local-set-key "lisp-mode" "C-x C-e" 'lisp-eval-last-sexp)
  (local-set-key "lisp-mode" "C-c C-c" 'lisp-eval-buffer)
  t)

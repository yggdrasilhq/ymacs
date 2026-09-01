;;;; macro.lisp --- Keyboard macros for ymacs

(in-package #:ymacs)

(defvar *last-kbd-macro* nil)
(defvar *recording-macro* nil)
(defvar *macro-counter* 0)
(defvar *kbd-macro-ring* nil)
(defvar *kbd-macro-ring-max* 10)

(defun start-kbd-macro (arg)
  (declare (ignore arg))
  (setf *recording-macro* t
        *last-kbd-macro* nil)
  (fire-probe :ymacs-macro :event "start"))

(defun end-kbd-macro (&optional arg)
  (declare (ignore arg))
  (setf *recording-macro* nil)
  (when *last-kbd-macro*
    (push *last-kbd-macro* *kbd-macro-ring*)
    (when (> (length *kbd-macro-ring*) *kbd-macro-ring-max*)
      (setf *kbd-macro-ring* (subseq *kbd-macro-ring* 0 *kbd-macro-ring-max*))))
  (fire-probe :ymacs-macro :event "end")
  *last-kbd-macro*)

(defun call-last-kbd-macro (&optional prefix)
  (let ((repeat (if (numberp prefix) prefix 1)))
    (loop repeat repeat do
      (dolist (cmd *last-kbd-macro*)
        (ignore-errors (funcall cmd))))
    t))

(defun kbd-macro-query (arg)
  (declare (ignore arg))
  (call-last-kbd-macro))

(defun name-last-kbd-macro (symbol)
  (setf (symbol-function symbol) (lambda (&optional arg) (call-last-kbd-macro arg))))

(defun insert-kbd-macro (symbol)
  (format nil "(fset '~a (lambda (&optional arg) (call-last-kbd-macro arg)))" symbol))

(defun kmacro-start-macro (arg) (start-kbd-macro arg))
(defun kmacro-end-macro (arg) (end-kbd-macro arg))
(defun kmacro-end-and-call-macro (arg)
  (end-kbd-macro arg)
  (call-last-kbd-macro arg))

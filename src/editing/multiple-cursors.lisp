;;;; multiple-cursors.lisp --- Multiple cursors for ymacs
;;;; Like Emacs multiple-cursors, but with ymacs rope buffers.

(in-package #:ymacs)

(defstruct cursor
  buffer pos mark)

(defvar *extra-cursors* nil)
(defvar *multiple-cursors-enabled* nil)

(defun mc/create-cursor (buf pos)
  (make-cursor :buffer buf :pos pos :mark pos))

(defun mc/add-cursor-at-point (buf)
  (push (mc/create-cursor buf (buffer-point buf)) *extra-cursors*)
  (setf *multiple-cursors-enabled* t)
  (fire-probe :ymacs-mc :action "add" :count (length *extra-cursors*))
  *extra-cursors*)

(defun mc/add-cursor-at-search (buf pattern)
  (let ((content (buffer-content buf)) (pos 0))
    (loop while (setf pos (cl:search pattern content :start2 pos))
          do (progn
               (push (mc/create-cursor buf pos) *extra-cursors*)
               (incf pos (length pattern))))
    (setf *multiple-cursors-enabled* (plusp (length *extra-cursors*)))
    *extra-cursors*))

(defun mc/remove-last-cursor ()
  (pop *extra-cursors*)
  (when (null *extra-cursors*) (setf *multiple-cursors-enabled* nil)))

(defun mc/remove-all-cursors ()
  (setf *extra-cursors* nil
        *multiple-cursors-enabled* nil))

(defun mc/for-each-cursor (fn)
  (dolist (cursor *extra-cursors*)
    (let ((buf (cursor-buffer cursor)))
      (setf (buffer-point buf) (cursor-pos cursor))
      (funcall fn buf)
      (setf (cursor-pos cursor) (buffer-point buf)))))

(defun mc/insert-at-cursors (text)
  (mc/for-each-cursor (lambda (buf) (buffer-insert buf (buffer-point buf) text))))

(defun mc/delete-at-cursors (len)
  (mc/for-each-cursor (lambda (buf) (buffer-delete buf (buffer-point buf) len))))

(defun mc/edit-lines (buf)
  (let ((content (buffer-content buf))
        (lines (split-lines (buffer-content buf))))
    (setf *extra-cursors* nil)
    (loop for line in lines
          for i from 0
          for pos = 0 then (+ pos (length line) 1)
          do (push (mc/create-cursor buf pos) *extra-cursors*))
    (setf *multiple-cursors-enabled* t)))

(defun mc/mark-next-like-this (buf)
  (let* ((content (buffer-content buf))
         (pt (buffer-point buf))
         (mark (buffer-mark buf))
         (word (when (and pt mark) (subseq content (min pt mark) (max pt mark)))))
    (when word
      (let ((next (cl:search word content :start2 (max pt mark))))
        (when next
          (push (mc/create-cursor buf next) *extra-cursors*)
          (setf (buffer-point buf) next
                (buffer-mark buf) (+ next (length word))))))))

(defun mc/num-cursors ()
  (1+ (length *extra-cursors*)))

;;;; undo.lisp --- Undo/redo for ymacs buffers
;;;; Each buffer maintains an undo stack of rope snapshots + point.
;;;; Like Emacs, undo is itself undoable (redo). Limit 1000 entries.

(in-package #:ymacs)

(defstruct undo-entry
  rope point mark timestamp)

(defvar *undo-limit* 1000)

(defun buffer-undo-stack (buf)
  (gethash (buffer-id buf) *undo-stacks*))

(defun ensure-undo-stack (buf)
  (unless (gethash (buffer-id buf) *undo-stacks*)
    (setf (gethash (buffer-id buf) *undo-stacks*) nil))
  (gethash (buffer-id buf) *undo-stacks*))

(defvar *undo-stacks* (make-hash-table :test 'equal))
(defvar *redo-stacks* (make-hash-table :test 'equal))

(defun push-undo (buf)
  (let ((stack (ensure-undo-stack buf)))
    (push (make-undo-entry :rope (buffer-rope buf)
                           :point (buffer-point buf)
                           :mark (buffer-mark buf)
                           :timestamp (get-universal-time))
          stack)
    (when (> (length stack) *undo-limit*)
      (setf (gethash (buffer-id buf) *undo-stacks*) (subseq stack 0 *undo-limit*)))
    ;; Clear redo on new edit
    (setf (gethash (buffer-id buf) *redo-stacks*) nil)))

(defun buffer-undo (buf)
  (let ((stack (gethash (buffer-id buf) *undo-stacks*)))
    (when stack
      (let ((entry (pop stack)))
        (setf (gethash (buffer-id buf) *undo-stacks*) stack)
        ;; Save current to redo
        (push (make-undo-entry :rope (buffer-rope buf)
                               :point (buffer-point buf)
                               :mark (buffer-mark buf)
                               :timestamp (get-universal-time))
              (gethash (buffer-id buf) *redo-stacks*))
        (setf (buffer-rope buf) (undo-entry-rope entry)
              (buffer-point buf) (undo-entry-point entry)
              (buffer-mark buf) (undo-entry-mark entry)
              (buffer-modified-p buf) t)
        (bump-document-version)
        t))))

(defun buffer-redo (buf)
  (let ((stack (gethash (buffer-id buf) *redo-stacks*)))
    (when stack
      (let ((entry (pop stack)))
        (setf (gethash (buffer-id buf) *redo-stacks*) stack)
        (push (make-undo-entry :rope (buffer-rope buf)
                               :point (buffer-point buf)
                               :mark (buffer-mark buf)
                               :timestamp (get-universal-time))
              (gethash (buffer-id buf) *undo-stacks*))
        (setf (buffer-rope buf) (undo-entry-rope entry)
              (buffer-point buf) (undo-entry-point entry)
              (buffer-mark buf) (undo-entry-mark entry)
              (buffer-modified-p buf) t)
        (bump-document-version)
        t))))

;; Hook into buffer operations
(defun buffer-insert-with-undo (buf pos text)
  (push-undo buf)
  (buffer-insert buf pos text))

(defun buffer-delete-with-undo (buf pos len)
  (push-undo buf)
  (buffer-delete buf pos len))

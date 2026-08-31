;;;; buffer.lisp --- Buffer engine and text rope management

(in-package #:ymacs)

(defstruct buffer
  id
  name
  file-path
  content
  point
  mark
  modified-p
  value-key)

(defvar *buffers* (make-hash-table :test 'equal))
(defvar *current-buffer* nil)

(defun make-new-buffer (name &optional content)
  (let* ((id (format nil "buf-~a" (get-universal-time)))
         (buf (make-buffer :id id
                           :name name
                           :content (or content "")
                           :point 0
                           :mark 0
                           :modified-p nil
                           :value-key id)))
    (setf (gethash id *buffers*) buf)
    (unless *current-buffer*
      (setf *current-buffer* buf))
    buf))

(defun get-buffer-by-id (id)
  (gethash id *buffers*))

(defun list-all-buffers ()
  (loop for v being the hash-values of *buffers* collect v))

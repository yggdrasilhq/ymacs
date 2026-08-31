;;;; sidebar.lisp --- Single sidebar management (max 1 in view)

(in-package #:ymacs)

(defvar *sidebar-visible* nil)
(defvar *current-sidebar-pane* "buffers")

(defun sidebar-visible-p ()
  *sidebar-visible*)

(defun spawn-sidebar (&optional (pane "buffers"))
  (setf *sidebar-visible* t
        *current-sidebar-pane* pane)
  (format t "~&[ymacs] Spawned single sidebar pane: ~a~%" pane))

(defun despawn-sidebar ()
  (setf *sidebar-visible* nil)
  (format t "~&[ymacs] Despawned sidebar~%"))

(defun toggle-sidebar (&optional (pane "buffers"))
  (if (and *sidebar-visible* (string= *current-sidebar-pane* pane))
      (despawn-sidebar)
      (spawn-sidebar pane)))

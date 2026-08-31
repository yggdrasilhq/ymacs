;;;; sidebar.lisp --- Single sidebar management (max 1 in view)
;;;; Invariant: at most ONE sidebar pane is visible. Spawning a second
;;;; replaces the first; despawn hides all. The pane list is declared via
;;;; OSC 7717 sidebar;declare — the GUI fetches GET /pane/<id>.

(in-package #:ymacs)

(defvar *sidebar-visible* nil)
(defvar *current-sidebar-pane* "buffers")
(defvar *available-panes* '("buffers" "outline" "project" "which-key"))
(defvar *sidebar-epoch* 0)

(defun sidebar-visible-p () *sidebar-visible*)

(defun available-panes () *available-panes*)

(defun spawn-sidebar (&optional (pane "buffers"))
  (let ((target (if (member pane *available-panes* :test #'string=) pane "buffers")))
    (setf *sidebar-visible* t
          *current-sidebar-pane* target)
    (incf *sidebar-epoch*)
    (fire-probe :ymacs-sidebar-toggle :pane target :visible t)
    (format t "~&[ymacs] Spawned single sidebar pane: ~a~%" target)
    target))

(defun despawn-sidebar ()
  (setf *sidebar-visible* nil)
  (incf *sidebar-epoch*)
  (fire-probe :ymacs-sidebar-toggle :pane *current-sidebar-pane* :visible nil)
  (format t "~&[ymacs] Despawned sidebar~%")
  nil)

(defun toggle-sidebar (&optional (pane "buffers"))
  (if (and *sidebar-visible* (string= *current-sidebar-pane* pane))
      (despawn-sidebar)
      (spawn-sidebar pane)))

(defun ymacs-toggle-sidebar-command (&optional pane)
  "Lisp-callable sidebar toggle for M-x ymacs-toggle-sidebar"
  (toggle-sidebar (or pane "buffers")))

(defun sidebar-document-version ()
  (format nil "~a-~a-~a" *frame-epoch* *sidebar-epoch* (if *sidebar-visible* *current-sidebar-pane* "hidden")))

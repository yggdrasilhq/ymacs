;;;; window.lisp --- Viewport and frame coordination
;;;; ymacs enforces a focused editing model: one main viewport (the document)
;;;; plus the single sidebar. No arbitrary splits in v0.1; splits are deferred
;;;; to a future tiling protocol. This file owns the geometry and the
;;;; document_version bump that drives GUI refetch.

(in-package #:ymacs)

(defstruct window-frame
  active-buffer
  width
  height
  split-state   ; :single only in v0.1; :vertical/:horizontal reserved
  document-version)

(defvar *main-window* (make-window-frame :active-buffer nil :width 120 :height 40
                                         :split-state :single :document-version "1"))

(defvar *frame-epoch* 1)

(defun current-window ()
  *main-window*)

(defun set-active-buffer (buf)
  (setf (window-frame-active-buffer *main-window*) buf)
  (when buf (setf *current-buffer* buf))
  (bump-document-version)
  buf)

(defun bump-document-version ()
  (incf *frame-epoch*)
  (incf *buffer-epoch*)
  (setf (window-frame-document-version *main-window*) (format nil "~a" *frame-epoch*))
  (fire-probe :ymacs-redisplay-frame :frame-id *frame-epoch* :widget-count (hash-table-count *buffers*))
  (window-frame-document-version *main-window*))

(defun document-version ()
  (window-frame-document-version *main-window*))

(defun window-width () (window-frame-width *main-window*))
(defun window-height () (window-frame-height *main-window*))

(defun resize-window (w h)
  (setf (window-frame-width *main-window*) w
        (window-frame-height *main-window*) h)
  (bump-document-version))

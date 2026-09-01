;;;; session.lisp --- Session management for ymacs
;;;; Persists open buffers, window layout, and recent files via session.json
;;;; and ytrace. Like Emacs desktop-save-mode, but with ymacs rope + ytrace.

(in-package #:ymacs)

(defvar *session-version* 2)
(defvar *session-auto-save-interval* 30)
(defvar *session-last-save* 0)

(defun session-file ()
  (merge-pathnames "session.json" (state-dir)))

(defun session-save (&optional force)
  (let ((now (get-universal-time)))
    (when (or force (> (- now *session-last-save*) *session-auto-save-interval*))
      (persist-session)
      (setf *session-last-save* now)
      (fire-probe :ymacs-session :action "save" :buffers (hash-table-count *buffers*))
      t)))

(defun session-restore ()
  (restore-session)
  (fire-probe :ymacs-session :action "restore" :buffers (hash-table-count *buffers*))
  t)

(defun session-add-recent (path)
  (pushnew (namestring path) *recent-files* :test #'string=)
  (when (> (length *recent-files*) 50)
    (setf *recent-files* (subseq *recent-files* 0 50)))
  (session-save t))

(defun session-clear ()
  (clrhash *buffers*)
  (setf *current-buffer* nil
        *recent-files* nil
        *buffer-epoch* 0
        *frame-epoch* 1)
  (ignore-errors (delete-file (session-file)))
  (fire-probe :ymacs-session :action "clear")
  t)

(defun session-buffers ()
  (list-all-buffers))

(defun session-switch-to-previous ()
  (let ((bufs (list-all-buffers)))
    (when (> (length bufs) 1)
      (let ((prev (second bufs)))
        (setf *current-buffer* prev)
        (bump-document-version)
        prev))))

(defun session-kill-all ()
  (dolist (buf (list-all-buffers))
    (kill-buffer (buffer-id buf)))
  (session-clear))

(defun session-info ()
  (format nil "Session v~a: ~a buffers, ~a recent, epoch ~a"
          *session-version* (hash-table-count *buffers*) (length *recent-files*) *buffer-epoch*))

;;;; eshell.lisp --- Eshell for ymacs (terminal inside buffer)
;;;; Like Emacs eshell, but backed by yggterm's PTY — no need to reinvent
;;;; terminal. This is a thin wrapper that spawns a shell buffer.

(in-package #:ymacs)

(defvar *eshell-buffers* 0)
(defvar *eshell-history* nil)
(defvar *eshell-history-max* 1000)

(defun eshell (&optional arg)
  (declare (ignore arg))
  (incf *eshell-buffers*)
  (let ((buf (make-new-buffer (format nil "*eshell*~a" *eshell-buffers*) "")))
    (set-buffer-major-mode buf "eshell-mode")
    (setf *current-buffer* buf)
    (bump-document-version)
    buf))

(define-major-mode "eshell-mode"
  :doc "Eshell — shell inside ymacs buffer."
  :hook (lambda (buf) (declare (ignore buf)) t))

(defun eshell-send-input (buf input)
  (push input *eshell-history*)
  (when (> (length *eshell-history*) *eshell-history-max*)
    (setf *eshell-history* (subseq *eshell-history* 0 *eshell-history-max*)))
  (let ((output (with-output-to-string (out)
                  (ignore-errors
                    (let ((proc (sb-ext:run-program "/bin/sh" (list "-c" input) :output out :error out :search t :wait t)))
                      (declare (ignore proc)))))))
    (buffer-insert-with-undo buf (length (buffer-content buf)) (format nil "~%~a~%~a" input output))
    output))

(defun eshell-history ()
  *eshell-history*)

(defun eshell-clear (buf)
  (setf (buffer-rope buf) (rope-from-string "")
        (buffer-modified-p buf) nil)
  (bump-document-version))

(defun eshell-cd (buf dir)
  (let ((path (if (string= dir "~") (or (sb-ext:posix-getenv "HOME") "/tmp") dir)))
    (when (probe-file path)
      (setf (buffer-file-path buf) (pathname path))
      t)))

(defun eshell-pwd (buf)
  (when (buffer-file-path buf) (namestring (buffer-file-path buf))))

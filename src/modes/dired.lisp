;;;; dired.lisp --- Minimal dired for ymacs

(in-package #:ymacs)

(defun dired-buffer (path)
  (let* ((dir (if (stringp path) (pathname path) path))
         (name (format nil "dired:~a" (namestring dir)))
         (buf (make-new-buffer name)))
    (setf (buffer-file-path buf) dir)
    (set-buffer-major-mode buf "dired-mode")
    (dired-refresh buf)
    buf))

(define-major-mode "dired-mode"
  :doc "Dired — directory listing as a buffer."
  :parent "fundamental")

(defun dired-refresh (buf)
  (let* ((dir (buffer-file-path buf))
         (entries (ignore-errors (directory (merge-pathnames "*.*" dir)))))
    (setf (buffer-rope buf)
          (rope-from-string
           (with-output-to-string (out)
             (format out "  ~a:~%" (namestring dir))
             (format out "  total ~a~%" (length entries))
             (dolist (e (sort (copy-list entries) #'string< :key #'namestring))
               (let* ((is-dir (and (probe-file e) (null (pathname-type e))))
                      (name (file-namestring e)))
                 (format out "  ~a ~a~%" (if is-dir "d" "-") name))))))
    (bump-document-version)))

(defun dired-find-file (buf line)
  (let* ((dir (buffer-file-path buf))
         (name (string-trim '(#\Space #\d #\-) line))
         (path (merge-pathnames name dir)))
    (when (probe-file path)
      (if (and (probe-file path) (null (pathname-type path)))
          (let ((nb (dired-buffer path)))
            (setf *current-buffer* nb)
            nb)
          (open-file-buffer path)))))

(defun dired-do-delete (buf line)
  (let* ((dir (buffer-file-path buf))
         (name (string-trim '(#\Space #\d #\-) line))
         (path (merge-pathnames name dir)))
    (when (probe-file path)
      (let ((trash (merge-pathnames ".local/share/Trash/files/" (parse-namestring (concatenate 'string (or (sb-ext:posix-getenv "HOME") "/tmp") "/")))))
        (ensure-directories-exist trash)
        (ignore-errors (sb-ext:run-program "/bin/mv" (list (namestring path) (namestring (merge-pathnames name trash))) :search t)))
      (dired-refresh buf))))

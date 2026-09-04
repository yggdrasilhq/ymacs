;;;; manifest.lisp --- Launcher registry for yggterm menus
(in-package #:ymacs)
(defun manifest-json (binary-path)
  (format nil "{\"name\":\"ymacs\",\"label\":\"Ymacs\",\"icon\":\"📝\",\"binary\":\"~a\",\"verbs\":[{\"id\":\"new\",\"label\":\"New Ymacs\",\"args\":[]}],\"keytip\":\"E\"}"
          (json-escape-string (namestring binary-path))))
(defun apps-dir () (merge-pathnames "apps/" (state-dir)))
(defun write-manifest-best-effort ()
  (handler-case
      (let* ((home (or (sb-ext:posix-getenv "HOME") (namestring (user-homedir-pathname))))
             (binary (merge-pathnames ".local/bin/ymacs" (user-homedir-pathname)))
             (dir (merge-pathnames "apps/" (parse-namestring (concatenate 'string home "/.yggterm/")))))
        (ensure-directories-exist dir)
        (let ((path (merge-pathnames "ymacs.json" dir)))
          (with-open-file (s path :direction :output :if-exists :supersede :external-format :utf-8)
            (write-string (manifest-json binary) s))))
    (error (e)
      ;; Best-effort must not be SILENT: the swallowed failure left the
      ;; launcher registry empty on jojo for two days with zero signal.
      (fire-probe :ymacs-manifest-write :error (format nil "~a" e))
      (format *error-output* "~&[ymacs] manifest write failed: ~a~%" e)
      nil)))

;;;; manifest.lisp --- Launcher registry for yggterm menus
;;;; Written to ~/.yggterm/apps/ymacs.json on every run (repairs binary path after upgrade).
;;;; Host daemon scans and prunes manifests whose binary vanished.

(in-package #:ymacs)

(defun manifest-json (binary-path)
  (format nil "{\"name\":\"ymacs\",\"label\":\"Ymacs\",\"icon\":\"📝\",\"binary\":\"~a\",\"verbs\":[{\"id\":\"new\",\"label\":\"New Ymacs\",\"args\":[]}],\"keytip\":\"E\"}"
          (json-escape-string binary-path)))

(defun apps-dir ()
  (merge-pathnames "apps/" (state-dir)))

(defun write-manifest-best-effort ()
  (handler-case
      (let* ((home (or (sb-ext:posix-getenv "HOME") (namestring (user-homedir-pathname))))
             (binary (or (ignore-errors (namestring (sb-ext:posix-getenv "YMACS_BIN")))
                         (ignore-errors (namestring (truename (first sb-ext:*posix-argv*))))
                         "/home/pi/.local/bin/ymacs"))
             (dir (merge-pathnames "apps/" (parse-namestring (concatenate 'string home "/.yggterm/")))))
        (ensure-directories-exist dir)
        (let ((path (merge-pathnames "ymacs.json" dir)))
          (with-open-file (s path :direction :output :if-exists :supersede :external-format :utf-8)
            (write-string (manifest-json binary) s))))
    (error () nil)))

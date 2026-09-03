;;;; ribbon-tests.lisp --- contract tests for the Excel-shape ribbon and
;;;; the command layer it drives (every keymap binding is a REAL command).
;;;;
;;;; Run: sbcl --load tests/run-tests.lisp
;;;; Plain CL, no dependencies — CI installs bare SBCL only.

(in-package #:ymacs)

(defun rt-sandbox ()
  "Disk-backed sandbox under home — never /tmp (store-tests pattern)."
  (ensure-directories-exist
   (merge-pathnames ".yggterm/scratchpad/ymacs-ribbon/" (user-homedir-pathname))))

(defun run-ribbon-tests ()
  (setf *test-pass* 0 *test-fail* 0)
  (format t "ymacs ribbon + command tests~%")

  (test "every default keymap binding names a real command (honesty law)"
    (unless (gethash "global" *elisp-keymaps*)
      (init-default-keymaps))
    (let ((map *global-map*)
          (dead nil))
      (assert-eq* t (not (null map)))
      (maphash (lambda (key target)
                 (declare (ignore key))
                 (when (and (symbolp target) (not (fboundp target)))
                   (push (cons key target) dead)))
               (elisp-keymap-bindings map))
      (when dead
        (error "dead keymap bindings: ~{~a~^, ~}" dead))))

  (test "find-file opens a file into the current buffer"
    (let* ((dir (rt-sandbox))
           (path (merge-pathnames "rt-find-file.txt" dir)))
      (with-open-file (s path :direction :output :if-exists :supersede)
        (write-string "ribbon file body" s))
      (command-execute 'find-file :args (list (namestring path)))
      (assert-eq* t (not (null *current-buffer*)))
      (assert-eq* "rt-find-file.txt" (buffer-name *current-buffer*))
      (assert-eq* t (not (null *echo-message*)))))

  (test "save-buffer writes the file and reports through the echo"
    (let* ((dir (rt-sandbox))
           (path (merge-pathnames "rt-save.txt" dir)))
      (with-open-file (s path :direction :output :if-exists :supersede)
        (write-string "before" s))
      (let ((buf (open-file-buffer (namestring path))))
        (setf *current-buffer* buf)
        (buffer-insert buf (length (buffer-content buf)) " after")
        (setf (buffer-modified-p buf) t)
        (command-execute 'save-buffer)
        (assert-eq* t (not (buffer-modified-p buf)))
        (let ((disk (with-open-file (s path)
                      (let ((s2 (make-string (file-length s))))
                        (read-sequence s2 s)
                        s2))))
          (assert-eq* t (not (null (search "after" disk))))))))

  (test "command: action runs the choke point; prompting commands open the palette"
    (let* ((*buffers* (make-hash-table :test 'equal))
           (*current-buffer* nil)
           (buf (make-new-buffer "*rt-cmd*" "hello")))
      (setf *current-buffer* buf)
      (let ((reply (handle-action `(("action" . "command:undo")))))
        (assert-eq* t (cdr (assoc "ok" reply :test #'string=))))
      (handle-action `(("action" . "command:find-file")))
      (assert-eq* t *minibuffer-active*)
      (minibuffer-abort)))

  (test "ribbon tab switch is real: groups follow the active tab"
    (let* ((*buffers* (make-hash-table :test 'equal))
           (*current-buffer* nil)
           (*tool-bar-visible* t)
           (buf (make-new-buffer "*rt-tab*" "x")))
      (setf *current-buffer* buf)
      (handle-action `(("action" . "ribbon-tab:help")))
      (let* ((ribbon (cdr (assoc "ribbon" (document-schema) :test #'string=)))
             (bar (aref ribbon 0)))
        (assert-eq* "help" (cdr (assoc "active" bar :test #'string=)))
        (assert-eq* 2 (length (coerce (cdr (assoc "groups" bar :test #'string=)) 'list))))
      (handle-action `(("action" . "ribbon-tab:home")))))

  (test "ribbon tab switching bumps the document version edge"
    (let ((*tool-bar-visible* t))
      (let ((before (document-version)))
        (handle-action `(("action" . "ribbon-tab:edit")))
        (assert-eq* t (not (null (string/= before (document-version)))))
        (handle-action `(("action" . "ribbon-tab:home"))))))

  (test "probes fire: command + key + ribbon land in the ring"
    (let ((buf (make-new-buffer "*rt-probe*" "x")))
      (setf *current-buffer* buf)
      (let ((before (probe-count :ymacs-command)))
        (command-execute 'undo)
        (assert-eq* t (> (probe-count :ymacs-command) before)))
      (let ((before (probe-count :ymacs-key)))
        (ymacs-handle-key "C-f")
        (assert-eq* t (> (probe-count :ymacs-key) before)))
      (let ((before (probe-count :ymacs-ribbon)))
        (handle-action `(("action" . "ribbon-tab:help")))
        (handle-action `(("action" . "ribbon-tab:home")))
        (assert-eq* t (> (probe-count :ymacs-ribbon) before)))))

  (format t "~a passed, ~a failed~%" *test-pass* *test-fail*)
  (zerop *test-fail*))

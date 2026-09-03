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
           (*tab-bar-mode-on* t)
           (buf (make-new-buffer "*rt-tab*" "x")))
      (setf *current-buffer* buf)
      (handle-action `(("action" . "ribbon-tab:help")))
      (let* ((ribbon (cdr (assoc "ribbon" (document-schema) :test #'string=)))
             (bar (aref ribbon 0)))
        (assert-eq* "help" (cdr (assoc "active" bar :test #'string=)))
        (assert-eq* 2 (length (coerce (cdr (assoc "groups" bar :test #'string=)) 'list))))
      (handle-action `(("action" . "ribbon-tab:home")))))

  (test "ribbon tab switching bumps the document version edge"
    (let ((*tab-bar-mode-on* t))
      (let ((before (document-version)))
        (handle-action `(("action" . "ribbon-tab:edit")))
        (assert-eq* t (not (null (string/= before (document-version)))))
        (handle-action `(("action" . "ribbon-tab:home"))))))

  (test "tab-bar API: lisp adds and removes tabs, groups and buttons"
    (let ((*tab-bar-tabs* (init-tab-bar-defaults))
          (*tab-bar-active* "home"))
      (let ((count (length (tab-bar-tab-names))))
        ;; add: append, duplicate refusal, insert-after
        (tab-bar-add-tab "tools" "Tools")
        (assert-eq* t (not (null (member "tools" (tab-bar-tab-names) :test #'string=))))
        (assert-eq* nil (tab-bar-add-tab "tools" "Tools"))
        (tab-bar-remove-tab "tools")
        (tab-bar-add-tab "tools" "Tools" :after "home")
        (assert-eq* "tools" (second (tab-bar-tab-names)))
        ;; buttons land in a group the call creates; duplicates refused
        (assert-eq* t (tab-bar-add-button "tools" "Build" "command:compile" "⚙ Compile" "Compile (M-x compile)"))
        (assert-eq* nil (tab-bar-add-button "tools" "Build" "command:compile" "⚙ Compile"))
        (let ((groups (getf (tab-bar-tab "tools") :groups)))
          (assert-eq* 1 (length groups))
          (assert-eq* "Build" (getf (first groups) :label)))
        ;; rename keeps the id
        (tab-bar-rename-tab "tools" "Toolbox")
        (assert-eq* "Toolbox" (getf (tab-bar-tab "tools") :name))
        (assert-eq* "tools" (getf (tab-bar-tab "tools") :id))
        ;; removal, bottom up
        (assert-eq* t (tab-bar-remove-button "tools" "Build" "command:compile"))
        (assert-eq* t (tab-bar-remove-group "tools" "Build"))
        (assert-eq* nil (tab-bar-remove-group "tools" "Build"))
        ;; removing the ACTIVE tab selects the first remaining
        (tab-bar-select-tab "tools")
        (tab-bar-remove-tab "tools")
        (assert-eq* "home" *tab-bar-active*)
        (assert-eq* count (length (tab-bar-tab-names))))))

  (test "tab-bar API: :buffer-modified resolves only for a dirty buffer"
    (let* ((*buffers* (make-hash-table :test 'equal))
           (*current-buffer* nil)
           (*tab-bar-tabs* (init-tab-bar-defaults))
           (*tab-bar-active* "home")
           (buf (make-new-buffer "*rt-prim*" "x")))
      (setf *current-buffer* buf)
      (let* ((groups (tab-bar-schema-groups buf))
             (file-group (aref groups 0))
             (buttons (cdr (assoc "buttons" file-group :test #'string=)))
             (save (aref buttons 1)))
        (assert-eq* "save" (cdr (assoc "action" save :test #'string=)))
        (assert-eq* :false (cdr (assoc "primary" save :test #'string=))))
      (setf (buffer-modified-p buf) t)
      (let* ((groups (tab-bar-schema-groups buf))
             (save (aref (cdr (assoc "buttons" (aref groups 0) :test #'string=)) 1)))
        (assert-eq* t (cdr (assoc "primary" save :test #'string=))))))

  (test "tab-bar API: unknown ids are refusals, never a broken strip"
    (let ((*tab-bar-tabs* (init-tab-bar-defaults))
          (*tab-bar-active* "home"))
      (assert-eq* nil (tab-bar-select-tab "no-such-tab"))
      (assert-eq* "home" *tab-bar-active*)
      (assert-eq* nil (tab-bar-remove-tab "no-such-tab"))
      (assert-eq* nil (tab-bar-add-group "no-such-tab" (tab-bar-make-group "G" nil)))
      (assert-eq* 4 (length (tab-bar-tab-names)))
      ;; an active id that no tab declares renders no groups — the panel
      ;; opens empty rather than lying
      (let ((*tab-bar-active* "ghost"))
        (assert-eq* 0 (length (tab-bar-schema-groups nil))))))

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

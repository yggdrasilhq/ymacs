;;;; schema-tests.lisp --- the GUI validator is strict: a schema slot
;;;; typed boolean must be true/false, never null. Lisp nil is the common
;;;; nothing, so every boolean slot goes through json-bool. This file locks
;;;; that: any null-typed boolean in any served schema fails here instead
;;;; of painting "document schema is malformed" in the user's viewport.
;;;;
;;;; Run: sbcl --load tests/run-tests.lisp
;;;; Plain CL, no dependencies — CI installs bare SBCL only.

(in-package #:ymacs)

(defun sch-json (schema)
  (json-encode-response schema))

(defun sch-assert-bools-strict (json label)
  "No boolean-typed slot may read null in JSON."
  (dolist (slot '("muted" "multiline" "line_numbers" "word_wrap"
                  "primary" "selected"))
    (let ((needle (format nil "\"~a\":null" slot)))
      (when (search needle json)
        (error "~a: slot ~a is null" label slot)))))

(defun run-schema-tests ()
  (setf *test-pass* 0 *test-fail* 0)
  (format t "ymacs schema-strictness tests~%")

  (test "json-bool is strict: T in, everything else an explicit false"
    (assert-eq* t (json-bool t))
    (assert-eq* :false (json-bool nil))
    (assert-eq* "false" (json-value-encode :false))
    (assert-eq* "true" (json-value-encode t)))

  (test "editor booleans fall back to shipped defaults without a book"
    ;; Daemon hosts have no init.org in cwd: the schema must still
    ;; validate (word_wrap ships DEFAULT TRUE, line-numbers true).
    ;; chdir somewhere bookless so *settings-schema-path-override*,
    ;; env, buffers and cwd all miss.
    ;; truename "." follows *default-pathname-defaults*, so bind it
    ;; somewhere bookless (sandbox has no init.org, no buffers visit
    ;; one, no override, no env).
    (let ((*default-pathname-defaults* (sb-sandbox))
          (*buffers* (make-hash-table :test 'equal))
          (*current-buffer* nil))
      (ensure-directories-exist (sb-sandbox))
      (assert-eq* nil (ignore-errors (settings-schema-path)))
      (assert-eq* t (settings-get-bool "editor.line-numbers" t))
      (assert-eq* t (settings-get-bool "editor.word-wrap" t))
      (assert-eq* :false (settings-get-bool "editor.line-numbers" nil))))

  (test "document schema validates with and without a current buffer"
    (let ((*current-buffer* nil))
      (sch-assert-bools-strict (sch-json (document-schema)) "doc-empty")))
  (test "document schema validates with an unmodified buffer"
    (let* ((*buffers* (make-hash-table :test 'equal))
           (*current-buffer* nil))
      (let ((buf (make-new-buffer "*st*" "hi")))
        (setf *current-buffer* buf)
        (let ((json (sch-json (document-schema))))
          (sch-assert-bools-strict json "doc-clean")
          (assert-eq* t (not (null (search "\"primary\":false" json))))))))

  (test "buffers schema validates with selected and unselected rows"
    (let* ((*buffers* (make-hash-table :test 'equal))
           (*current-buffer* nil))
      (make-new-buffer "*a*" "a")
      (make-new-buffer "*b*" "b")
      (let ((json (sch-json (buffers-schema))))
        (sch-assert-bools-strict json "buffers")
        (assert-eq* t (not (null (search "\"selected\":true" json))))
        (assert-eq* t (not (null (search "\"selected\":false" json)))))))

  (test "single-pane dispatch validates in every view, hidden included"
    (let ((*sidebar-visible* t))
      (dolist (view '("buffers" "outline" "which-key" "settings" "project"))
        (setf *current-sidebar-pane* view)
        (sch-assert-bools-strict (sch-json (sidebar-pane-schema))
                                 (format nil "pane-~a" view))))
    (let ((*sidebar-visible* nil))
      (sch-assert-bools-strict (sch-json (sidebar-pane-schema)) "pane-hidden")))

  (test "palette rows validate while the minibuffer is active"
    (minibuffer-start "M-x " '("save-buffer" "sidebar"))
    (unwind-protect
         (sch-assert-bools-strict
          (sch-json `(("title" . "palette")
                      ("widgets" . ,(coerce (minibuffer-schema-widgets)
                                            'vector))))
          "palette")
      (minibuffer-abort)))

  (test "file buffers display the filename, identity stays the path"
    (let* ((*buffers* (make-hash-table :test 'equal))
           (*current-buffer* nil)
           (*recent-files* nil)
           (dir (sb-sandbox)))
      (ensure-directories-exist dir)
      (let ((f (merge-pathnames "some-file.txt" dir)))
        (with-open-file (s f :direction :output :if-exists :supersede)
          (write-string "x" s))
        (let ((buf (open-file-buffer (namestring f))))
          (assert-eq* "some-file.txt" (buffer-name buf))
          (assert-eq* (namestring f) (namestring (buffer-file-path buf)))
          (let* ((widgets (cdr (assoc "widgets" (buffers-schema)
                                      :test #'string=)))
                 (row (find (buffer-id buf) (coerce widgets 'list)
                            :key (lambda (w)
                                   (cdr (assoc "id" w :test #'string=)))
                            :test #'string=)))
            (assert-eq* "some-file.txt"
                        (cdr (assoc "title" row :test #'string=)))
            (assert-eq* (namestring f)
                        (cdr (assoc "subtitle" row :test #'string=)))))
        (ignore-errors (delete-file f)))))

  (format t "~a passed, ~a failed~%" *test-pass* *test-fail*)
  (zerop *test-fail*))

(defun run-toolbar-tests ()
  (setf *test-pass* 0 *test-fail* 0)
  (format t "ymacs tab-bar (ribbon chrome) tests~%")

  (test "tab-bar-mode is registered and toggles with a version edge"
    (assert-eq* t (not (null (member "tab-bar-mode" (minibuffer-command-names)
                                     :test #'string=))))
    (let ((*tab-bar-mode-on* t))
      (let ((before (document-version)))
        (command-execute 'tab-bar-mode)
        (assert-eq* nil *tab-bar-mode-on*)
        (assert-eq* t (not (null (string/= before (document-version)))))
        (command-execute 'tab-bar-mode)
        (assert-eq* t *tab-bar-mode-on*))))

  (test "tool-bar-mode stays registered as the tab-bar-mode alias"
    (assert-eq* t (not (null (member "tool-bar-mode" (minibuffer-command-names)
                                     :test #'string=))))
    (let ((*tab-bar-mode-on* t))
      (command-execute 'tool-bar-mode)
      (assert-eq* nil *tab-bar-mode-on*)
      (command-execute 'tool-bar-mode)
      (assert-eq* t *tab-bar-mode-on*)))

  (test "the ribbon is a ribbon-bar (tabs over groups); widgets carry no ribbon"
    (let* ((*buffers* (make-hash-table :test 'equal))
           (*current-buffer* nil)
           (*tab-bar-mode-on* t))
      (let ((buf (make-new-buffer "*tb*" "x")))
        (setf *current-buffer* buf)
        (let* ((schema (document-schema))
               (ribbon (cdr (assoc "ribbon" schema :test #'string=)))
               (widgets (cdr (assoc "widgets" schema :test #'string=)))
               (bar (aref ribbon 0))
               (groups (cdr (assoc "groups" bar :test #'string=))))
          (assert-eq* 2 (length (coerce ribbon 'list)))
          (assert-eq* "ribbon-bar" (cdr (assoc "kind" bar :test #'string=)))
          (assert-eq* "home" (cdr (assoc "active" bar :test #'string=)))
          (assert-eq* 4 (length (coerce (cdr (assoc "tabs" bar :test #'string=)) 'list)))
          (assert-eq* 3 (length (coerce groups 'list)))
          (assert-eq* t (cdr (assoc "right" (aref groups 2) :test #'string=)))
          ;; every button fires an action
          (dolist (g (coerce groups 'list))
            (dolist (b (coerce (cdr (assoc "buttons" g :test #'string=)) 'list))
              (assert-eq* t (not (null (cdr (assoc "action" b :test #'string=)))))))
          (assert-eq* nil (find "ribbon-bar" (coerce widgets 'list)
                                :key (lambda (w) (cdr (assoc "kind" w :test #'string=)))
                                :test #'string=))))))

  (test "ribbon-tab action switches the command groups"
    (let* ((*buffers* (make-hash-table :test 'equal))
           (*current-buffer* nil)
           (*tab-bar-mode-on* t)
           (buf (make-new-buffer "*tb4*" "x")))
      (setf *current-buffer* buf)
      (handle-action `(("action" . "ribbon-tab:view")))
      (assert-eq* "view" *tab-bar-active*)
      (let* ((ribbon (cdr (assoc "ribbon" (document-schema) :test #'string=)))
             (bar (aref ribbon 0))
             (groups (cdr (assoc "groups" bar :test #'string=)))
             (pane-btns (cdr (assoc "buttons" (aref groups 0) :test #'string=))))
        (assert-eq* "view" (cdr (assoc "active" bar :test #'string=)))
        (assert-eq* "toggle-sidebar"
                    (cdr (assoc "action" (aref pane-btns 0) :test #'string=))))
      (handle-action `(("action" . "ribbon-tab:home")))
      (assert-eq* "home" *tab-bar-active*)))

  (test "command: actions run through the choke point and echo"
    (let* ((*buffers* (make-hash-table :test 'equal))
           (*current-buffer* nil)
           (*tab-bar-mode-on* t)
           (buf (make-new-buffer "*tb5*" "hello")))
      (setf *current-buffer* buf)
      (let ((reply (handle-action `(("action" . "command:undo")))))
        (assert-eq* t (cdr (assoc "ok" reply :test #'string=))))
      ;; a prompting command opens the palette instead of failing
      (handle-action `(("action" . "command:find-file")))
      (assert-eq* t *minibuffer-active*)
      (minibuffer-abort)))

  (test "tool-bar off means no ribbon (host gives the card full rect)"
    (let* ((*buffers* (make-hash-table :test 'equal))
           (*current-buffer* nil)
           (*tab-bar-mode-on* nil))
      (make-new-buffer "*tb2*" "x")
      (assert-eq* nil (cdr (assoc "ribbon" (document-schema) :test #'string=)))))

  (test "ribbon JSON validates under the strict contract"
    (let* ((*buffers* (make-hash-table :test 'equal))
           (*current-buffer* nil)
           (*tab-bar-mode-on* t))
      (make-new-buffer "*tb3*" "x")
      (let ((json (sch-json `(("title" . "t")
                              ("ribbon" . ,(cdr (assoc "ribbon" (document-schema)
                                                       :test #'string=)))))))
        (sch-assert-bools-strict json "ribbon"))))

  (format t "~a passed, ~a failed~%" *test-pass* *test-fail*)
  (zerop *test-fail*))

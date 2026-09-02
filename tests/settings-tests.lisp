;;;; settings-tests.lisp --- contract tests for the settings store and
;;;; its two views (docs/spec-primitives.md §4, step 7; divergence D2).
;;;;
;;;; Everything runs in a sandboxed HOME: no test may touch the real
;;;; ~/.yggterm state. The schema fixture is a real org file parsed by
;;;; the same org node parser the editor uses.

(in-package #:ymacs)

(defvar *st-pass* 0)
(defvar *st-fail* 0)

(defmacro st-test (name &body body)
  `(progn
     (format t "  ~a ..." ,name)
     (handler-case (progn ,@body (incf *st-pass*) (format t " ok~%"))
       (error (e) (incf *st-fail*) (format t " FAIL: ~a~%" e)))))

(defun st-assert (want got)
  (unless (equal want got)
    (error "expected ~s, got ~s" want got)))

(defun st-sandbox-dir ()
  (merge-pathnames ".yggterm/ymacs/"
                   (make-pathname :directory
                                  (append (pathname-directory
                                           (parse-namestring
                                            (or (sb-ext:posix-getenv "HOME") "/")))
                                          '("st-sandbox")))))

(defun st-sandbox-home ()
  (let* ((dir (st-sandbox-dir))
         (home (make-pathname :directory (butlast (pathname-directory dir)))))
    home))

(defun st-write (path string)
  (ensure-directories-exist path)
  (with-open-file (s path :direction :output :if-exists :supersede
                          :external-format :utf-8)
    (write-string string s)))

(defun st-read (path)
  (with-open-file (s path :external-format :utf-8)
    (let ((out (make-string-output-stream)))
      (loop for ch = (read-char s nil nil)
            while ch do (write-char ch out))
      (get-output-stream-string out))))

(defvar *st-fixture-book*
  "* Chapter I

Prose about the editor.

* Settings

** Editing

*** editor.word-wrap
:PROPERTIES:
:TYPE: boolean
:DEFAULT: true
:DESC: Soft-wrap long lines in the editor viewport.
:END:

*** editor.line-numbers
:PROPERTIES:
:TYPE: boolean
:DEFAULT: true
:DESC: Show line numbers in the editor viewport.
:END:

** Files

*** files.recent-max
:PROPERTIES:
:TYPE: number
:DEFAULT: 5
:DESC: Recent files kept in the session.
:END:
")

(defun st-setup ()
  "Sandbox HOME + schema fixture. Returns the schema path."
  (let* ((sandbox (st-sandbox-home))
         (book (merge-pathnames "init.org" sandbox)))
    (setf (sb-ext:posix-getenv "HOME") (namestring sandbox))
    (st-write book *st-fixture-book*)
    (setf (sb-ext:posix-getenv "YMACS_SETTINGS_SCHEMA") (namestring book))
    ;; Reset store state so tests start from the sandbox, not prior runs.
    (setf *settings-open* nil
          *settings-section* nil
          *settings-overrides* nil
          *settings-user-org-stat* nil
          *current-buffer* nil)
    (namestring book)))

(defun st-teardown (old-home old-schema)
  (setf (sb-ext:posix-getenv "HOME") old-home)
  (setf (sb-ext:posix-getenv "YMACS_SETTINGS_SCHEMA") old-schema))

(defun st-widgets (schema)
  (coerce (cdr (assoc "widgets" schema :test #'string=)) 'list))

(defun st-widget (widgets id)
  "The widget whose id is ID."
  (find-if (lambda (w) (equal id (cdr (assoc "id" w :test #'string=)))) widgets))

(defun st-editor-widget (schema)
  (st-widget (st-widgets schema) "editor"))

(defun run-settings-tests ()
  (setf *st-pass* 0 *st-fail* 0)
  (format t "ymacs settings store tests~%")
  (let ((old-home (sb-ext:posix-getenv "HOME"))
        (old-schema (sb-ext:posix-getenv "YMACS_SETTINGS_SCHEMA")))
    (unwind-protect
         (progn
           (st-setup)

           (st-test "schema parses sections, entries, types, defaults from the book"
             (st-assert '("Editing" "Files") (settings-sections))
             (st-assert '("editor.word-wrap" "boolean" "true"
                          "Soft-wrap long lines in the editor viewport.")
                        (settings-entry "editor.word-wrap")))

           (st-test "defaults apply when user.org does not exist"
             (st-assert t (settings-get "editor.word-wrap"))
             (st-assert 5 (settings-get "files.recent-max")))

           (st-test "settings-set writes user.org and the override wins"
             (st-assert :ok (settings-set "editor.word-wrap" "false"))
             (st-assert nil (settings-get "editor.word-wrap"))
             (let ((user (st-read (settings-user-org-path))))
               (st-assert t (and (search "* Settings" user)
                                 (search ":editor.word-wrap: false" user)))))

           (st-test "a second set replaces in place, never duplicates"
             (settings-set "editor.word-wrap" "true")
             (settings-set "editor.word-wrap" "false")
             (let ((user (st-read (settings-user-org-path))))
               (st-assert 1 (count ":editor.word-wrap:" user :test #'string=))
               (st-assert t (search ":editor.word-wrap: false" user))))

           (st-test "the writer preserves foreign bytes, keys, and the missing trailing newline"
             ;; A user file with prose, a foreign property, and NO
             ;; trailing newline must survive a set untouched outside
             ;; the managed drawer.
             (let ((user-path (settings-user-org-path))
                   (before "* My config
Some prose the user wrote.
* Settings
:PROPERTIES:
:user.own-key: keep-me
:editor.line-numbers: true
:END:
* More prose
no trailing newline"))
               (st-write user-path before)
               (setf *settings-user-org-stat* nil)
               (settings-set "editor.word-wrap" "false")
               (let ((after (st-read user-path)))
                 (st-assert t (search "Some prose the user wrote." after))
                 (st-assert t (search ":user.own-key: keep-me" after))
                 (st-assert t (search ":editor.line-numbers: true" after))
                 (st-assert t (search ":editor.word-wrap: false" after))
                 (st-assert t (search "* More prose" after))
                 (st-assert #\n (char after (1- (length after)))))))

           (st-test "invalid ids and values are rejected without touching the file"
             (let ((user-path (settings-user-org-path))
                   (before (st-read user-path)))
               (st-assert :invalid (settings-set "editor.word-wrap" "yes"))
               (st-assert :invalid (settings-set "nope.mode" "true"))
               (st-assert before (st-read user-path))))

           (st-test "hand edits to user.org are reloaded (the file is a peer view)"
             (st-write (settings-user-org-path)
                       "* Settings
:PROPERTIES:
:editor.word-wrap: true
:END:")
             (setf *settings-user-org-stat* nil) ; mtime is second-granular
             (st-assert t (settings-get "editor.word-wrap")))

           (st-test "M-x settings renders the section from the schema"
             (settings-open)
             (settings-set "editor.word-wrap" "true")
             (let* ((schema (document-schema))
                    (title (cdr (assoc "title" schema :test #'string=)))
                    (buttons (cdr (assoc "buttons"
                                         (st-widget (st-widgets schema)
                                                    "ctl:editor.word-wrap")
                                         :test #'string=))))
               (st-assert "ymacs — Settings: Editing" title)
               ;; current value is true: the On button is primary.
               (let ((on (find-if (lambda (b) (search "true" (cdr (assoc "action" b :test #'string=))))
                                  (coerce buttons 'list)))
                     (off (find-if (lambda (b) (search "false" (cdr (assoc "action" b :test #'string=))))
                                   (coerce buttons 'list))))
                 (st-assert t (cdr (assoc "primary" on :test #'string=)))
                 (st-assert nil (cdr (assoc "primary" off :test #'string=))))))

           (st-test "settings view drops key_capture; closing restores the editor view"
             (st-assert nil (assoc "key_capture" (document-schema) :test #'string=))
             (settings-close)
             (st-assert t (cdr (assoc "key_capture" (document-schema) :test #'string=)))
             (st-assert "editor" (cdr (assoc "id" (st-editor-widget (document-schema))
                                              :test #'string=))))

           (st-test "the live editor widget reflects the store"
             ;; The editor view needs a current buffer to render.
             (let ((buf (make-new-buffer "*st-live*" "")))
               (setf *current-buffer* buf)
               (settings-set "editor.word-wrap" "false")
               (let ((editor (st-editor-widget (document-schema))))
                 (st-assert nil (cdr (assoc "word_wrap" editor :test #'string=)))
                 (st-assert t (cdr (assoc "line_numbers" editor :test #'string=)))
                 ;; restore
                 (settings-set "editor.word-wrap" "true")
                 (st-assert t (cdr (assoc "word_wrap"
                                          (st-editor-widget (document-schema))
                                          :test #'string=))))))

           (st-test "section switching renders the other section"
             (settings-open)
             (settings-handle-action "settings-section"
                                     '(("value" . "Files")) nil)
             (st-assert "ymacs — Settings: Files"
                        (cdr (assoc "title" (document-schema) :test #'string=)))
             (settings-close))

           (st-test "the settings pane lists sections with the selected flag"
             (settings-open)
             (let* ((pane (settings-pane-schema))
                    (editing (st-widget (st-widgets pane) "Editing")))
               (st-assert t (cdr (assoc "selected" editing :test #'string=)))
               (st-assert "settings-section"
                          (cdr (assoc "row_action" editing :test #'string=))))
             (settings-close))

           (st-test "an unreachable schema is honest, not invented"
             (setf (sb-ext:posix-getenv "YMACS_SETTINGS_SCHEMA")
                   "/nonexistent/settings.org")
             (setf *current-buffer* nil)
             (let ((schema (settings-schema)))
               (st-assert nil schema)
               (settings-open)
               (let ((flat (format nil "~a" (cdr (assoc "widgets" (document-schema)
                                                        :test #'string=)))))
                 (st-assert t (search "schema not found" flat)))
               (settings-close))))

      (st-teardown old-home old-schema)))
  (format t "ymacs settings store tests: ~a passed, ~a failed~%" *st-pass* *st-fail*)
  (zerop *st-fail*))

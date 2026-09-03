;;;; settings.lisp --- the settings store: defaults ← user.org overrides.
;;;;
;;;; Step 7 (docs/spec-primitives.md §4, §5; divergence D2): ONE store,
;;;; two views. The SCHEMA lives in the shipped book (init.org) as org
;;;; properties — a `* Settings` chapter whose level-2 headings are
;;;; sections and level-3 headings are settings, each carrying
;;;; :TYPE:/:DEFAULT:/:DESC: in a :PROPERTIES: drawer. The OVERRIDES
;;;; live in ~/.yggterm/ymacs/user.org under a `* Settings` heading's
;;;; :PROPERTIES: drawer — the same file users hand-edit for any other
;;;; configuration, so the writer may only touch that one drawer and
;;;; must preserve every other byte of the file (including whether the
;;;; last line ends in a newline).
;;;;
;;;; Precedence is defaults ← overrides (VSCode settings design). The
;;;; UI is GENERATED from the schema — no hand-mirrored widget list.
;;;; Org parsing rides the typed node parser (modes/org.lisp, defined
;;;; later in the build order — every cross-call here is runtime).

(in-package #:ymacs)

;;; --- State -------------------------------------------------------------------

(defvar *settings-open* nil "The settings document owns the viewport.")
(defvar *settings-section* nil "Currently rendered section name.")
(defvar *settings-overrides* nil
  "ALIST of (id . value-string) from user.org's Settings drawer.")
(defvar *settings-user-org-stat* nil
  "Cons (file-write-date . file-length) of user.org at last read — the
file is a peer view, so hand edits are reloaded when either moves.
mtime alone is second-granular; two edits inside one second must not
serve a stale store.")
(defvar *settings-schema-path-override* nil
  "Test/diagnostic hook: when bound, THE schema file (beats the env
and cwd search).")
(defvar *settings-user-org-path-override* nil
  "Test/diagnostic hook: when bound, THE user.org file (beats the
state-dir default).")

;;; --- Schema resolution ---------------------------------------------------------

(in-package #:ymacs)

(defun settings-schema-path ()
  "First existing candidate for the shipped book: the test/diagnostic
override, explicit env override, an open buffer visiting init.org, the
daemon's cwd. NIL when the book is unreachable — the UI then renders an
honest empty schema (never a hand-mirrored fallback)."
  (or (and *settings-schema-path-override*
           (probe-file *settings-schema-path-override*)
           *settings-schema-path-override*)
      (let ((env (sb-ext:posix-getenv "YMACS_SETTINGS_SCHEMA")))
        (or (and env (plusp (length env)) (probe-file env) env)
            (let ((from-buffer (find-if
                                (lambda (b)
                                  (and (buffer-file-path b)
                                       (string-equal (file-namestring (buffer-file-path b))
                                                     "init.org")))
                                (list-all-buffers))))
              (or (and from-buffer
                       (buffer-file-path from-buffer)
                       (probe-file (buffer-file-path from-buffer))
                       (buffer-file-path from-buffer))
                  (let ((cwd (merge-pathnames "init.org" (truename "."))))
                    (and (probe-file cwd) cwd))))))))

(defun settings--parse-properties (content lines prop-start prop-end)
  "Parse `:KEY: value` lines from LINES[PROP-START..PROP-END] (1-based,
inclusive) into an alist, keys kept verbatim (case preserved — override
ids are dotted lowercase and lookups are string-equal). Non-property
lines are ignored: a drawer may carry keys the store does not manage."
  (declare (ignore content))
  (let ((out nil))
    (loop for n from prop-start to prop-end
          for trimmed = (org-trim (org-strip-cr (aref lines (1- n))))
          do (when (and (plusp (length trimmed)) (char= (char trimmed 0) #\:))
               (let ((colon (position #\: trimmed :start 1)))
                 (when colon
                   (let ((key (subseq trimmed 1 colon))
                         (val (string-trim '(#\Space #\Tab) (subseq trimmed (1+ colon)))))
                     (when (plusp (length key))
                       (push (cons key val) out)))))))
    (nreverse out)))

(defun settings-schema ()
  "The schema: a list of (SECTION (ID TYPE DEFAULT DESC)...) in
document order, from the book's `* Settings` chapter. Parsed on demand
— the book is editable, a cache would be a second store."
  (let ((path (settings-schema-path)))
    (when path
      (let* ((content (read-file-string path))
             (nodes (org-parse content))
             (chapter (find-if (lambda (n)
                                 (and (org-heading-p n)
                                      (string-equal (org-heading-title n) "Settings")))
                               nodes)))
        (when chapter
          (let ((sections nil)
                (lines (org-scan-lines content)))
            (dolist (sec (org-heading-body chapter))
              (when (org-heading-p sec)
                (let ((entries nil))
                  (dolist (entry (org-heading-body sec))
                    (when (org-heading-p entry)
                      (let ((props nil))
                        (dolist (child (org-heading-body entry))
                          (when (and (org-drawer-p child)
                                     (string-equal (org-drawer-name child) "PROPERTIES")
                                     (org-drawer-body-line-start child))
                            (setf props
                                  (settings--parse-properties
                                   content lines
                                   (org-drawer-body-line-start child)
                                   (or (org-drawer-body-line-end child)
                                       (1- (org-drawer-body-line-start child)))))))
                        (when props
                          (push (list (org-heading-title entry)
                                      (cdr (assoc "TYPE" props :test #'string-equal))
                                      (cdr (assoc "DEFAULT" props :test #'string-equal))
                                      (cdr (assoc "DESC" props :test #'string-equal)))
                                entries)))))
                  (when entries
                    (push (cons (org-heading-title sec) (nreverse entries))
                          sections)))))
            (nreverse sections)))))))

(defun settings-sections ()
  (mapcar #'car (settings-schema)))

(defun settings-entry (id)
  "The schema entry (id type default desc) for ID, or nil — the schema
is the authority on what settings exist."
  (dolist (section (settings-schema))
    (let ((hit (find id (cdr section) :test #'string= :key #'first)))
      (when hit (return hit)))))

(defun settings-user-org-path ()
  (or *settings-user-org-path-override*
      (merge-pathnames "user.org" (state-dir))))

(defun settings--settings-heading-p (line)
  "Exactly the level-1 `* Settings` heading (a `** Settings` subheading
inside some other chapter is not the store)."
  (and (plusp (length line))
       (char= (char line 0) #\*)
       (not (find #\* line :start 1))
       (string-equal (org-trim (subseq line 1)) "Settings")))

(defun settings--drawer-span (content)
  "Locate the `* Settings` heading's :PROPERTIES: drawer in CONTENT.
Returns the two-element list (PROPS-LINE END-LINE) — 1-based line
numbers of the :PROPERTIES: and :END: lines — or NIL."
  (multiple-value-bind (lines starts) (org-scan-lines content)
    (declare (ignore starts))
    (let ((n (length lines)) heading props)
      (loop for i from 0 below n
            for line = (org-strip-cr (aref lines i))
            do (cond
                 ((and (null heading) (settings--settings-heading-p line))
                  (setf heading t))
                 ((and heading (null props)
                       (string-equal (org-trim line) ":PROPERTIES:"))
                  (setf props (1+ i)))
                 ((and props (string-equal (org-trim line) ":END:"))
                  (return-from settings--drawer-span
                    (list props (1+ i))))))
      (when (and heading props)
        (list props n)))))


(defun settings-load-overrides ()
  "The override alist from user.org. Reloads when the file's mtime OR
length moved — hand edits are a first-class way to change settings."
  (let* ((path (settings-user-org-path))
         (exists (probe-file path)))
    (when exists
      (let* ((stat (cons (file-write-date path)
                         (with-open-file (s path) (file-length s)))))
        (unless (equal stat *settings-user-org-stat*)
          (let* ((content (read-file-string path))
                 (span (settings--drawer-span content))
                 (props (and span (first span)))
                 (end (and span (second span))))
            (when (and props end)
              (setf *settings-user-org-stat* stat
                    *settings-overrides*
                    (settings--parse-properties
                     content (org-scan-lines content) props end))))))))
  *settings-overrides*)

(defun settings-get (id)
  "The typed current value of setting ID: user.org override beats the
schema default. Unknown ids return NIL — the schema is the authority."
  (let ((entry (settings-entry id)))
    (when entry
      (let* ((type (second entry))
             (override (cdr (assoc id (settings-load-overrides)
                                   :test #'string-equal)))
             (raw (if override override (third entry))))
        (settings--coerce raw type)))))

(defun settings--coerce (raw type)
  "Coerce RAW (a string) per TYPE. An unparseable value yields NIL
rather than a guess — a broken override must never look like a working
value."
  (cond
    ((null raw) nil)
    ((string-equal type "boolean")
     (cond ((string-equal raw "true") t)
           ((string-equal raw "false") nil)
           (t nil)))
    ((string-equal type "number")
     (ignore-errors (parse-integer (org-trim raw))))
    (t raw)))

(defun settings--valid-p (type value-string)
  (cond
    ((string-equal type "boolean")
     (or (string-equal value-string "true") (string-equal value-string "false")))
    ((string-equal type "number")
     (ignore-errors (parse-integer (org-trim value-string))))
    ((string-equal type "string") (plusp (length value-string)))
    (t nil)))

(defun settings--note-write (path)
  (setf *settings-user-org-stat*
        (cons (file-write-date path)
              (with-open-file (s path) (file-length s)))))

(defun settings--create-user-org (path id value-string)
  (ensure-directories-exist (directory-namestring path))
  (with-open-file (s path :direction :output :if-does-not-exist :create
                          :external-format :utf-8)
    (format s "* Settings~%:PROPERTIES:~%:~a: ~a~%:END:~%" id value-string))
  (settings--note-write path)
  t)

(defun settings--append-user-org-drawer (path id value-string)
  (with-open-file (s path :direction :output :if-exists :append
                          :if-does-not-exist :create
                          :external-format :utf-8)
    (format s "~&* Settings~%:PROPERTIES:~%:~a: ~a~%:END:~%"
            id value-string))
  (settings--note-write path)
  t)

(defun settings--rebuild-user-org-drawer (path id value-string)
  "Rebuild the Settings drawer in place: BEFORE + new drawer + AFTER,
spliced by byte offset so every byte outside the drawer — including
the file's trailing-newline behaviour — is preserved."
  (let ((content (read-file-string path)))
    (let ((span (settings--drawer-span content)))
      (when span
        (let ((props (first span)))
          (let ((end (second span)))
            (let ((lines (org-scan-lines content)))
              ;; Body only: the marker lines themselves are not properties.
              (let ((old (settings--parse-properties content lines
                                                     (1+ props) (1- end))))
                (let ((foreign (remove id old :test #'string-equal :key #'car)))
                  (let ((body (append (mapcar (lambda (kv)
                                                (format nil ":~a: ~a" (car kv) (cdr kv)))
                                              foreign)
                                      (list (format nil ":~a: ~a" id value-string)))))
                    (let ((before (subseq content 0
                                            (settings--line-start content props)))
                          (after (let ((n (length lines)))
                                   (if (< end n)
                                       (subseq content
                                               (settings--line-start content (1+ end)))
                                       ""))))
                      (let ((new-content
                              (with-output-to-string (out)
                                (write-string before out)
                                (write-string ":PROPERTIES:" out)
                                (terpri out)
                                (dolist (line body)
                                  (write-string line out)
                                  (terpri out))
                                (write-string ":END:" out)
                                ;; The old :END: line's own terminator
                                ;; decides whether ours has one: when
                                ;; after is empty AND the old file did
                                ;; not end in a newline, emit none.
                                (if (and (string= after "")
                                         (plusp (length content))
                                         (char/= (char content (1- (length content)))
                                                  #\Newline))
                                    nil
                                    (terpri out))
                                (write-string after out))))
                        (let ((tmp (merge-pathnames (make-pathname :type "org.tmp")
                                                      path)))
                          (with-open-file (s tmp :direction :output
                                                  :if-exists :supersede
                                                  :external-format :utf-8)
                            (write-string new-content s))
                          (rename-file tmp path))
                        (settings--note-write path)
                        t))))))))))))

(defun settings--line-start (content line)
  "Byte offset of LINE (1-based) in CONTENT."
  (loop for i from 0 below (length content)
        for count = 0 then (if (char= (char content (1- i)) #\Newline)
                               (1+ count) count)
        when (= count (1- line)) return i
        finally (return (length content))))

(defun settings--write-override (id value-string)
  "Dispatch: create / append / rebuild — always writing via the small
flat helpers above, so the failure surface stays shallow."
  (let ((path (settings-user-org-path)))
    (if (probe-file path)
        (if (settings--drawer-span (read-file-string path))
            (settings--rebuild-user-org-drawer path id value-string)
            (settings--append-user-org-drawer path id value-string))
        (settings--create-user-org path id value-string))))

(defun settings-set (id value-string)
  "Validate ID/VALUE against the schema, then write the override into
user.org — creating file and drawer if missing, replacing a managed
property in place, and preserving every other byte of the file.
Returns :ok, :invalid (unknown id or bad value), or :error."
  (let ((entry (settings-entry id)))
    (unless entry (return-from settings-set :invalid))
    (unless (settings--valid-p (second entry) value-string)
      (return-from settings-set :invalid))
    (if (settings--write-override id value-string)
        (let ((pair (assoc id *settings-overrides* :test #'string-equal)))
          (if pair
              (setf (cdr pair) value-string)
              (push (cons id value-string) *settings-overrides*))
          :ok)
        :error)))

;;; --- The surface (dual-window UI) -------------------------------------------------

(defun settings-open (&optional section)
  "M-x settings: the sidebar becomes the sections column, the viewport
renders the selected section as a settings document."
  (spawn-sidebar "settings")
  (setf *settings-open* t
        *settings-section*
        (or section
            (first (settings-sections))
            "Settings"))
  (bump-document-version)
  (fire-probe :ymacs-settings :open t :section *settings-section*)
  *settings-section*)

(defun settings-close ()
  (setf *settings-open* nil)
  (bump-document-version)
  (fire-probe :ymacs-settings :open nil)
  nil)

(defun settings-handle-action (action body-json values-alist)
  "Handle a settings:* action. Returns (:handled reply) or nil when the
action is not a settings action — control-server dispatches first,
settings owns its namespace."
  (declare (ignore values-alist))
  (labels ((reply ()
             `(("ok" . t) ("document_version" . ,(document-version)))))
    (cond
      ((null action) nil)
      ((string= action "settings")
       (settings-open)
       (list :handled (reply)))
      ((string= action "settings-section")
       (let ((value (cdr (assoc "value" body-json :test #'string=))))
         (when (member value (settings-sections) :test #'string=)
           (setf *settings-section* value)
           (bump-document-version)))
       (list :handled (reply)))
      ((string= action "settings-close")
       (settings-close)
       (list :handled (reply)))
      ((and (>= (length action) 13)
            (string= action "settings-set:" :end1 13 :end2 13))
       ;; settings-set:<id>:<value> — the buttons' encoded form.
       (let* ((rest (subseq action 13))
              (split (position #\: rest)))
         (when split
           (settings-set (subseq rest 0 split) (subseq rest (1+ split)))
           (bump-document-version)
           (list :handled (reply)))))
      (t nil))))

(defun settings-pane-schema ()
  "The RAIL side of the dual-window settings UI: the GNOME-style
sections column. Row ids are section names (the row_action value)."
  (let ((sections (settings-sections)))
    `(("title" . "Settings")
      ("widgets" . ,(coerce
                     (append
                      (list `(("kind" . "label") ("muted" . t)
                              ("text" . "Sections")))
                      (mapcar (lambda (s)
                                `(("kind" . "list-row")
                                  ("id" . ,s)
                                  ("title" . ,s)
                                  ("selected" . ,(and *settings-section*
                                                      (string= *settings-section* s)))
                                  ("row_action" . "settings-section")))
                              sections)
                      (list `(("kind" . "list-row")
                              ("id" . "__close")
                              ("title" . "Close settings")
                              ("row_action" . "settings-close"))))
                     'vector)))))

(defun settings--entry-widgets (id type default desc)
  "The widgets for ONE setting, generated from the schema entry — the
control set is chosen by TYPE, never hand-mirrored."
  (let* ((current (settings-get id))
         (current-str
          (cond ((eq current t) "true")
                ((and (null current) (string-equal type "boolean")) "false")
                (current (princ-to-string current))
                (t "")))
         (controls
          (if (string-equal type "boolean")
              `(("kind" . "toolbar") ("id" . ,(format nil "ctl:~a" id))
                ("buttons" . ,(vector
                               `(("action" . ,(format nil "settings-set:~a:true" id))
                                 ("label" . "On")
                                 ("primary" . ,(eq current t)))
                               `(("action" . ,(format nil "settings-set:~a:false" id))
                                 ("label" . "Off")
                                 ("primary" . ,(not (eq current t)))))))
              ;; No string/number settings exist yet; when one arrives
              ;; its control lands here, schema-driven. No fake buttons.
              `(("kind" . "label") ("muted" . t)
                ("text" . ,(format nil "(~a settings are read-only for now)" type))))))
    (vector
     `(("kind" . "label")
       ("text" . ,(format nil "~a~@[  (default: ~a)~]" (or desc id) default)))
     controls
     `(("kind" . "label") ("muted" . t)
       ("text" . ,(format nil "current: ~a  ·  id: ~a" current-str id))))))

(defun settings-document-schema ()
  "The VIEWPORT side: the selected section as a settings document,
generated from the schema."
  (let ((schema (settings-schema)))
    (cond
      ((null schema)
       `(("title" . "ymacs — Settings")
         ("widgets" . ,(coerce
                        (list `(("kind" . "label")
                                ("text" . "Settings schema not found."))
                              `(("kind" . "label") ("muted" . t)
                                ("text" . "Open init.org in this daemon, run from the repo root, or set YMACS_SETTINGS_SCHEMA.")))
                        'vector))))
      (t
       (let* ((section (or (and *settings-section*
                                (member *settings-section* (settings-sections)
                                        :test #'string=)
                                *settings-section*)
                           (first (settings-sections))))
              (entries (cdr (assoc section schema :test #'string=))))
         `(("title" . ,(format nil "ymacs — Settings: ~a" section))
           ("widgets" . ,(coerce
                          (append
                           (list `(("kind" . "section") ("text" . ,section)))
                           (if entries
                               (loop for (id type default desc) in entries
                                     append (coerce (settings--entry-widgets
                                                     id type default desc)
                                                    'list))
                               (list `(("kind" . "label") ("muted" . t)
                                       ("text" . "No settings in this section yet."))))
                           (list `(("kind" . "toolbar") ("id" . "settings-footer")
                                   ("buttons" . ,(vector
                                                  `(("action" . "settings-close")
                                                    ("label" . "✓ Done")
                                                    ("title" . "Back to the buffer")
                                                    ("primary" . t))))))
                           (list `(("kind" . "label") ("muted" . t)
                                   ("text" . ,(format nil "Overrides: ~a (hand-editable — two views of one store)"
                                                      (settings-user-org-path))))))
                          'vector))))))))

(defcommand settings (&optional section)
  "Open the settings system: sections in the sidebar, the selected
section as the viewport document. Overrides land in user.org."
  ;; Empty spec: bare (interactive) never registers, leaving M-x unable
  ;; to name this command (found while wiring M-x sidebar).
  (interactive "")
  (settings-open section))

(defun settings--read-user-org-for-test ()
  (when (probe-file (settings-user-org-path))
    (read-file-string (settings-user-org-path))))

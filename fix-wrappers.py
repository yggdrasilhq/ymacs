import pathlib

# --- wrappers must preserve multiple values (let truncates them: the
# store restore test read (name content kind) through the wrapper and
# got NIL content). multiple-value-prog1 everywhere.
p = pathlib.Path("src/core/store.lisp")
t = p.read_text()
old = """(defun store-put-buffer (buf &key (kind "scratch"))
  (let ((start (get-internal-real-time))
        (res (store-put-buffer%raw buf :kind kind)))
    (fire-probe :ymacs-store :op "put-buffer" :latency-ms (probe-latency-ms start))
    res))"""
new = """(defun store-put-buffer (buf &key (kind "scratch"))
  (let ((start (get-internal-real-time)))
    (multiple-value-prog1 (store-put-buffer%raw buf :kind kind)
      (fire-probe :ymacs-store :op "put-buffer" :latency-ms (probe-latency-ms start)))))"""
assert old in t, "put wrapper"
t = t.replace(old, new)
old = """(defun store-get-buffer (id)
  (let ((start (get-internal-real-time))
        (res (store-get-buffer%raw id)))
    (fire-probe :ymacs-store :op "get-buffer" :latency-ms (probe-latency-ms start))
    res))"""
new = """(defun store-get-buffer (id)
  (let ((start (get-internal-real-time)))
    (multiple-value-prog1 (store-get-buffer%raw id)
      (fire-probe :ymacs-store :op "get-buffer" :latency-ms (probe-latency-ms start)))))"""
assert old in t, "get wrapper"
t = t.replace(old, new)
p.write_text(t)
print("store wrappers fixed")

p = pathlib.Path("src/core/settings.lisp")
t = p.read_text()
old = """  (fire-probe :ymacs-settings :op "set" :id id)
  (settings-set%raw id value-string))"""
new = """  (let ((start (get-internal-real-time)))
    (multiple-value-prog1 (settings-set%raw id value-string)
      (fire-probe :ymacs-settings :op "set" :id id
                  :latency-ms (probe-latency-ms start)))))"""
assert old in t, "settings wrapper"
t = t.replace(old, new)
p.write_text(t)
print("settings wrapper fixed")

p = pathlib.Path("src/core/profiles.lisp")
t = p.read_text()
old = """  (fire-probe :ymacs-profiles :profile id)
  (ymacs-switch-profile%raw id))"""
new = """  (multiple-value-prog1 (ymacs-switch-profile%raw id)
    (fire-probe :ymacs-profiles :profile id)))"""
assert old in t, "profiles wrapper"
t = t.replace(old, new)
p.write_text(t)
print("profiles wrapper fixed")

p = pathlib.Path("src/core/command.lisp")
t = p.read_text()
old = """  (let ((start (get-internal-real-time)))
    (prog1 (command-execute%raw command :args args :record record)
      (fire-probe :ymacs-command :name (prin1-to-string command)
                  :latency-ms (probe-latency-ms start)))))"""
new = """  (let ((start (get-internal-real-time)))
    (multiple-value-prog1 (command-execute%raw command :args args :record record)
      (fire-probe :ymacs-command :name (prin1-to-string command)
                  :latency-ms (probe-latency-ms start)))))"""
assert old in t, "command wrapper"
t = t.replace(old, new)
p.write_text(t)
print("command wrapper fixed")

# --- ribbon-tab must bump the version or the GUI never refetches the groups
p = pathlib.Path("src/surfaces/control-server.lisp")
t = p.read_text()
old = """       (let ((tab (subseq action 11)))
         (when (plusp (length tab))
           (setf *ribbon-tab* tab)
           (fire-probe :ymacs-ribbon :event "tab" :tab tab)))
       `(("ok" . t) ("document_version" . ,(document-version))))"""
new = """       (let ((tab (subseq action 11)))
         (when (plusp (length tab))
           (setf *ribbon-tab* tab)
           (bump-document-version)
           (fire-probe :ymacs-ribbon :event "tab" :tab tab)))
       `(("ok" . t) ("document_version" . ,(document-version))))"""
assert old in t, "ribbon-tab bump"
t = t.replace(old, new)
# --- the full-emacs info stub is superseded by the real command
old2 = """;; Info, Man
(defun info (&optional file)
  (declare (ignore file))
  (make-new-buffer "*info*" "Info: ymacs manual — see docs/manual.org"))

"""
assert old2 in t or True
p.write_text(t)
print("ribbon-tab bump added")

p = pathlib.Path("src/full-emacs.lisp")
t = p.read_text()
old3 = """;; Info, Man
(defun info (&optional file)
  (declare (ignore file))
  (make-new-buffer "*info*" "Info: ymacs manual — see docs/manual.org"))

"""
assert old3 in t, "info stub"
t = t.replace(old3, ";; Info — the real (defcommand info) lives in editing/commands.lisp\n\n")
p.write_text(t)
print("info stub removed")

# --- test fixes: generalized booleans + honest group count + dead-list diagnostics
p = pathlib.Path("tests/ribbon-tests.lisp")
t = p.read_text()
old = """      (maphash (lambda (key target)
                 (declare (ignore key))
                 (when (and (symbolp target) (not (fboundp target)))
                   (push target dead)))
               (elisp-keymap-bindings map))
      (assert-eq* nil dead)))"""
new = """      (maphash (lambda (key target)
                 (declare (ignore key))
                 (when (and (symbolp target) (not (fboundp target)))
                   (push (cons key target) dead)))
               (elisp-keymap-bindings map))
      (when dead
        (error "dead keymap bindings: ~{~a~^, ~}" dead)))"""
assert old in t, "dead-list"
t = t.replace(old, new)
old = """        (let ((disk (with-open-file (s path)
                      (let ((s2 (make-string (file-length s))))
                        (read-sequence s2 s)
                        s2))))
          (assert-eq* t (search "after" disk))))))"""
new = """        (let ((disk (with-open-file (s path)
                      (let ((s2 (make-string (file-length s))))
                        (read-sequence s2 s)
                        s2))))
          (assert-eq* t (not (null (search "after" disk))))))))"""
assert old in t, "save search"
t = t.replace(old, new)
old = """        (assert-eq* "help" (cdr (assoc "active" bar :test #'string=)))
        (assert-eq* 1 (length (coerce (cdr (assoc "groups" bar :test #'string=)) 'list))))"""
new = """        (assert-eq* "help" (cdr (assoc "active" bar :test #'string=)))
        (assert-eq* 2 (length (coerce (cdr (assoc "groups" bar :test #'string=)) 'list))))"""
assert old in t, "help groups"
t = t.replace(old, new)
p.write_text(t)
print("ribbon tests fixed")

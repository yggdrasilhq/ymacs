import pathlib

# honesty test: enumerate the KEY-PLANE keymap (*global-map*), not the
# unused compat-layer "global" entry — two keymap systems, only one is real.
p = pathlib.Path("tests/ribbon-tests.lisp")
t = p.read_text()
old = """  (test "every default keymap binding names a real command (honesty law)"
    (unless (gethash "global" *elisp-keymaps*)
      (init-default-keymaps))
    (let ((map (gethash "global" *elisp-keymaps*))
          (dead nil))
      (assert-eq* t (not (null map)))
      (maphash (lambda (key target)
                 (declare (ignore key))
                 (when (and (symbolp target) (not (fboundp target)))
                   (push (cons key target) dead)))
               (elisp-keymap-bindings map))
      (when dead
        (error "dead keymap bindings: ~{~a~^, ~}" dead)))))"""
new = """  (test "every default keymap binding names a real command (honesty law)"
    ;; *global-map* is the key plane's own table — the compat-layer
    ;; *elisp-keymaps* "global" entry is a different, unused system.
    (let ((dead nil))
      (maphash (lambda (key target)
                 (declare (ignore key))
                 (when (and (symbolp target) (not (fboundp target)))
                   (push (cons key target) dead)))
               (elisp-keymap-bindings *global-map*))
      (when dead
        (error "dead keymap bindings: ~{~a~^, ~}" dead)))))"""
assert old in t, "honesty test anchor"
t = t.replace(old, new)
p.write_text(t)
print("honesty test fixed")

# store test 1: honor the file's own sandbox law — it ran against the
# LIVE daemon store and loses when another process holds the file.
p = pathlib.Path("tests/store-tests.lisp")
t = p.read_text()
old = """    (stest "unnamed buffers persist at create and restore by id"
      (store-open)"""
new = """    (stest "unnamed buffers persist at create and restore by id"
      (let ((*store-path-override* (sb-store-path "persist")))
        (store-open)"""
assert old in t, "store test 1 anchor"
t = t.replace(old, new)
# close the added let: the test body ends with (store-close)))  — add one closer
old2 = """          (kill-buffer id)
          (assert-eq* nil (store-buffer-exists-p id))))
      (store-close)))"""
new2 = """          (kill-buffer id)
          (assert-eq* nil (store-buffer-exists-p id))))
        (store-close))))"""
assert old2 in t, "store test 1 closer"
t = t.replace(old2, new2)
p.write_text(t)
print("store test 1 sandboxed")

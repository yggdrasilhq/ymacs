# ELPA & MELPA Compatibility in ymacs

`ymacs` targets **~90% plug-and-play compatibility** with the extensive Emacs Lisp ecosystem while retaining the advantages of a pure Common Lisp engine.

## 1. How Compatibility Works

1. **Emacs Lisp Reader & Macro Expander:**
   - An integrated Emacs Lisp compat layer reads standard `.el` files, converting Emacs Lisp symbols, scoping rules, and special forms into compiled Common Lisp equivalents.
2. **Buffer & Window API Emulation:**
   - Standard functions (`current-buffer`, `insert`, `delete-region`, `point`, `mark`, `save-excursion`, `with-current-buffer`) map directly to native `ymacs` buffer primitives.
3. **Keymap & Hook System:**
   - Emulates `define-key`, `global-set-key`, `add-hook`, `run-hooks`, and mode definitions (`define-derived-mode`, `define-minor-mode`).
4. **Package Management:**
   - Compatible with `package.el` archive formats from ELPA and MELPA. Packages can be fetched, unpacked, byte-compiled, and autoloaded into the running image.

## 2. Departures from Archaic Emacs

- Blocking synchronous HTTP fetches (`url-retrieve-synchronously`) run asynchronously in background threads.
- UI prompts (`y-or-n-p`) render as clean non-modal status prompts or sidebar chips rather than hijacking the minibuffer.
- Archaic backup files (`#file#`, `file~`) are replaced with atomic transactional sqlite state.

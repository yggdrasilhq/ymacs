;;;; build.lisp --- Produce ymacs binary image via SBCL save-lisp-and-die
(require :asdf)
(require :sb-bsd-sockets)
(let ((base (truename *default-pathname-defaults*)))
  (push (merge-pathnames "src/" base) asdf:*central-registry*)
  (push base asdf:*central-registry*)
  ;; Vendored ecosystems (cl-sqlite + cffi + friends) — same doctrine as
  ;; Rust's vendored crates: imports, not hand-rolled FFI.
  (let ((vendor (merge-pathnames "vendor/" base)))
    (when (probe-file vendor)
      (dolist (sd (directory (merge-pathnames "*/" vendor)))
        (pushnew sd asdf:*central-registry*)))))
(asdf:load-system :ymacs)
;; *ymacs-version*'s SSOT is the system version (ymacs.asd) — the defvar in
;; main.lisp is only the interpreted-mode fallback. Stamp the loaded system's
;; version into the image before the dump so --version can never drift.
(setf ymacs::*ymacs-version* (asdf:component-version (asdf:find-system :ymacs)))
(format t "~&[build] Loaded ymacs ~a~%" (asdf:component-version (asdf:find-system :ymacs)))
(format t "[build] Dumping image to ymacs-bin~%")
(sb-ext:save-lisp-and-die "ymacs-bin"
                          :toplevel #'ymacs:main
                          :executable t
                          :save-runtime-options t)

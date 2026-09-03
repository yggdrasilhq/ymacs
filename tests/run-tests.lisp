;;;; run-tests.lisp --- load ymacs and run the contract tests.
;;;; Usage: sbcl --noinform --disable-debugger --load tests/run-tests.lisp
;;;; Exits non-zero on any failure.

(require :asdf)
(push #P"./" asdf:*central-registry*)
(push #P"./src/" asdf:*central-registry*)
(asdf:load-system :ymacs)
(load "tests/command-tests.lisp")
(load "tests/keyboard-tests.lisp")
(load "tests/frames-tests.lisp")
(load "tests/org-tests.lisp")
(load "tests/settings-tests.lisp")
(load "tests/surface-tests.lisp")
(load "tests/sidebar-tests.lisp")

(sb-ext:quit :unix-status (if (and (ymacs::run-command-tests)
                                   (ymacs::run-keyboard-tests)
                                   (ymacs::run-frames-tests)
                                   (ymacs::run-org-tests)
                                   (ymacs::run-settings-tests)
                                   (ymacs::run-surface-tests)
                                   (ymacs::run-sidebar-tests))
                              0 1))

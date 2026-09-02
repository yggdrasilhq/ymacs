;;;; run-tests.lisp --- load ymacs and run the contract tests.
;;;; Usage: sbcl --noinform --disable-debugger --load tests/run-tests.lisp
;;;; Exits non-zero on any failure.

(require :asdf)
(push #P"./" asdf:*central-registry*)
(push #P"./src/" asdf:*central-registry*)
(asdf:load-system :ymacs)
(load "tests/command-tests.lisp")

(sb-ext:quit :unix-status (if (ymacs::run-command-tests) 0 1))

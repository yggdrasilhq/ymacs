;;;; store-runner.lisp --- the store suite runs in its OWN image: the
;;;; sqlite FFI + save-lisp-free sandbox state must not poison (or be
;;;; poisoned by) the big combined suite process. Run:
;;;;   sbcl --load tests/store-runner.lisp   (exit 0 = all green)
(require :asdf)
(push #P"./" asdf:*central-registry*)
(push #P"./src/" asdf:*central-registry*)
(dolist (sd (directory "vendor/*/")) (pushnew sd asdf:*central-registry*))
(asdf:load-system :ymacs)
(load "tests/command-tests.lisp")     ; test/assert helpers + *test-pass*
(load "tests/store-tests.lisp")
(sb-ext:quit :unix-status (if (ymacs::run-store-tests) 0 1))

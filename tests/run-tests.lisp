;;;; run-tests.lisp --- load ymacs and run the contract tests.
;;;; Usage: sbcl --noinform --disable-debugger --load tests/run-tests.lisp
;;;; Exits non-zero on any failure.

(require :asdf)
(push #P"./" asdf:*central-registry*)
(push #P"./src/" asdf:*central-registry*)
;; vendored ecosystem (see build.lisp)
(when (probe-file "vendor/")
  (dolist (sd (directory "vendor/*/"))
    (pushnew sd asdf:*central-registry*)))
(asdf:load-system :ymacs)
(load "tests/command-tests.lisp")
(load "tests/keyboard-tests.lisp")
(load "tests/frames-tests.lisp")
(load "tests/org-tests.lisp")
(load "tests/settings-tests.lisp")
(load "tests/surface-tests.lisp")
(load "tests/sidebar-tests.lisp")
(load "tests/schema-tests.lisp")
(load "tests/ingress-tests.lisp")
(load "tests/elpa-corpus-tests.lisp")

(let ((every-lisp-suite
        (and (ymacs::run-command-tests)
             (ymacs::run-keyboard-tests)
             (ymacs::run-frames-tests)
             (ymacs::run-org-tests)
             (ymacs::run-settings-tests)
             (ymacs::run-surface-tests)
             (ymacs::run-sidebar-tests)
             (ymacs::run-schema-tests)
             (ymacs::run-toolbar-tests)
             (ymacs::run-ingress-tests)
             (ymacs::run-corpus-tests))))
  ;; The store suite runs in its own image (see tests/store-runner.lisp):
  ;; the sqlite FFI must not poison, or be poisoned by, the big combined
  ;; suite process. Propagate the child's exit status.
  (let* ((proc (ignore-errors
                 (sb-ext:run-program "sbcl"
                                     (list "--noinform" "--disable-debugger"
                                           "--no-sysinit" "--no-userinit"
                                           "--load" "tests/store-runner.lisp")
                                     :search t :wait t)))
         (store-ok (and proc (= (sb-ext:process-exit-code proc) 0))))
    (format t "ymacs durable-store suite: ~a~%"
            (if store-ok "ok" "FAILED"))
    (force-output)
    (sb-ext:quit :unix-status (if (and every-lisp-suite store-ok) 0 1))))

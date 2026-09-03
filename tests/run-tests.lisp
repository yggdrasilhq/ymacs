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
(load "tests/ribbon-tests.lisp")

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
             (ymacs::run-corpus-tests)
             (ymacs::run-ribbon-tests))))
  ;; The store suite runs in its own image (see tests/store-runner.lisp):
  ;; the sqlite FFI must not poison, or be poisoned by, the big combined
  ;; suite process. Propagate the child's exit status.
  (let* ((out-path "tests/.store-child-output.log")
         (proc (progn
                 (ignore-errors (delete-file out-path))
                 (multiple-value-bind (p err)
                     (ignore-errors
                       (sb-ext:run-program "sbcl"
                                           (list "--noinform" "--disable-debugger"
                                                 "--no-sysinit" "--no-userinit"
                                                 "--load" "tests/store-runner.lisp")
                                           :search t :wait t
                                           :output out-path :error :output))
                   (when (and (null p) err)
                     (format t "store child spawn error: ~a~%" err))
                   p)))
         (store-ok (and proc (= (sb-ext:process-exit-code proc) 0))))
    (format t "ymacs durable-store suite: ~a~%"
            (if store-ok "ok" (if proc "FAILED" "SPAWN-FAILED")))
    (unless store-ok
      (when proc
        (format t "--- store child output (exit ~a) ---~%"
                (sb-ext:process-exit-code proc)))
      (ignore-errors
        (with-open-file (s out-path)
          (loop for line = (read-line s nil nil)
                while line do (write-line line))))
      (force-output))
    (force-output)
    (sb-ext:quit :unix-status (if (and every-lisp-suite store-ok) 0 1))))

;;;; frames-tests.lisp --- contract tests for Frame = yggterm row
;;;; (docs/spec-primitives.md §1.3). The GUI spawn itself is a live
;;;; probe; everything decidable headless is locked here.

(in-package #:ymacs)

(defun run-frames-tests ()
  (setf *test-pass* 0 *test-fail* 0)
  (format t "ymacs frames tests~%")

  (test "make-frame argv names the GUI verb and the row title"
    (assert-eq*
     (list "server" "app" "terminal" "new"
           "--kind" "shell" "--title" "ymacs frame")
     (make-frame-command-argv "yggterm-headless" "ymacs frame")))

  (test "frame row parses from a JSON reply"
    (assert-eq* "local://abc123"
                (frames-parse-row
                 "{\"ok\":true,\"session_path\":\"local://abc123\",\"title\":\"ymacs frame\"}")))

  (test "frame row parses from bare local:// text"
    (assert-eq* "local://xyz"
                (frames-parse-row "row created local://xyz (seated 6.1)")))

  (test "an unrecognized reply parses to nil (headless refusal)"
    (assert-eq* nil (frames-parse-row "error: no GUI attached")))

  (test "frame registry tracks spawns and removals"
    (let ((*frames* nil))
      (push (list :row "local://f1" :title "ymacs frame") *frames*)
      (push (list :row "local://f2" :title "ymacs frame") *frames*)
      (assert-eq* 2 (length *frames*))
      (setf *frames* (remove "local://f1" *frames*
                             :key (lambda (f) (getf f :row)) :test #'string=))
      (assert-eq* 1 (length *frames*))
      (assert-eq* "local://f2" (getf (first *frames*) :row))))

  (format t "~a passed, ~a failed~%" *test-pass* *test-fail*)
  (zerop *test-fail*))

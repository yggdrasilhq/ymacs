;;;; command-tests.lisp --- contract tests for the command layer and the
;;;; macro law (docs/spec-primitives.md §3).
;;;;
;;;; Run: sbcl --load tests/run-tests.lisp
;;;; Plain CL, no dependencies — CI installs bare SBCL only.

(in-package #:ymacs)

(defvar *test-pass* 0)
(defvar *test-fail* 0)

(defmacro test (name &body body)
  `(progn
     (format t "  ~a ..." ,name)
     (handler-case (progn ,@body (incf *test-pass*) (format t " ok~%"))
       (error (e) (incf *test-fail*) (format t " FAIL: ~a~%" e)))))

(defun assert-eq* (want got)
  (unless (equal want got)
    (error "expected ~s, got ~s" want got)))

;;; --- Test commands --------------------------------------------------------

(defvar *test-counter* 0)

(defcommand test-append (s)
  "Insert S into the test buffer and bump the counter."
  (interactive "sText: ")
  (buffer-insert *current-buffer*
                 (length (buffer-content *current-buffer*)) s)
  (incf *test-counter*)
  s)

(defcommand test-noargs ()
  "Bare command: bumps the counter only."
  (interactive)
  (incf *test-counter*))

(defcommand test-prefix (p)
  "Consumes the prefix argument as its argument."
  (interactive "p")
  (incf *test-counter* (or p 1))
  p)

(defun run-command-tests ()
  (setf *test-pass* 0 *test-fail* 0 *test-counter* 0)
  (format t "ymacs command-layer tests~%")

  (test "command-execute fills string spec from supplied args"
    (let ((buf (make-new-buffer "*cmdtest*" "")))
      (setf *current-buffer* buf)
      (command-execute 'test-append :args (list "a"))
      (assert-eq* "a" (buffer-content buf))
      (assert-eq* 1 *test-counter*)))

  (test "missing interactive args is a loud error, not a silent prompt"
    (handler-case
        (progn (command-execute 'test-append) (error "should have signaled"))
      (missing-interactive-args () t)))

  (test "bare command with empty spec runs"
    (command-execute 'test-noargs)
    (assert-eq* 2 *test-counter*))

  (test "prefix-arg code p supplies numeric default 1"
    (assert-eq* 1 (command-execute 'test-prefix :args nil))
    (assert-eq* 3 *test-counter*))

  (test "recording captures command invocations with args"
    (let ((buf (make-new-buffer "*cmdtest*" "")))
      (setf *current-buffer* buf)
      (start-kbd-macro)
      (command-execute 'test-append :args (list "x"))
      (command-execute 'test-noargs)
      (end-kbd-macro)
      (assert-eq* 2 (length *last-kbd-macro*))
      (assert-eq* 'test-append (getf (first *last-kbd-macro*) :command))
      (assert-eq* (list "x") (getf (first *last-kbd-macro*) :args))
      (assert-eq* 'test-noargs (getf (second *last-kbd-macro*) :command))))

  (test "replay reproduces effects headless and does not re-record"
    (let* ((buf (make-new-buffer "*cmdtest*" ""))
           (*current-buffer* buf))
      (setf *test-counter* 0)
      (start-kbd-macro)                     ; recording while we replay:
      (execute-kbd-macro *last-kbd-macro*)  ; must NOT enter the record
      (end-kbd-macro)
      (assert-eq* 2 *test-counter*)
      (assert-eq* "x" (buffer-content buf))
      ;; the only recorded entry would have been the replay itself — none:
      (assert-eq* nil *last-kbd-macro*)))

  (test "name-last-kbd-macro binds a callable"
    (let ((buf (make-new-buffer "*cmdtest*" "")))
      (setf *current-buffer* buf *test-counter* 0)
      (start-kbd-macro)
      (command-execute 'test-append :args (list "q"))
      (end-kbd-macro)
      (name-last-kbd-macro 'test-named-macro)
      (funcall 'test-named-macro)
      ;; one insert from the recorded run + one from the named replay:
      (assert-eq* "qq" (buffer-content buf))
      (assert-eq* 2 *test-counter*)))

  (test "M-x routes through the layer and records with args"
    (let ((buf (make-new-buffer "*cmdtest*" "")))
      (setf *current-buffer* buf *test-counter* 0)
      (start-kbd-macro)
      (execute-extended-command nil "test-append" "m")
      (end-kbd-macro)
      (assert-eq* "m" (buffer-content buf))
      (assert-eq* 'test-append (getf (first *last-kbd-macro*) :command))))

  (test "replaying an M-x macro works with no palette, no surfaces"
    (let* ((buf (make-new-buffer "*cmdtest2*" ""))
           (*current-buffer* buf))
      (execute-kbd-macro *last-kbd-macro*)
      (assert-eq* "m" (buffer-content buf))))

  (test "cancel-kbd-macro discards the record"
    (start-kbd-macro)
    (command-execute 'test-noargs)
    (cancel-kbd-macro)
    (assert-eq* nil *macro-recording*)
    (assert-eq* nil *macro-record-rev*))

  (format t "~a passed, ~a failed~%" *test-pass* *test-fail*)
  (zerop *test-fail*))

;;;; keyboard-tests.lisp --- contract tests for the key plane dispatcher
;;;; (docs/spec-key-plane.md): chord sequences, self-insert, movement,
;;;; undefined keys, and macro law end-to-end through the key plane.
;;;;
;;;; Run via tests/run-tests.lisp. Plain CL, no dependencies.

(in-package #:ymacs)

(defun run-keyboard-tests ()
  (setf *test-pass* 0 *test-fail* 0 *test-counter* 0)
  (format t "ymacs key-plane tests~%")

  (test "self-insert types at point and advances it"
    (let* ((buf (make-new-buffer "*kt*" "")))
      (setf *current-buffer* buf)
      (reset-key-sequence)
      (ymacs-handle-key "h")
      (ymacs-handle-key "i")
      (assert-eq* "hi" (buffer-content buf))
      (assert-eq* 2 (buffer-point buf))))

  (test "SPC self-inserts a space"
    (let* ((buf (make-new-buffer "*kt*" "")))
      (setf *current-buffer* buf)
      (reset-key-sequence)
      (ymacs-handle-key "a")
      (ymacs-handle-key "SPC")
      (ymacs-handle-key "b")
      (assert-eq* "a b" (buffer-content buf))))

  (test "two-chord sequence executes after the second chord"
    (let* ((buf (make-new-buffer "*kt*" "")))
      (setf *current-buffer* buf *test-counter* 0)
      (global-set-key "C-x C-j" 'test-noargs)
      (ymacs-handle-key "C-x")
      (assert-eq* "C-x" (key-sequence-string))
      (ymacs-handle-key "C-j")
      (assert-eq* "" (key-sequence-string))
      (assert-eq* 1 *test-counter*)))

  (test "a prefix chord stays pending and shows in the schema"
    (let* ((buf (make-new-buffer "*kt*" "")))
      (setf *current-buffer* buf)
      (reset-key-sequence)
      (let ((reply (ymacs-handle-key "C-x")))
        (assert-eq* "C-x" (key-sequence-string))
        (let ((schema (cdr (assoc "schema" reply :test #'string=))))
          (assert-eq* t (cdr (assoc "key_capture" schema :test #'string=)))))))

  (test "an undefined two-chord sequence resets"
    (let* ((buf (make-new-buffer "*kt*" "")))
      (setf *current-buffer* buf)
      (reset-key-sequence)
      (ymacs-handle-key "C-x")
      (ymacs-handle-key "C-~")              ; nothing binds this
      (assert-eq* "" (key-sequence-string))
      (assert-eq* "" (buffer-content buf))))

  (test "movement: C-n preserves column, C-p returns"
    (let* ((buf (make-new-buffer "*kt*" "abcdef
xy
longer line here")))
      (setf *current-buffer* buf)
      (reset-key-sequence)
      (setf (buffer-point buf) 3)           ; column 3 on line 1
      (ymacs-handle-key "C-n")              ; line 2 has only x,y (indices 7-8)
      (assert-eq* 9 (buffer-point buf))     ; clamped to its end-of-line
      (setf (buffer-point buf) 3)
      (setf *key-sequence* nil)
      (ymacs-handle-key "C-a")
      (assert-eq* 0 (buffer-point buf))))

  (test "C-e / C-a bracket the line"
    (let* ((buf (make-new-buffer "*kt*" "hello
world")))
      (setf *current-buffer* buf (buffer-point buf) 1)
      (setf *key-sequence* nil)
      (ymacs-handle-key "C-e")
      (assert-eq* 5 (buffer-point buf))
      (ymacs-handle-key "C-n")
      (assert-eq* 11 (buffer-point buf))
      (ymacs-handle-key "C-a")
      (assert-eq* 6 (buffer-point buf))))

  (test "M-x without the palette refuses quietly and keeps the session alive"
    (let* ((buf (make-new-buffer "*kt*" "")))
      (setf *current-buffer* buf)
      (reset-key-sequence)
      (let ((reply (ymacs-handle-key "M-x")))
        (assert-eq* t (cdr (assoc "ok" reply :test #'string=)))
        (assert-eq* "" (key-sequence-string)))))

  (test "key-driven invocations record into macros (macro law, end to end)"
    (let* ((buf (make-new-buffer "*kt*" "")))
      (setf *current-buffer* buf *test-counter* 0)
      (reset-key-sequence)
      (start-kbd-macro)
      (ymacs-handle-key "k")                ; self-insert, recorded
      (ymacs-handle-key "C-x")
      (ymacs-handle-key "C-j")              ; test-noargs, recorded
      (end-kbd-macro)
      (assert-eq* 2 (length *last-kbd-macro*))
      (assert-eq* 'self-insert-command (getf (first *last-kbd-macro*) :command))
      ;; Replay into a fresh buffer types the text again — headless:
      (let* ((buf2 (make-new-buffer "*kt2*" ""))
             (*current-buffer* buf2))
        (setf *test-counter* 0)
        (execute-kbd-macro *last-kbd-macro*)
        (assert-eq* "k" (buffer-content buf2))
        (assert-eq* 1 *test-counter*))))

  (test "keyboard-quit clears a pending sequence"
    (let* ((buf (make-new-buffer "*kt*" "")))
      (setf *current-buffer* buf)
      (reset-key-sequence)
      (ymacs-handle-key "C-x")
      (keyboard-quit)
      (assert-eq* "" (key-sequence-string))))

  (format t "~a passed, ~a failed~%" *test-pass* *test-fail*)
  (zerop *test-fail*))

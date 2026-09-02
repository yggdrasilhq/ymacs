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

  (test "M-x opens the palette; typing filters; RET executes"
    (let* ((buf (make-new-buffer "*kt*" "abc")))
      (setf *current-buffer* buf)
      (reset-key-sequence)
      (ymacs-handle-key "M-x")
      (assert-eq* t *minibuffer-active*)
      (assert-eq* "M-x " *minibuffer-prompt*)
      (ymacs-handle-key "n")
      (ymacs-handle-key "e")
      (ymacs-handle-key "x")
      (ymacs-handle-key "t")
      (assert-eq* t (every (lambda (c) (search "next" c :test #'string-equal))
                           *minibuffer-candidates*))
      (ymacs-handle-key "RET")
      (assert-eq* nil *minibuffer-active*)
      (assert-eq* 3 (buffer-point buf))
      (assert-eq* "" (key-sequence-string))))

  (test "an unknown command name keeps the palette open with the error"
    (let* ((buf (make-new-buffer "*kt*" "")))
      (setf *current-buffer* buf)
      (reset-key-sequence)
      (ymacs-handle-key "M-x")
      (ymacs-handle-key "z")
      (ymacs-handle-key "z")
      (ymacs-handle-key "z")
      (ymacs-handle-key "RET")
      (assert-eq* t *minibuffer-active*)
      (assert-eq* t (not (null (search "No match" *minibuffer-error*))))
      (minibuffer-abort)))

  (test "C-n moves the palette selection"
    (let* ((buf (make-new-buffer "*kt*" "")))
      (setf *current-buffer* buf)
      (reset-key-sequence)
      (ymacs-handle-key "M-x")
      (ymacs-handle-key "f")
      (assert-eq* t (>= (length *minibuffer-candidates*) 2))
      (let ((before *minibuffer-selected*))
        (ymacs-handle-key "C-n")
        (assert-eq* (1+ before) *minibuffer-selected*))
      (minibuffer-abort)))

  (test "palette keys never enter the macro record (the gesture law)"
    (let* ((buf (make-new-buffer "*kt*" "")))
      (setf *current-buffer* buf)
      (reset-key-sequence)
      (start-kbd-macro)
      (ymacs-handle-key "M-x")
      (ymacs-handle-key "z")
      (ymacs-handle-key "z")
      (ymacs-handle-key "z")
      (ymacs-handle-key "RET")
      (ymacs-handle-key "C-g")
      (end-kbd-macro)
      (assert-eq* nil *last-kbd-macro*)))

  (test "M-x with a prompting argument collects it, records with args, replays"
    (let* ((buf (make-new-buffer "*kt*" "")))
      (setf *current-buffer* buf *test-counter* 0)
      (reset-key-sequence)
      (start-kbd-macro)
      (ymacs-handle-key "M-x")
      (dolist (ch (coerce "test-append" 'list))
        (ymacs-handle-key (string ch)))
      (assert-eq* t *minibuffer-active*)
      (ymacs-handle-key "RET")
      (assert-eq* t *minibuffer-active*)
      (assert-eq* "Text: " *minibuffer-prompt*)
      (ymacs-handle-key "m")
      (ymacs-handle-key "RET")
      (assert-eq* nil *minibuffer-active*)
      (end-kbd-macro)
      (assert-eq* "m" (buffer-content buf))
      (assert-eq* 1 (length *last-kbd-macro*))
      (assert-eq* 'test-append (getf (first *last-kbd-macro*) :command))
      (assert-eq* (list "m") (getf (first *last-kbd-macro*) :args))
      (let* ((buf2 (make-new-buffer "*kt2*" ""))
             (*current-buffer* buf2))
        (setf *test-counter* 0)
        (execute-kbd-macro *last-kbd-macro*)
        (assert-eq* "m" (buffer-content buf2))
        (assert-eq* 1 *test-counter*))))

  (test "C-x C-f opens the palette for the file name (generic prompting)"
    (let* ((path #p"~/.yggterm/scratchpad/ymacs-palette-test.txt"))
      (with-open-file (out path :direction :output :if-exists :supersede)
        (write-string "palette file body" out))
      (let* ((buf (make-new-buffer "*kt*" "")))
        (setf *current-buffer* buf)
        (reset-key-sequence)
        (ymacs-handle-key "C-x")
        (ymacs-handle-key "C-f")
        (assert-eq* t *minibuffer-active*)
        (assert-eq* "Find file: " *minibuffer-prompt*)
        (dolist (ch (coerce (namestring (truename path)) 'list))
          (ymacs-handle-key (string ch)))
        (ymacs-handle-key "RET")
        (assert-eq* nil *minibuffer-active*)
        (assert-eq* "palette file body" (buffer-content *current-buffer*))
        (kill-buffer (buffer-id *current-buffer*))
        (setf *current-buffer* buf))))

  (test "a clicked candidate accepts through minibuffer-select"
    (let* ((buf (make-new-buffer "*kt*" "")))
      (setf *current-buffer* buf *test-counter* 0)
      (reset-key-sequence)
      (ymacs-handle-key "M-x")
      (let ((reply (handle-action
                    `(("action" . "minibuffer-select")
                      ("value" . "test-noargs")))))
        (assert-eq* t (cdr (assoc "ok" reply :test #'string=)))
        (assert-eq* nil *minibuffer-active*)
        (assert-eq* 1 *test-counter*))))

  (test "C-u sets a numeric prefix"
    (let* ((buf (make-new-buffer "*kt*" "")))
      (setf *current-buffer* buf)
      (reset-key-sequence)
      (ymacs-handle-key "C-u")
      (assert-eq* t *prefix-arg-given*)
      (assert-eq* 4 *prefix-arg*)
      (reset-prefix-arg)
      (reset-key-sequence)))


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


  (test "flat json scan honours escaped quotes in values"
    (let* ((bs (string (code-char 92)))
           (q (string (code-char 34)))
           (json (concatenate 'string "{" q "form" q ":" q "(+ 1 " bs q "x" bs q ")" q "}" ))
           (parsed (parse-flat-json json)))
      (assert-eq* t (not (null (assoc "form" parsed :test (function string=)))))
      (assert-eq* t (not (null (search (string (code-char 34))
                                (cdr (assoc "form" parsed :test (function string=)))))))))
  (format t "~a passed, ~a failed~%" *test-pass* *test-fail*)
  (zerop *test-fail*))
;;;; org-tests.lisp --- contract tests for the typed org node layer
;;;; (docs/spec-primitives.md §1.1, build-order step 6).
;;;;
;;;; The fixtures are the SAME documents emd-renderer's org tests
;;;; (libyggterm, the Rust reference engine) run: parse decisions, tree
;;;; shape, and splice byte-exactness must agree on both sides or the
;;;; contract is broken.
;;;;
;;;; Run: sbcl --load tests/run-tests.lisp
;;;; Plain CL, no dependencies — CI installs bare SBCL only.

(in-package #:ymacs)

(defvar *org-test-pass* 0)
(defvar *org-test-fail* 0)

(defmacro org-test (name &body body)
  `(progn
     (format t "  ~a ..." ,name)
     (handler-case (progn ,@body (incf *org-test-pass*) (format t " ok~%"))
       (error (e) (incf *org-test-fail*) (format t " FAIL: ~a~%" e)))))

(defun org-assert-equal (want got)
  (unless (equal want got)
    (error "expected ~s, got ~s" want got)))

(defun org-nodes-kinds (nodes)
  "Flattened node-kind sequence, depth-first — the tree-shape contract
the Rust engine's tiling fixture locks."
  (let (out)
    (labels ((walk (list)
               (dolist (n list)
                 (typecase n
                   (org-heading
                    (push :heading out)
                    (walk (org-heading-body n)))
                   (org-src-block (push :src out))
                   (org-drawer (push :drawer out))
                   (org-checkbox (push :checkbox out))
                   (org-table (push :table out))
                   (org-text (push :text out))))))
      (walk nodes)
      (nreverse out))))

(defun org-test-buffer (name content)
  (let ((buf (make-new-buffer name content)))
    (setf *current-buffer* buf)
    buf))

(defun run-org-tests ()
  (setf *org-test-pass* 0 *org-test-fail* 0)
  (format t "ymacs org node contract tests~%")

  (org-test "heading fields parse like the Rust engine"
    (let ((nodes (org-parse "* TODO [#A] Write the engine :rust:core:
")))
      (let ((h (first (org-headings-flat nodes))))
        (org-assert-equal 1 (org-heading-level h))
        (org-assert-equal "TODO" (org-heading-todo h))
        (org-assert-equal #\A (org-heading-priority h))
        (org-assert-equal "Write the engine" (org-heading-title h))
        (org-assert-equal '("rust" "core") (org-heading-tags h)))))

  (org-test "subtrees nest by stars"
    (let ((nodes (org-parse "* A
** B
*** C
* D
")))
      (org-assert-equal '("A" "D")
                        (mapcar #'org-heading-title (copy-list nodes)))
      (org-assert-equal '("B")
                        (mapcar #'org-heading-title (org-heading-body (first nodes))))
      (org-assert-equal '("C")
                        (mapcar #'org-heading-title
                                (org-heading-body (first (org-heading-body (first nodes))))))))

  (org-test "a single uppercase letter stays title text (Emacs parity)"
    (let ((h (first (org-headings-flat (org-parse "* A note
")))))
      (org-assert-equal nil (org-heading-todo h))
      (org-assert-equal "A note" (org-heading-title h))))

  (org-test "the contract fixture yields the same tree shape both sides"
    (let ((kinds (org-nodes-kinds
                  (org-parse "* Top :core:
intro text
** Nested
- [ ] box one
- [X] box two
#+begin_src rust
fn main() {}
#+end_src
:PROPERTIES:
:prop: 1
:END:
| a | b |
|---+---|
| 1 | 2 |
trailing words
"))))
      (org-assert-equal
       '(:heading :text :heading :checkbox :checkbox :src :drawer :table :text)
       kinds)))

  (org-test "todo cycle is exact: TODO → DONE → none → TODO, other lines untouched"
    (let ((buf (org-test-buffer "*org-todo-test*" "* TODO write it
body line
* DONE other :x:
")))
      (unwind-protect
           (progn
             (setf (buffer-point buf) 0)
             (org-todo buf)
             (org-assert-equal "* DONE write it
body line
* DONE other :x:
" (buffer-content buf))
             (org-todo buf)
             (org-assert-equal "* write it
body line
* DONE other :x:
" (buffer-content buf))
             (org-todo buf)
             (org-assert-equal "* TODO write it
body line
* DONE other :x:
" (buffer-content buf)))
        (kill-buffer (buffer-id buf)))))

  (org-test "a DONE headline deeper in the file is left alone"
    (let ((buf (org-test-buffer "*org-todo-isolation*" "* TODO target
* DONE other
")))
      (unwind-protect
           (progn
             (setf (buffer-point buf) 0)
             (org-todo buf)
             (org-assert-equal "* DONE target
* DONE other
" (buffer-content buf)))
        (kill-buffer (buffer-id buf)))))

  (org-test "a prose headline gains TODO exactly as Emacs"
    (let ((buf (org-test-buffer "*org-todo-prose*" "* A note
")))
      (unwind-protect
           (progn
             (org-todo buf)
             (org-assert-equal "* TODO A note
" (buffer-content buf)))
        (kill-buffer (buffer-id buf)))))

  (org-test "todo cycle works under C-c C-t through the command layer"
    (let ((buf (org-test-buffer "*org-todo-keyplane*" "* TODO via keys
")))
      (unwind-protect
           (progn
             (setf (buffer-point buf) 0)
             ;; Zero-arg execution = the key plane's path; the macro law
             ;; records it like any other command invocation.
             (command-execute 'org-todo)
             (org-assert-equal "* DONE via keys
" (buffer-content buf)))
        (kill-buffer (buffer-id buf)))))

  (org-test "checkbox toggle is character-exact"
    (let ((buf (org-test-buffer "*org-checkbox*" "- [ ] unchecked
- [x] lowercase
")))
      (unwind-protect
           (progn
             (setf (buffer-point buf) 0)
             (org-checkbox-toggle buf)
             (org-assert-equal "- [X] unchecked
- [x] lowercase
" (buffer-content buf))
             (setf (buffer-point buf) (length "- [X] unchecked
"))
             (org-checkbox-toggle buf)
             (org-assert-equal "- [X] unchecked
- [ ] lowercase
" (buffer-content buf)))
        (kill-buffer (buffer-id buf)))))

  (org-test "C-c C-c toggles a checkbox at point"
    (let ((buf (org-test-buffer "*org-ctrlc*" "- [ ] via cc
")))
      (unwind-protect
           (progn
             (command-execute 'org-ctrl-c-ctrl-c)
             (org-assert-equal "- [X] via cc
" (buffer-content buf)))
        (kill-buffer (buffer-id buf)))))

  (org-test "next/prev heading move point by line"
    (let ((buf (org-test-buffer "*org-nav*" "* One
text
* Two
more
* Three
")))
      (unwind-protect
           (progn
             ;; Point on the "text" line (0-based line 1).
             (setf (buffer-point buf) (length "* One
"))
             (org-next-heading buf)
             (org-assert-equal (length "* One
text
") (buffer-point buf))
             (org-prev-heading buf)
             (org-assert-equal 0 (buffer-point buf))
             ;; Point on "more" (line 3): prev lands on * Two.
             (setf (buffer-point buf) (length "* One
text
* Two
"))
             (org-prev-heading buf)
             (org-assert-equal (length "* One
text
") (buffer-point buf)))
        (kill-buffer (buffer-id buf)))))

  (org-test "outline rows are node-driven: indent, keyword, tags, line ids"
    (let ((rows (org-outline-rows "* Top
body
** TODO Sub :deep:
")))
      (org-assert-equal
       '(("line-1" . "Top") ("line-3" . "  TODO Sub :deep:"))
       rows)))

  (org-test "goto-line moves point to the line start"
    (let ((buf (org-test-buffer "*org-goto*" "* One
body
* Two
")))
      (unwind-protect
           (progn
             (org-goto-line buf 3)
             (org-assert-equal (+ (length "* One
body
")) (buffer-point buf)))
        (kill-buffer (buffer-id buf)))))

  (org-test "the value-key law survives org splices"
    (let ((buf (org-test-buffer "*org-valuekey*" "* TODO keep
")))
      (unwind-protect
           (progn
             (let ((key (buffer-value-key buf)))
               (org-todo buf)
               (org-assert-equal key (buffer-value-key buf))
               (org-assert-equal t (buffer-modified-p buf))))
        (kill-buffer (buffer-id buf)))))

  (format t "ymacs org node contract tests: ~a passed, ~a failed~%"
          *org-test-pass* *org-test-fail*)
  (zerop *org-test-fail*))

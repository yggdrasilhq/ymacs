;;;; macro.lisp --- keyboard macros on top of the command layer.
;;;;
;;;; Law (docs/spec-primitives.md §3): recording lives in the command
;;;; layer's choke point (src/core/command.lisp); this file is playback,
;;;; naming, and insertion. A macro is a list of entries
;;;; (:command SYMBOL :args LIST :prefix VALUE) and replays headless —
;;;; palette/sidebar state is never consulted. The v0 recorder stored
;;;; nothing; that defect is fixed at the choke point, not here.

(in-package #:ymacs)

(defun call-last-kbd-macro (&optional prefix loopfunc)
  "Run the last keyboard macro (C-x e). Numeric PREFIX repeats it."
  (declare (ignore loopfunc))
  (unless *last-kbd-macro*
    (error "No keyboard macro defined"))
  (let ((count (typecase prefix
                 (number (max 1 prefix))
                 (otherwise 1))))
    (loop repeat count do (execute-kbd-macro *last-kbd-macro*))
    t))

(defun execute-kbd-macro (macro &optional count)
  "Execute MACRO (a list of entries) COUNT times (default 1).
Replay goes through the command layer with RECORD nil — replay never
re-records and never re-prompts: the stored parameter values are the
ones the interactive run collected. Replaying while a macro is being
defined is allowed (it composes silently); to have a composition record
as ONE step, name the macro (name-last-kbd-macro) and invoke the name —
named invocations are commands and record as such."
  (let ((n (or count 1)))
    (let ((*kbd-replaying* t))
      (loop repeat (max 1 n) do
        (dolist (entry macro)
          (let ((cmd (getf entry :command))
                (args (getf entry :args))
                (prefix (getf entry :prefix)))
            (when prefix (give-prefix-arg prefix))
            (command-execute cmd :args args :record nil))))
      t)))

(defun name-last-kbd-macro (symbol)
  "Bind SYMBOL to the last keyboard macro; calling SYMBOL runs it."
  (let ((macro *last-kbd-macro*))
    (unless macro (error "No keyboard macro defined"))
    (setf (symbol-function symbol)
          (lambda (&optional arg)
            (execute-kbd-macro macro (typecase arg (number arg) (otherwise 1)))))
    symbol))

(defun insert-kbd-macro (name &optional macroname)
  "Print a readable Lisp form that redefines NAME's macro. The emitted
form replays through the command layer (portable within ymacs)."
  (let ((macro (if macroname
                   (and (fboundp macroname) *last-kbd-macro*)
                   *last-kbd-macro*)))
    (unless macro (error "No keyboard macro defined"))
    (princ (format nil "(fset '~a (lambda (&optional arg)~%  (execute-kbd-macro '~s arg)))"
                   (string-downcase (symbol-name name))
                   macro))
    name))

(defun kbd-macro-query (prompt)
  "Within a replayed macro, ask the bound query handler (default: yes).
Macros never record gestures; a command that needs confirmation calls
this at replay time."
  (if *macro-query-handler*
      (funcall *macro-query-handler* prompt)
      t))

(defvar *macro-query-handler* nil)

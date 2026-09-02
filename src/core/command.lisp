;;;; command.lisp --- the command layer: named commands, interactive
;;;; specs, prefix arguments, M-x, and macro recording at command
;;;; granularity.
;;;;
;;;; Law (docs/spec-primitives.md §3): EVERY command execution funnels
;;;; through COMMAND-EXECUTE. The recorder hooks this one choke point, so
;;;; keyboard macros capture command invocations with their arguments —
;;;; never palette gestures, sidebar clicks, or focus changes. A recorded
;;;; macro replays identically headless with no surfaces at all.

(in-package #:ymacs)

;;; --- Prefix argument ------------------------------------------------------

(defvar *prefix-arg* nil "Current raw prefix argument, or nil.")
(defvar *prefix-arg-given* nil "T when a prefix argument was supplied.")

(defun give-prefix-arg (value)
  (setf *prefix-arg* value *prefix-arg-given* t))

(defun reset-prefix-arg ()
  (setf *prefix-arg* nil *prefix-arg-given* nil))

;;; --- Interactive specs ----------------------------------------------------
;;;
;;; A command's spec is the argument of its (interactive ...) form: either
;;; a string of parameter codes (Emacs-style subset) or a Lisp form.
;;; Each newline-separated line of a string spec is one parameter: the
;;; first character is the CODE, the rest is its prompt. Supported codes:
;;;   P  raw prefix argument      p  prefix as number (default 1)
;;;   s  string                   S  non-empty string
;;;   f  file name                b  buffer name
;;;   n  number                   r  region (point mark) — two values
;;;   c  character
;;; Any other code consumes one caller-supplied value.
;;;
;;; SUPPLIED ARGS WIN: a caller (palette, key plane, macro replay,
;;; headless verb) that supplies ARGS owns the parameter values in
;;; order — the spec computes only what the caller did not supply, and
;;; prompts are never re-evaluated. That is what makes replay work
;;; headless.

(defvar *command-interactive-specs* (make-hash-table :test 'eq))

(defun declare-interactive (symbol spec)
  "Register SPEC as the interactive spec of command SYMBOL."
  (setf (gethash symbol *command-interactive-specs*) spec)
  symbol)

(define-condition missing-interactive-args (error)
  ((command :initarg :command :reader missing-interactive-args-command))
  (:report (lambda (c s)
             (format s "~a requires interactive arguments (palette or caller must supply them)"
                     (missing-interactive-args-command c)))))

(defmacro defcommand (name args &optional docstring &body body)
  "Define a command NAME(ARGS) and register its (interactive ...) spec.
Mirrors Emacs shape: an optional docstring, then the (interactive ...)
form at the head of BODY — both stripped from the function body."
  (let* ((has-doc (stringp docstring))
         (real-body (if has-doc body (cons docstring body)))
         (spec nil))
    (when (and (consp (first real-body)) (eq (caar real-body) 'interactive))
      (setf spec (cdar real-body)
            real-body (rest real-body)))
    (cond
      ((null spec)
       `(progn
          (defun ,name ,args ,@(when has-doc (list docstring)) ,@real-body)
          ',name))
      (t
       (let ((normalized (if (= (length spec) 1) (first spec) spec)))
         `(progn
            (defun ,name ,args ,@(when has-doc (list docstring)) ,@real-body)
            (declare-interactive ',name ',normalized)
            ',name))))))

;;; --- Macro recording state (owned by the choke point) ---------------------

(defvar *macro-recording* nil "T while defining a keyboard macro.")
(defvar *macro-record-rev* nil "Recorded entries, most recent first.")
(defvar *last-kbd-macro* nil "Last completed macro: list of entries.")
(defvar *kbd-macro-ring* nil)
(defvar *kbd-macro-ring-max* 10)
(defvar *kbd-replaying* nil "T inside execute-kbd-macro: failures skip, never open UI.")

;; Entry shape: (:command SYMBOL :args LIST :prefix VALUE)

(defun macro-record-entry (entry)
  (when *macro-recording*
    (push entry *macro-record-rev*)))

(defun start-kbd-macro (&optional append)
  "Begin recording (C-x (). Non-nil APPEND extends the last macro."
  (setf *macro-recording* t
        *macro-record-rev* (if (and append *last-kbd-macro*)
                               (reverse *last-kbd-macro*)
                               nil))
  (fire-probe :ymacs-macro :event "start" :append (and append t))
  t)

(defun end-kbd-macro (&optional arg)
  "Finish recording (C-x )); the macro becomes *last-kbd-macro*."
  (declare (ignore arg))
  (setf *macro-recording* nil)
  (setf *last-kbd-macro* (nreverse *macro-record-rev*)
        *macro-record-rev* nil)
  (when *last-kbd-macro*
    (push *last-kbd-macro* *kbd-macro-ring*)
    (when (> (length *kbd-macro-ring*) *kbd-macro-ring-max*)
      (setf *kbd-macro-ring* (subseq *kbd-macro-ring* 0 *kbd-macro-ring-max*))))
  (fire-probe :ymacs-macro :event "end" :steps (length *last-kbd-macro*))
  *last-kbd-macro*)

(defun cancel-kbd-macro ()
  "Discard the macro being defined (C-g during recording)."
  (when *macro-recording*
    (setf *macro-recording* nil *macro-record-rev* nil)
    (fire-probe :ymacs-macro :event "cancel")
    t))

;;; --- The choke point ------------------------------------------------------

(defun command-name (command)
  (cond
    ((symbolp command) command)
    ((functionp command) nil)
    (t (error "Not a command: ~a" command))))

(defun split-spec-lines (s)
  "Split an interactive spec string on newlines: each line is one
parameter — first character is the code, the rest is its prompt."
  (loop with start = 0
        for pos = (position #\Newline s :start start)
        collect (subseq s start (or pos (length s)))
        while pos
        do (setf start (1+ pos))))

(defun compute-interactive-values (command args)
  "Return the argument list for COMMAND. Supplied ARGS are consumed in
parameter order; codes with nothing supplied either compute (prefix,
region) or signal MISSING-INTERACTIVE-ARGS (a prompting parameter the
caller must supply — the palette, or the stored values of a macro)."
  (let ((spec (gethash command *command-interactive-specs*))
        (queue (copy-list args))
        (out nil))
    (labels ((consume ()
               (let ((v (first queue)))
                 (push v out)
                 (setf queue (rest queue))))
             (must-consume ()
               (if queue
                   (consume)
                   (error 'missing-interactive-args :command command))))
      (cond
        ;; Form spec: parameters must come supplied whole (never evaluate
        ;; prompts behind the caller's back).
        ((and (consp spec) (not (stringp spec)))
         (if args
             (dotimes (_ (length args)) (consume))
             (error 'missing-interactive-args :command command)))
        ((stringp spec)
         (loop for line in (split-spec-lines spec)
               when (plusp (length line))
                 do (let ((code (char line 0)))
                      (case code
                        (#\P
                         (if queue (consume) (push *prefix-arg* out)))
                        (#\p
                         (if queue
                             (consume)
                             (push (if *prefix-arg-given*
                                       (typecase *prefix-arg*
                                         (number *prefix-arg*)
                                         (otherwise 1))
                                       1)
                                   out)))
                        (#\r
                         (cond
                           ((>= (length queue) 2)
                            (consume) (consume))
                           (*current-buffer*
                            (push (buffer-mark *current-buffer*) out)
                            (push (buffer-point *current-buffer*) out))
                           (t
                            (error 'missing-interactive-args :command command))))
                        ((#\s #\S #\f #\F #\b #\B #\n #\e #\m #\c)
                         (must-consume))
                        (t
                         (unless (char= code #\*) ; "*" flag: no parameter
                           (must-consume)))))))))
    (nreverse out)))

(defun command-execute (command &key args (record t))
  "Execute COMMAND (symbol or function) through the single choke point.
ARGS, when supplied, are the interactive parameter values (palette, key
dispatch, or stored macro). RECORD nil suppresses macro recording — used
by replay. Every other call site in ymacs must go through here."
  (let* ((sym (command-name command))
         (fn (if sym (or (and sym (fboundp sym) (symbol-function sym)) command) command))
         (values (compute-interactive-values (or sym command) args)))
    (when (and record *macro-recording*
               (not (member sym '(start-kbd-macro end-kbd-macro cancel-kbd-macro))))
      (macro-record-entry (list :command (or sym fn) :args (copy-list values) :prefix *prefix-arg*)))
    (let ((result (apply fn values)))
      ;; The prefix is consumed by the command that read it; the one
      ;; command that CREATES a prefix must keep it.
      (unless (eq sym 'universal-argument)
        (reset-prefix-arg))
      result)))

(defun execute-extended-command (&optional prefix-arg command-name &rest supplied-args)
  "M-x. COMMAND-NAME is resolved in :ymacs; SUPPLIED-ARGS are the
interactive parameter values. The palette is a VIEW over this entry
point — it collects the name and parameter values, this function runs
the command through the choke point."
  (when prefix-arg (give-prefix-arg prefix-arg))
  (let* ((sym (and command-name (find-symbol (string-upcase command-name) :ymacs))))
    (unless (and sym (fboundp sym))
      (error "No command named ~a" command-name))
    (command-execute sym :args supplied-args)))

;;; --- Specs for the pre-existing basic commands ----------------------------

(declare-interactive 'find-file "fFind file: ")
(declare-interactive 'open-file-buffer "fFind file: ")
(declare-interactive 'switch-to-buffer "bBuffer name: ")
(declare-interactive 'save-buffer "")
(declare-interactive 'kill-buffer-command "bBuffer name: ")
(declare-interactive 'isearch-forward "")
(declare-interactive 'isearch-backward "")
(declare-interactive 'undo "")
(declare-interactive 'yank "P")
(declare-interactive 'keyboard-quit "")
(declare-interactive 'execute-extended-command "P
MCommand name: ")

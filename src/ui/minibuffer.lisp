;;;; minibuffer.lisp --- the command palette: the minibuffer state
;;;; machine that collects every interactive argument the command layer
;;;; asks for (docs/spec-primitives.md §3, spec-key-plane §3).
;;;;
;;;; Law: the palette is a VIEW. Its keys mutate THIS state machine and
;;;; are never recorded into macros; the final invocation goes through
;;;; command-execute with the collected values, which is what records —
;;;; and what replays headless. Prompting is generic: any command whose
;;;; spec needs a value the caller did not supply opens the palette,
;;;; which is exactly Emacs's `C-x C-f` -> "Find file: " behaviour.

(in-package #:ymacs)

(defvar *minibuffer-active* nil)
(defvar *minibuffer-prompt* "")
(defvar *minibuffer-input* "")
(defvar *minibuffer-candidates* nil "Filtered candidates, display order.")
(defvar *minibuffer-selected* 0 "Index into *minibuffer-candidates*.")
(defvar *minibuffer-history* nil)
(defvar *minibuffer-error* nil "Last refusal, rendered until the next key.")
(defvar *minibuffer-collection-base* nil "The unfiltered collection of the read in flight.")

;;; The read in flight. NIL command = choosing a command NAME (phase 1);
;;; a symbol = collecting that command's remaining prompting parameters.
(defvar *minibuffer-command* nil)
(defvar *minibuffer-remaining-prompts* nil "Unconsumed (code prompt) lines.")
(defvar *minibuffer-acc* nil "Collected parameter values, most recent first.")

(defparameter minibuffer-visible-max 8)

;;; --- Filtering (orderless-ish: every space-separated part matches) --------

(defun minibuffer-split-query (query)
  (remove "" (split-whitespace (string-upcase query)) :test #'string=))

(defun minibuffer-filter (query candidates)
  (let ((parts (minibuffer-split-query query)))
    (if (null parts)
        (copy-list candidates)
        (remove-if-not
         (lambda (cand)
           (let ((u (string-upcase cand)))
             (every (lambda (part) (search part u :test #'string=)) parts)))
         candidates))))

;;; --- Collections ------------------------------------------------------------

(defun minibuffer-command-names ()
  "Every command the layer knows: interactive specs plus bound symbols
that look like commands, sorted — the M-x collection."
  (let ((names (make-hash-table :test 'equal)))
    (maphash (lambda (sym _)
               (declare (ignore _))
               (when (fboundp sym)
                 (setf (gethash (string-downcase (symbol-name sym)) names) t)))
             *command-interactive-specs*)
    (sort (loop for name being the hash-keys of names collect name) #'string<)))

(defun minibuffer-buffer-names ()
  (mapcar #'buffer-name (list-all-buffers)))

(defun minibuffer-collection-for (code-char)
  (cond
    ((eql code-char #\b) (minibuffer-buffer-names))
    (t nil)))                            ; s/f/n/c/... are free text

(defun minibuffer-prompting-lines (spec)
  "The spec lines whose parameters must be collected from a user
(prefix and region codes compute at execute time)."
  (when (stringp spec)
    (loop for line in (split-spec-lines spec)
          when (and (plusp (length line))
                    (not (find (char line 0) "Ppr")))
            collect line)))

;;; --- State transitions --------------------------------------------------------

(defun minibuffer-start (prompt collection)
  (setf *minibuffer-active* t
        *minibuffer-prompt* prompt
        *minibuffer-input* ""
        *minibuffer-error* nil
        *minibuffer-collection-base* collection
        *minibuffer-candidates* (minibuffer-filter "" collection)
        *minibuffer-selected* 0)
  (fire-probe :ymacs-minibuffer :prompt prompt)
  nil)

(defun minibuffer-start-for-command (command)
  "Collect COMMAND's prompting parameters (the generic palette entry:
C-x C-f lands here with find-file's \"fFind file: \")."
  (let* ((sym (if (symbolp command) command nil))
         (spec (and sym (gethash sym *command-interactive-specs*)))
         (prompts (minibuffer-prompting-lines spec)))
    (setf *minibuffer-command* sym
          *minibuffer-remaining-prompts* (rest prompts)
          *minibuffer-acc* nil)
    (if prompts
        (minibuffer-start (subseq (first prompts) 1)
                          (minibuffer-collection-for (char (first prompts) 0)))
        (progn (minibuffer-finish)))))

(defun minibuffer-exit-state ()
  (setf *minibuffer-active* nil *minibuffer-input* "" *minibuffer-error* nil
        *minibuffer-command* nil *minibuffer-remaining-prompts* nil
        *minibuffer-acc* nil *minibuffer-candidates* nil *minibuffer-selected* 0))

(defun minibuffer-abort ()
  "C-g in the palette: leave everything untouched."
  (minibuffer-exit-state)
  (reset-key-sequence)
  (fire-probe :ymacs-minibuffer :event "abort")
  nil)

(defun minibuffer-current-input ()
  (if (and *minibuffer-candidates*
           (>= *minibuffer-selected* 0)
           (< *minibuffer-selected* (length *minibuffer-candidates*)))
      (nth *minibuffer-selected* *minibuffer-candidates*)
      *minibuffer-input*))

(defun minibuffer-refilter ()
  (setf *minibuffer-candidates*
        (minibuffer-filter *minibuffer-input* *minibuffer-collection-base*)
        *minibuffer-selected* 0))

(defun minibuffer-finish ()
  "All parameters collected: run the command through the choke point
with exactly the collected values — the record the macro keeps."
  (let ((sym *minibuffer-command*)
        (values (reverse *minibuffer-acc*)))
    (minibuffer-exit-state)
    (command-execute sym :args values)))

(defun minibuffer-accept ()
  "RET: accept the current selection/input and advance."
  (let ((value (minibuffer-current-input)))
    (push value *minibuffer-history*)
    (cond
      ;; Phase 1 done: the value names a command.
      ((null *minibuffer-command*)
       (let* ((sym (find-symbol (string-upcase value) :ymacs)))
         (cond
           ((and sym (fboundp sym))
            (let* ((spec (gethash sym *command-interactive-specs*))
                   (prompts (minibuffer-prompting-lines spec)))
              (setf *minibuffer-command* sym
                    *minibuffer-remaining-prompts* (rest prompts))
              (if prompts
                  (let* ((line (first prompts)))
                    (minibuffer-start (subseq line 1)
                                      (minibuffer-collection-for (char line 0))))
                  (minibuffer-finish))))
           (t
            (setf *minibuffer-error* (format nil "No match: ~a" value))
            nil))))
      ;; Phase 2: the value is one parameter.
      (t
       (push value *minibuffer-acc*)
       (let ((rest *minibuffer-remaining-prompts*))
         (if rest
             (let ((line (first rest)))
               (setf *minibuffer-remaining-prompts* (rest rest))
               (minibuffer-start (subseq line 1)
                                 (minibuffer-collection-for (char line 0))))
             (minibuffer-finish)))))))

;;; --- Keys (the palette's own map; never recorded) -------------------------------

(defun minibuffer-handle-key (chord)
  "Handle CHORD inside the palette. Returns nil when the key was not a
palette key (the caller keeps its own reset semantics)."
  (setf *minibuffer-error* nil)
  (cond
    ((or (string= chord "RET") (string= chord "C-m"))
     (minibuffer-accept))
    ((or (string= chord "C-g") (string= chord "ESC"))
     (minibuffer-abort))
    ((or (string= chord "C-n") (string= chord "<down>"))
     (when *minibuffer-candidates*
       (setf *minibuffer-selected*
             (min (1- (length *minibuffer-candidates*))
                  (1+ *minibuffer-selected*)))))
    ((or (string= chord "C-p") (string= chord "<up>"))
     (setf *minibuffer-selected* (max 0 (1- *minibuffer-selected*))))
    ((or (string= chord "DEL") (string= chord "C-<backspace>"))
     (unless (string= *minibuffer-input* "")
       (setf *minibuffer-input* (subseq *minibuffer-input* 0 (1- (length *minibuffer-input*)))))
     (minibuffer-refilter))
    ((string= chord "TAB")
     ;; Complete to the selected candidate's text.
     (when *minibuffer-candidates*
       (setf *minibuffer-input* (minibuffer-current-input))
       (minibuffer-refilter)))
    ((= (length chord) 1)
     (setf *minibuffer-input* (concatenate 'string *minibuffer-input* chord))
     (minibuffer-refilter))
    (t nil))
  t)

;;; --- Render (the palette is window chrome drawn from the doc schema) ------------

(defun minibuffer-visible-candidates (&optional (max minibuffer-visible-max))
  (let ((rows (min (length *minibuffer-candidates*) max)))
    (loop for i below rows
          collect (list i (nth i *minibuffer-candidates*)))))

(defun minibuffer-schema-widgets ()
  "The palette widgets appended to the document schema while active."
  (when *minibuffer-active*
    (let* ((prompt (format nil "~a~@[  ~a~]" *minibuffer-prompt* *minibuffer-error*))
           (rows (minibuffer-visible-candidates)))
      `((("kind" . "section") ("text" . ,prompt))
        (("kind" . "search-box") ("id" . "minibuffer")
         ("placeholder" . ,*minibuffer-prompt*) ("value" . ,*minibuffer-input*)
         ("action" . "minibuffer-accept"))
        ,@(loop for (i cand) in rows
                collect `(("kind" . "list-row") ("id" . ,cand) ("title" . ,cand)
                          ("selected" . ,(= i *minibuffer-selected*))
                          ("row_action" . "minibuffer-select")))))))

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
;;;;
;;;; The view is the yggui COMMAND PALETTE component, rendered by the
;;;; host as an overlay surface (spec-primitives S3 — a window
;;;; component, never document widgets): this module declares the
;;;; palette block of the document schema (query, prompt, candidates,
;;;; selection) and answers the palette's mouse actions. The keyboard
;;;; keeps flowing through the key plane as chords — TAB, C-n/C-p, C-g
;;;; and typing stay Emacs keys; the component's own arrows/RET/ESC
;;;; arrive as palette-move/palette-accept/palette-dismiss actions.

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

(defparameter minibuffer-visible-max 12)

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

(defun minibuffer-strict-p ()
  "T when the read in flight refuses non-candidates: phase 1 of M-x,
where Emacs itself answers [No match] for a non-command. Everything
else — file names, buffer names, free text — accepts what was typed
(C-x b foo RET creates foo), so the palette always offers the raw
input as a candidate there."
  (null *minibuffer-command*))

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
  ;; The palette surface just entered (or left) the document schema; the
  ;; GUI is a thin client that refetches /pane/doc only when this stamp
  ;; moves. Without the bump the payload changes and the palette stays
  ;; invisible (found live in the shadow 2026-09-04).
  (bump-document-version)
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
  (bump-document-version)
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
        *minibuffer-selected* 0)
  ;; A lenient read accepts what was typed even when it matches nothing
  ;; (C-x b foo RET creates foo). The raw input rides at the END of the
  ;; candidate list, so every selection/accept path — C-n into it, RET on
  ;; it, a click — is the ordinary machinery; phase 1 (M-x) is strict and
  ;; never gets the row, exactly as Emacs refuses a non-command.
  (when (and (not (minibuffer-strict-p))
             (plusp (length *minibuffer-input*))
             (not (member *minibuffer-input* *minibuffer-candidates*
                          :test #'string=)))
    (setf *minibuffer-candidates*
          (append *minibuffer-candidates* (list *minibuffer-input*)))))

(defun minibuffer-finish ()
  "All parameters collected: run the command through the choke point
with exactly the collected values — the record the macro keeps."
  (let ((sym *minibuffer-command*)
        (values (reverse *minibuffer-acc*)))
    (minibuffer-exit-state)
    (bump-document-version)
    (fire-probe :ymacs-minibuffer :event "accept" :prompt (prin1-to-string sym))
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
  ;; Candidates/selection/input all live in the schema the GUI refetches
  ;; on the version stamp — every handled chord moves it.
  (bump-document-version)
  t)

;;; --- Palette actions (the mouse half of the surface) -----------------------------

(defun minibuffer-palette-move (dir)
  "A palette-move action: DIR is next/previous/first/last. The
selection WRAPS both ways, like the host's palette_index_after — a
launcher you steer by feel must not stop dead at an edge."
  (let ((len (length *minibuffer-candidates*)))
    (when (plusp len)
      (let ((sel *minibuffer-selected*))
        (setf *minibuffer-selected*
              (cond
                ((string= dir "next") (if (= sel (1- len)) 0 (1+ sel)))
                ((string= dir "previous") (if (zerop sel) (1- len) (1- sel)))
                ((string= dir "first") 0)
                ((string= dir "last") (1- len))
                (t sel)))))))

(defun minibuffer-palette-accept-id (id)
  "A palette-accept action: ID is a clicked row's id, or the
component's Enter carrying the selected row's id. The id is accepted BY
NAME — refilter against it, select it, accept — so a stale row (the
list moved under the click) reads exactly like typing the full name,
which is how M-x itself accepts a complete command name."
  (when (and *minibuffer-active* (plusp (length id)))
    (setf *minibuffer-input* id)
    (minibuffer-refilter)
    (let ((pos (position id *minibuffer-candidates* :test #'string=)))
      (when pos (setf *minibuffer-selected* pos)))
    (minibuffer-accept))
  nil)

;;; --- Render (the palette surface block of the document schema) -------------------

(defun minibuffer-visible-window (&optional (max minibuffer-visible-max))
  "The GLOBAL indices of the candidate window the surface shows: a
sliding frame around the selection, so the selected row is always on
screen (the palette component scrolls its results box but does not
follow the selection). Ids stay absolute, so acceptance is unambiguous."
  (let* ((len (length *minibuffer-candidates*))
         (rows (min len max)))
    (when (plusp rows)
      (let ((start (max 0 (min (- *minibuffer-selected* (floor rows 2))
                               (- len rows)))))
        (loop for i below rows collect (+ start i))))))

(defun minibuffer-schema-palette ()
  "The palette surface block of the document schema, or NIL while no
read is in flight (the key is then OMITTED — the host rejects nulls).
`selected` indexes the ITEMS vector, which is the visible window."
  (when *minibuffer-active*
    (let* ((window (minibuffer-visible-window))
           (items (loop for i in window
                        collect `(("id" . ,(nth i *minibuffer-candidates*))
                                  ("label" . ,(nth i *minibuffer-candidates*))))))
      `(("query" . ,*minibuffer-input*)
        ("prompt" . ,(string-right-trim '(#\Space) *minibuffer-prompt*))
        ("selected" . ,(if window
                           (position *minibuffer-selected* window :test #'=)
                           0))
        ("items" . ,(apply #'vector (or items nil)))
        ;; The empty-list voice: the last refusal when there is one
        ;; (phase 1 RET on a non-command — Emacs's [No match]), the
        ;; host's own "No matches" otherwise.
        ("empty" . ,(or *minibuffer-error* ""))))))

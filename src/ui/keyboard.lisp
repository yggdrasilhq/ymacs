;;;; keyboard.lisp --- the key plane: chord events from the yggterm
;;;; key-capture channel (docs/spec-key-plane.md) into the command layer.
;;;;
;;;; One chord per event ("C-x", "C-f", "h", "<up>"); SEQUENCES are the
;;;; app's business: this file accumulates the pending sequence, resolves
;;;; it against the active keymaps, and funnels every execution through
;;;; command-execute — so key-driven invocations record into keyboard
;;;; macros exactly like M-x ones (the macro law, spec-primitives §3).

(in-package #:ymacs)

(defvar *key-sequence* nil "Pending key-sequence chords, most recent first.")

(defun key-sequence-string ()
  "The pending sequence in display order, or \"\"."
  (if *key-sequence*
      (format nil "~{~a~^ ~}" (reverse *key-sequence*))
      ""))

(defun reset-key-sequence ()
  (setf *key-sequence* nil))

;;; --- Keymap resolution -----------------------------------------------------

(defun keyboard-active-mode-map ()
  (and *current-buffer*
       (gethash (buffer-major-mode *current-buffer*) *local-maps*)))

(defun keyboard-lookup-exact (seq)
  (let ((mode-map (keyboard-active-mode-map)))
    (or (and mode-map (elisp/lookup-key mode-map seq))
        (elisp/lookup-key *global-map* seq))))

(defun keyboard-prefix-p (seq)
  "Does any binding in an active map start with SEQ as a prefix chord?
A binding \"C-x C-f\" makes \"C-x\" a prefix; the separator is one space."
  (flet ((prefix-in (map)
           (loop for k being the hash-keys of (elisp-keymap-bindings map)
                 thereis (and (> (length k) (length seq))
                              (string= k seq :end1 (length seq))
                              (char= (char k (length seq)) #\Space)))))
    (let ((mode-map (keyboard-active-mode-map)))
      (or (and mode-map (prefix-in mode-map))
          (prefix-in *global-map*)))))

;;; --- Execution --------------------------------------------------------------

(defun keyboard-execute-binding (cmd)
  "Execute a keymap binding through the command layer. A binding to an
unbound symbol, or one whose parameters need a prompt the key plane
cannot ask (M-x without the palette — the palette component is its
collector), refuses quietly: a dead key must never kill the reply."
  (handler-case
      (typecase cmd
        (symbol (if (fboundp cmd)
                    (progn (command-execute cmd) t)
                    nil))
        (function (funcall cmd) t)
        (otherwise nil))
    (missing-interactive-args () nil)
    (error () nil)))

;;; --- Point helpers ------------------------------------------------------------

(defun keyboard-line-bounds (content pt)
  "Values: this line's start and its end (exclusive, before the newline),
for point PT clamped into CONTENT."
  (let ((pt (max 0 (min pt (length content)))))
    (values (1+ (or (position #\Newline content :end pt :from-end t) -1))
            (or (position #\Newline content :start pt) (length content)))))

(defun keyboard-clamp-point (pt)
  (max 0 (min pt (length (buffer-content *current-buffer*)))))

;;; --- Movement (the v0 point commands) ----------------------------------------

(defcommand next-line (&optional (count 1))
  "Move point DOWN COUNT lines, preserving the column."
  (interactive "p")
  (when *current-buffer*
    (let ((content (buffer-content *current-buffer*))
          (pt (buffer-point *current-buffer*))
          (n (max 1 count)))
      (multiple-value-bind (bol eol) (keyboard-line-bounds content pt)
        (let ((col (- pt bol))
              (target-bol bol))
          (dotimes (_ n)
            (let ((this-eol (or (position #\Newline content :start target-bol)
                                (length content))))
              (if (>= this-eol (length content))
                  (setf target-bol (length content))
                  (setf target-bol (1+ this-eol)))))
          (let ((line-end (or (position #\Newline content :start target-bol)
                              (length content))))
            (declare (ignore eol))
            (setf (buffer-point *current-buffer*)
                  (min line-end (+ target-bol col)))))))))

(defcommand previous-line (&optional (count 1))
  "Move point UP COUNT lines, preserving the column."
  (interactive "p")
  (when *current-buffer*
    (let ((content (buffer-content *current-buffer*))
          (pt (buffer-point *current-buffer*))
          (n (max 1 count)))
      (multiple-value-bind (bol eol) (keyboard-line-bounds content pt)
        (declare (ignore eol))
        (let ((col (- pt bol))
              (target-bol bol))
          (dotimes (_ n)
            (unless (zerop target-bol)
              (let ((prev-eol (1- target-bol)))
                (setf target-bol
                      (1+ (or (position #\Newline content
                                        :end prev-eol :from-end t)
                              -1))))))
          (let ((line-end (or (position #\Newline content :start target-bol)
                              (length content))))
            (setf (buffer-point *current-buffer*)
                  (min line-end (+ target-bol col)))))))))

(defcommand forward-char (&optional (count 1))
  "Move point RIGHT COUNT characters."
  (interactive "p")
  (when *current-buffer*
    (setf (buffer-point *current-buffer*)
          (keyboard-clamp-point (+ (buffer-point *current-buffer*) count)))))

(defcommand backward-char (&optional (count 1))
  "Move point LEFT COUNT characters."
  (interactive "p")
  (when *current-buffer*
    (setf (buffer-point *current-buffer*)
          (keyboard-clamp-point (- (buffer-point *current-buffer*) count)))))

(defcommand move-beginning-of-line (&optional (count 1))
  "Move point to the beginning of the current line."
  (interactive "p")
  (declare (ignore count))
  (when *current-buffer*
    (multiple-value-bind (bol _)
        (keyboard-line-bounds (buffer-content *current-buffer*)
                              (buffer-point *current-buffer*))
      (declare (ignore _))
      (setf (buffer-point *current-buffer*) bol))))

(defcommand move-end-of-line (&optional (count 1))
  "Move point to the end of the current line."
  (interactive "p")
  (declare (ignore count))
  (when *current-buffer*
    (multiple-value-bind (_ eol)
        (keyboard-line-bounds (buffer-content *current-buffer*)
                              (buffer-point *current-buffer*))
      (declare (ignore _))
      (setf (buffer-point *current-buffer*) eol))))

;;; --- Self-insert -------------------------------------------------------------

(defun keyboard-printable-char (chord)
  "The character CHORD self-inserts, or NIL (specials and modifier
chords never self-insert)."
  (cond
    ((string= chord "SPC") #\Space)
    ((= (length chord) 1)
     (let ((ch (char chord 0)))
       (and (graphic-char-p ch) ch)))
    (t nil)))

(defcommand self-insert-command (&optional (count 1) ch)
  "Insert the typed character COUNT times at point."
  (interactive "p
c")
  (when (and *current-buffer* ch)
    (buffer-insert *current-buffer*
                   (buffer-point *current-buffer*)
                   (make-string count :initial-element ch))
    (setf (buffer-point *current-buffer*)
          (keyboard-clamp-point (+ (buffer-point *current-buffer*) count)))
    t))

;;; --- The dispatcher -------------------------------------------------------------

(defun ymacs-handle-key (chord)
  "Handle one key event. Returns the action-reply alist: ok + the fresh
document schema, so one loopback round trip renders the keystroke."
  (if (or (null chord) (string= chord ""))
      (key-plane-reply)
      (let ((seq (if *key-sequence*
                     (format nil "~a ~a" (key-sequence-string) chord)
                     (copy-seq chord))))
        (cond
          ;; Exact binding — mode map, then global.
          ((keyboard-lookup-exact seq)
           (reset-key-sequence)
           (keyboard-execute-binding (keyboard-lookup-exact seq))
           (key-plane-reply))
          ;; A longer binding continues with this chord — stay pending.
          ((keyboard-prefix-p seq)
           (push chord *key-sequence*)
           (key-plane-reply))
          ;; Printable character with no binding: self-insert.
          ((and (null *key-sequence*) (keyboard-printable-char chord))
           (reset-key-sequence)
           (command-execute 'self-insert-command
                            :args (list 1 (keyboard-printable-char chord)))
           (key-plane-reply))
          ;; Undefined: reset, render anyway.
          (t
           (reset-key-sequence)
           (key-plane-reply))))))

(defun key-plane-reply ()
  `(("ok" . t)
    ("schema" . ,(document-schema))
    ("document_version" . ,(document-version))))

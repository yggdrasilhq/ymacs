;;;; startup.lisp --- The GNU-Emacs-style startup screen (*GNU Ymacs*).
;;;;
;;;; Owner request 2026-09-10 (board ACK-83f10bee0f): a start screen
;;;; just like GNU Emacs, from which The Ymacs Manual opens. Interface
;;;; law: the keyset is GNU's splash — TAB/S-TAB cycle the links, RET
;;;; activates the link on the cursor line, q leaves for the next real
;;;; buffer — and C-h r reads the manual from anywhere (global). The
;;;; screen is a VIEW buffer (never durable), the same law as Info's.
;;;; Divergence from GNU (splash on every plain start) is ledger entry
;;;; D10: ymacs's daemon is perpetual, so the screen shows on FRESH
;;;; daemon boots only; a restored session is left untouched.

(in-package #:ymacs)

(defvar *splash-buffer-name* "*GNU Ymacs*"
  "The startup screen buffer (GNU's is *GNU Emacs*).")

(defvar *splash-buffers* (make-hash-table :test 'equal)
  "Buffer id -> t for startup screens (view buffers, never durable).")

(defvar *splash-links* (make-hash-table :test 'equal)
  "Buffer id -> alist of (LABEL . COMMAND), screen order. A link line
reads `* LABEL` in the buffer text; activation matches the cursor
line's label against this table.")

(defun ymacs-splash-text ()
  "The startup screen text. Pure ASCII — the renderer carries no
box-drawing face today — so the logo is a hand-drawn Y. Flush-left
continuation lines are the STRING, not style."
  (format nil
" \\       /
  \\     /       Ymacs ~a
   \\   /        the Emacs-compatible editor on libyggterm
    \\ /
     Y          Copyright (C) 2026 Avikalpa Kundu and the ymacs authors
     |          Ymacs comes with ABSOLUTELY NO WARRANTY; it is free
    / \\         software, and you are welcome to redistribute it
   /   \\        under the GNU GPL version 3 or later.

 * The Ymacs Manual      Read it in Info: RET on this line, or C-h r anywhere
 * Visit New File        C-x C-f

 Point moves with the arrows; TAB walks the links above.
 Useful keys: C-x C-f find a file | M-x run a command | C-x b switch buffers
 Divergences from GNU Emacs: docs/emacs-manual/divergences.org"
          *ymacs-version*))

(defun splash-buffer-p (buf)
  (and buf (gethash (buffer-id buf) *splash-buffers*)))

(defun ymacs-splash-buffer ()
  "The live startup-screen buffer, or NIL."
  (find-if (lambda (b) (string= (buffer-name b) *splash-buffer-name*))
           (list-all-buffers)))

(defun ymacs-splash-ensure ()
  "Create-once the startup screen and return its buffer. A view
buffer: tagged non-durable and the store row its creation wrote is
dropped (the Info view law)."
  (let ((buf (or (ymacs-splash-buffer)
                 (make-new-buffer *splash-buffer-name* (ymacs-splash-text)))))
    (setf (gethash (buffer-id buf) *splash-buffers*) t)
    (setf (gethash (buffer-id buf) *splash-links*)
          (list (cons "The Ymacs Manual" 'info)
                (cons "Visit New File" 'find-file)))
    (set-buffer-major-mode buf "startup-mode")
    (setf (buffer-point buf) 1)
    (when *store* (ignore-errors (store-delete-buffer (buffer-id buf))))
    buf))

;;; --- Lines and links -------------------------------------------------------

(defun splash-line-index (buf)
  "The 1-based line the buffer's point sits on."
  (let ((content (buffer-content buf))
        (pt (max 0 (min (buffer-point buf) (length (buffer-content buf))))))
    (1+ (count #\Newline content :end pt))))

(defun splash-line-text (buf idx)
  (nth (1- idx) (split-lines (buffer-content buf))))

(defun splash-line-start (buf idx)
  "The 1-based point of line IDX's first character."
  (let ((content (buffer-content buf))
        (point 1))
    (loop for i from 1
          while (< i idx)
          do (let ((nl (position #\Newline content :start (1- point))))
               (if nl (setf point (+ nl 2)) (return point))))
    point))

(defun splash-link-lines (buf)
  "The 1-based line numbers that hold a link (`* LABEL')."
  (loop for line in (split-lines (buffer-content buf))
        for i from 1
        when (splash-link-at-line buf line)
          collect i))

(defun splash-link-at-line (buf line)
  "The (LABEL . COMMAND) entry whose label the trimmed `* LABEL' line
carries, or NIL. The label must be in the buffer's link table, so
`* Menu:'-style non-links never match. PREFIX TEST: string= compares
equal-length regions, so the LONG string's :end2 bounds the compare —
bounding the label with :end1 never matches (cl-lisp gotcha)."
  (let ((trimmed (string-left-trim " " line)))
    (when (and (>= (length trimmed) 2) (string= trimmed "* " :end1 2))
      (let ((rest (string-trim " " (subseq trimmed 2))))
        (find-if (lambda (entry)
                   (let ((label (car entry)))
                     (and (>= (length rest) (length label))
                          (string= label rest :end2 (length label)))))
                 (gethash (buffer-id buf) *splash-links*))))))

(defun splash-link-at (buf)
  "The link entry under the buffer's point, or NIL when the cursor
line is not a link line."
  (splash-link-at-line buf (splash-line-text buf (splash-line-index buf))))

;;; --- Commands ---------------------------------------------------------------

(defcommand startup-next-link ()
  "Startup screen TAB — point to the next link, wrapping."
  (interactive)
  (let ((buf *current-buffer*))
    (if (splash-buffer-p buf)
        (let* ((links (splash-link-lines buf))
               (cur (splash-line-index buf))
               (next (or (find-if (lambda (i) (> i cur)) links)
                         (first links))))
          (if next
              (progn (setf (buffer-point buf) (splash-line-start buf next))
                     (bump-document-version)
                     (message "%s" (string-trim
                                    " "
                                    (splash-line-text buf next))))
              (message "No links on the startup screen")))
        (message "Not on the startup screen"))))

(defcommand startup-previous-link ()
  "Startup screen S-TAB — point to the previous link, wrapping."
  (interactive)
  (let ((buf *current-buffer*))
    (if (splash-buffer-p buf)
        (let* ((links (splash-link-lines buf))
               (cur (splash-line-index buf))
               (prev (or (find-if (lambda (i) (< i cur)) links :from-end t)
                         (first (last links)))))
          (if prev
              (progn (setf (buffer-point buf) (splash-line-start buf prev))
                     (bump-document-version)
                     (message "%s" (string-trim
                                    " "
                                    (splash-line-text buf prev))))
              (message "No links on the startup screen")))
        (message "Not on the startup screen"))))

(defcommand startup-activate-link ()
  "Startup screen RET — run the command of the link on the cursor
line, through the shared M-x-law entry (a prompting command opens the
palette, C-x C-f-style)."
  (interactive)
  (let* ((buf *current-buffer*)
         (link (and buf (splash-buffer-p buf) (splash-link-at buf))))
    (if link
        (command-execute-or-prompt (cdr link))
        (message "No link on this line"))))

(defcommand startup-quit ()
  "Startup screen q — kill the screen and select the next real
buffer (the Info q law)."
  (interactive)
  (let ((buf *current-buffer*))
    (if (splash-buffer-p buf)
        (let ((next (loop for b in (list-all-buffers)
                          unless (or (splash-buffer-p b)
                                     (string= (buffer-name b) (buffer-name buf)))
                          return b)))
          (remhash (buffer-id buf) *splash-buffers*)
          (remhash (buffer-id buf) *splash-links*)
          (kill-buffer-by-id (buffer-id buf))
          (when next
            (setf *current-buffer* next)
            (bump-document-version)
            (message "Killed %s" (buffer-name buf))))
        (message "Not on the startup screen"))))

;;; --- Mode ---------------------------------------------------------------------

(defun startup-set-keybindings ()
  (local-set-key "startup-mode" "TAB" 'startup-next-link)
  (local-set-key "startup-mode" "S-TAB" 'startup-previous-link)
  (local-set-key "startup-mode" "RET" 'startup-activate-link)
  (local-set-key "startup-mode" "q" 'startup-quit)
  t)

(define-major-mode "startup-mode"
  :doc "Startup screen mode — the GNU-Emacs-style welcome: TAB/S-TAB
walk the links, RET activates the link on the cursor line, q leaves
for the next real buffer. C-h r reads The Ymacs Manual from anywhere."
  :hook (lambda (buf)
          (declare (ignore buf))
          (startup-set-keybindings)))

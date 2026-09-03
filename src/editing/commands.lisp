;;;; commands.lisp --- the interactive commands the default keymap binds
;;;;
;;;; The keymap has bound these names since the step-3 wave; until now
;;;; most did not exist, and every keypress resolved to a swallowed
;;;; error (found by pixel verification, 2026-09-04). Each command here
;;;; is a real M-x citizen: defined through defcommand, executed only
;;;; through command-execute, reported through the echo area.

(in-package #:ymacs)

;;; --- Files ------------------------------------------------------------------

(defcommand find-file (filename)
  "Open FILENAME into a buffer and select it."
  (interactive "fFind file: ")
  (let ((buf (open-file-buffer filename)))
    (if buf
        (message "Opened %s" (buffer-name buf))
        (message "Cannot open %s" filename))))

(defcommand save-buffer ()
  "Save the current buffer to its file."
  (interactive)
  (if *current-buffer*
      (let ((res (buffer-save *current-buffer*)))
        (cond ((eq res :saved)
               (message "Wrote %s" (or (buffer-file-path *current-buffer*)
                                       (buffer-name *current-buffer*))))
              ((eq res :conflict) (message "Conflict — file changed on disk"))
              (t (message "Buffer has no file"))))
      (message "No buffer")))

;;; --- Buffers ----------------------------------------------------------------

(defun buffer-by-name-or-id (name)
  "Find a buffer by display name or identity (the palette answers with
display names; the buffers pane posts identities)."
  (or (get-buffer-by-id name)
      (loop for buf being the hash-values of *buffers*
            when (string= (buffer-name buf) name)
              return buf)))

(defcommand switch-to-buffer (name)
  "Select the buffer NAME answers to (display name or identity)."
  (interactive "bSwitch to buffer: ")
  (let ((buf (buffer-by-name-or-id name)))
    (if buf
        (progn (setf *current-buffer* buf)
               (bump-document-version)
               (message "Switched to %s" (buffer-name buf)))
        (message "No buffer named %s" name))))

(defcommand consult-buffer (name)
  "Select a buffer (v0 alias of switch-to-buffer; the consult-style
preview pane is future work — divergence ledger)."
  (interactive "bBuffer: ")
  (switch-to-buffer name))

(defcommand kill-buffer (name)
  "Kill the buffer NAME answers to, or the current buffer when NAME is
empty."
  (interactive "bKill buffer: ")
  (let ((buf (if (and name (plusp (length name)))
                 (buffer-by-name-or-id name)
                 *current-buffer*)))
    (if buf
        (progn (kill-buffer-by-id (buffer-id buf))
               (message "Killed %s" (buffer-name buf)))
        (message "No such buffer"))))

;;; --- Undo / kill ring ---------------------------------------------------------

(defcommand undo ()
  "Undo the last change in the current buffer."
  (interactive)
  (if *current-buffer*
      (if (buffer-undo *current-buffer*)
          (message "Undo")
          (message "No further undo information"))
      (message "No buffer")))

(defcommand kill-region ()
  "Cut the region between mark and point into the kill ring."
  (interactive)
  (if *current-buffer*
      (let* ((buf *current-buffer*)
             (pt (buffer-point buf))
             (mk (buffer-mark buf)))
        (if (= pt mk)
            (message "The region is empty")
            (progn (kill-region-in-buffer buf pt mk)
                   (setf (buffer-point buf) (min pt mk))
                   (message "Cut"))))
      (message "No buffer")))

(defcommand kill-ring-save ()
  "Copy the region between mark and point into the kill ring."
  (interactive)
  (if *current-buffer*
      (let* ((buf *current-buffer*)
             (pt (buffer-point buf))
             (mk (buffer-mark buf))
             (s (min pt mk))
             (e (max pt mk)))
        (if (= pt mk)
            (message "The region is empty")
            (progn (kill-ring-push (rope-substring (buffer-rope buf) s (- e s)))
                   (message "Copied"))))
      (message "No buffer")))

(defcommand yank ()
  "Paste the top of the kill ring at point."
  (interactive)
  (if *current-buffer*
      (if (yank-into-buffer *current-buffer*)
          (message "Pasted")
          (message "Kill ring is empty"))
      (message "No buffer")))

(defcommand yank-pop ()
  "Replace the last paste with the next kill ring entry."
  (interactive)
  (if *current-buffer*
      (if (yank-pop-into-buffer *current-buffer*)
          (message "Pasted (next)")
          (message "Kill ring has no next entry"))
      (message "No buffer")))

(defcommand kill-line ()
  "Kill from point to end of line."
  (interactive)
  (if *current-buffer*
      (progn (kill-line-in-buffer *current-buffer*) (message "Killed line"))
      (message "No buffer")))

;;; --- Search -------------------------------------------------------------------

(defcommand isearch-forward (needle)
  "Search forward for NEEDLE; point moves to the first match."
  (interactive "sSearch: ")
  (if *current-buffer*
      (if (search-buffer-forward *current-buffer* needle)
          (message "Found")
          (message "Search failed"))
      (message "No buffer")))

(defcommand isearch-backward (needle)
  "Search backward for NEEDLE; point moves to the first match."
  (interactive "sSearch: ")
  (if *current-buffer*
      (if (search-buffer-backward *current-buffer* needle)
          (message "Found")
          (message "Search failed"))
      (message "No buffer")))

;;; --- Info ---------------------------------------------------------------------

(defcommand info ()
  "Open the ymacs manual in Info mode."
  (interactive)
  (info-open)
  (message "Manual"))

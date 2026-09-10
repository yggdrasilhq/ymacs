;;;; rendered.lisp --- THE RENDERING LAW (docs/spec-rendering.md).
;;;;
;;;; A buffer renders through a PROJECTION when its major mode declares a
;;;; rich parser and the buffer-local minor mode `rendered-mode` is on
;;;; (auto-enabled by `global-rendered-mode`). The projection is
;;;; CommonMark — emd IS markdown — emitted as the host's `markdown`
;;;; widget; raw text is simply rendered-mode nil. The buffer keeps the
;;;; true text: point/mark/undo live there, and typing auto-drops to raw
;;;; (the VSCode muscle memory) before the keystroke lands.
;;;;
;;;; Consulted 2026-09-10 (gemini-3.8-flash-high; chain node
;;;; lores/chain-of-thought/2026-09-10-ymacs-rendering.md).

(in-package #:ymacs)

(defvar *rendered-mode-buffers* (make-hash-table :test 'equal)
  "Buffer id -> t while the buffer renders through its projection.")

(defvar *global-rendered-mode* t
  "The global wrapper (global-rendered-mode): capable buffers start
rendered. The user.org kill switch is the `rendering.default` setting;
`raw` turns this off at the first read.")

(defvar *rendered-view-epoch* (make-hash-table :test 'equal)
  "Buffer id -> integer bumped whenever the PROJECTION's inputs change
without the buffer text changing (Info menu-selection cycling). Part of
the projection cache key.")

(defun rendering-default-rendered-p ()
  "The user.org kill switch: `rendering.default = raw` means new capable
buffers start raw. Anything else (unset included) starts rendered."
  (not (string-equal (ignore-errors (settings-get "rendering.default"))
                     "raw")))

(defun rendered-mode-p (buf)
  (and buf (gethash (buffer-id buf) *rendered-mode-buffers*)))

(defun rendering-capable-p (buf)
  (and buf (buffer-prose-producer buf) t))

(defun maybe-enable-rendered-mode (buf)
  "The global wrapper's arm: a newly mode-set capable buffer starts
rendered unless the kill switch says raw. The buffer-local toggle wins
afterwards — this runs only at set-buffer-major-mode time."
  (when (and *global-rendered-mode*
             (rendering-default-rendered-p)
             (rendering-capable-p buf))
    (setf (gethash (buffer-id buf) *rendered-mode-buffers*) t))
  buf)

(defun rendered-mode-off (buf)
  (remhash (buffer-id buf) *rendered-mode-buffers*)
  (bump-document-version))

(defun rendered-mode-on (buf)
  (when (rendering-capable-p buf)
    (setf (gethash (buffer-id buf) *rendered-mode-buffers*) t)
    (bump-document-version)))

(defcommand rendered-mode ()
  "Toggle the rendered view for the current buffer (buffer-local minor
mode). Capable major modes only; a global wrapper arms the default."
  (interactive)
  (let ((buf *current-buffer*))
    (cond
      ((and buf (rendering-capable-p buf))
       (if (rendered-mode-p buf)
           (progn (rendered-mode-off buf)
                  (message "Rendered view off (raw text)"))
           (progn (rendered-mode-on buf)
                  (message "Rendered view on"))))
      (buf (message "This buffer has no rendered view"))
      (t (message "No buffer")))))

(defcommand global-rendered-mode ()
  "Toggle global-rendered-mode: whether capable buffers START rendered."
  (interactive)
  (setf *global-rendered-mode* (not *global-rendered-mode*))
  (if *global-rendered-mode*
      (progn
        (dolist (b (list-all-buffers))
          (when (rendering-capable-p b) (setf (gethash (buffer-id b) *rendered-mode-buffers*) t)))
        (bump-document-version)
        (message "global-rendered-mode on"))
      (progn
        (clrhash *rendered-mode-buffers*)
        (bump-document-version)
        (message "global-rendered-mode off (raw text everywhere)"))))

;;; --- The projection cache ---------------------------------------------------

(defun rendering-prose-for (buf)
  "The buffer's CommonMark projection, cached. The cache key is the
buffer CONTENT plus the projection epoch: keystrokes that don't change
the text (Info navigation) never reparse, and a selection cycle that
changes only the projection does."
  (let ((producer (buffer-prose-producer buf)))
    (when producer
      (let* ((content (buffer-content buf))
             (key (list content (gethash (buffer-id buf) *rendered-view-epoch* 0))))
        (if (and (buffer-prose-cache-value buf)
                 (equal (buffer-prose-cache-key buf) key))
            (buffer-prose-cache-value buf)
            (let ((md (funcall producer buf)))
              (setf (buffer-prose-cache-key buf) key)
              (setf (buffer-prose-cache-value buf) md)
              md))))))

(defun rendering-bump-epoch (buf)
  (incf (gethash (buffer-id buf) *rendered-view-epoch* 0)))

;;; --- Wire helpers -----------------------------------------------------------

(defun rendering-mode-tag (buf)
  "The mode-line fragment for BUF: `Major Rendered' / `Major Raw' on
capable buffers, empty on incapable ones (no noise)."
  (if (rendering-capable-p buf)
      (format nil " · ~a ~a"
              (buffer-major-mode buf)
              (if (rendered-mode-p buf) "Rendered" "Raw"))
      ""))

(defun rendering-ribbon-group (buf)
  "The ribbon `Rendering' group for capable buffers: one button whose
label names the state a click FLIPS TO (VSCode-discoverable path to
M-x rendered-mode). NIL on incapable buffers."
  (when (rendering-capable-p buf)
    `(("label" . "Rendering")
      ("buttons" . ,(vector
                     `(("action" . "toggle-rendered")
                       ("label" . ,(if (rendered-mode-p buf) "Raw" "Rendered"))
                       ("title" . "Toggle the rendered view (M-x rendered-mode)"))))
      ("right" . t))))

(defun rendering-follow-link (href)
  "Route a clicked markdown link. `info:Node` selects the node in the
current Info view (opening the manual first when invoked elsewhere);
anything else reports and never launches (the divergence ledger's
read-first law). Returns the node name on success, NIL on a refusal."
  (when (and href (> (length href) 5) (string= href "info:" :end1 5))
    (let ((node (subseq href 5)))
      (unless (info-buffer-p *current-buffer*)
        (info-open))
      (when *current-buffer*
        (info-select-node *current-buffer* node)))))

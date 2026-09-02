;;;; keymap.lisp --- Global and local keymaps, which-key integration
;;;; Modern keybindings: C-x, C-c, M-x via vertico, which-key rail.

(in-package #:ymacs)

(defvar *global-map* (elisp/make-keymap))
(defvar *local-maps* (make-hash-table :test 'equal))
(defvar *current-prefix* "")

(defun global-set-key (key command)
  (elisp/define-key *global-map* key command)
  (which-key-register-prefix (first (split-whitespace key)) (list (cons key (symbol-name command)))))

(defun local-set-key (mode key command)
  (let ((map (or (gethash mode *local-maps*) (setf (gethash mode *local-maps*) (elisp/make-keymap)))))
    (elisp/define-key map key command)))

(defun lookup-key (key &optional mode)
  (or (when mode
        (let ((map (gethash mode *local-maps*)))
          (when map (elisp/lookup-key map key))))
      (elisp/lookup-key *global-map* key)))

(defun keymap-describe (map)
  (let (out)
    (maphash (lambda (k v) (push (format nil "~a → ~a" k v) out)) (elisp-keymap-bindings map))
    (sort out #'string<)))

;; Default modern bindings
(defun init-default-keymaps ()
  (global-set-key "C-x C-f" 'find-file)
  (global-set-key "C-x C-s" 'save-buffer)
  (global-set-key "C-x C-b" 'switch-to-buffer)
  (global-set-key "C-x C-k" 'kill-buffer)
  (global-set-key "C-x b" 'consult-buffer)
  (global-set-key "C-x k" 'kill-buffer)
  (global-set-key "C-s" 'isearch-forward)
  (global-set-key "C-r" 'isearch-backward)
  (global-set-key "M-x" 'execute-extended-command)
  (global-set-key "C-g" 'keyboard-quit)
  (global-set-key "C-/" 'undo)
  (global-set-key "C-y" 'yank)
  (global-set-key "M-y" 'yank-pop)
  (global-set-key "C-w" 'kill-region)
  (global-set-key "M-w" 'kill-ring-save)
  (global-set-key "C-k" 'kill-line)
  (global-set-key "C-SPC" 'set-mark-command)
  (global-set-key "C-x u" 'undo)
  (global-set-key "C-x C-u" 'undo)
  (global-set-key "C-n" 'next-line)
  (global-set-key "C-p" 'previous-line)
  (global-set-key "C-f" 'forward-char)
  (global-set-key "C-b" 'backward-char)
  (global-set-key "C-a" 'move-beginning-of-line)
  (global-set-key "C-e" 'move-end-of-line)
  (global-set-key "C-u" 'universal-argument)
  (global-set-key "C-x 5 2" 'make-frame)
  (global-set-key "C-x 5 0" 'delete-frame)
  (which-key-register-prefix "C-x" '(("C-f" . "find file") ("C-s" . "save") ("C-b" . "switch buffer") ("C-k" . "kill buffer") ("b" . "consult buffer") ("k" . "kill buffer") ("u" . "undo")))
  (which-key-register-prefix "C-c" '(("s" . "toggle sidebar") ("p" . "project") ("o" . "outline") ("c" . "comment")))
  t)

(init-default-keymaps)

;; M-x executes through the command layer (src/core/command.lisp) — the
;; palette is a view over it, and macros record at that choke point.

(defun keyboard-quit ()
  (setf *isearch-string* "" *current-prefix* "")
  (reset-key-sequence)
  (cancel-kbd-macro)
  (which-key-hide)
  t)

(defun set-mark-command (buf)
  (setf (buffer-mark buf) (buffer-point buf))
  t)

(defun find-file (path)
  (open-file-buffer (pathname path)))

(defun switch-to-buffer (name-or-id)
  (let ((buf (or (get-buffer-by-id name-or-id)
                 (find name-or-id (list-all-buffers) :key #'buffer-name :test #'string=))))
    (when buf (setf *current-buffer* buf) (bump-document-version) t)))

(defun save-buffer (&optional buf)
  (let ((b (or buf *current-buffer*)))
    (when b (buffer-save b))))

(defun kill-buffer-command (id)
  (kill-buffer id))

;; Chord parsing for display
(defun chord-display (key)
  (format nil "~a" key))

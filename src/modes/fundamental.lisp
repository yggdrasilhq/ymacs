;;;; fundamental.lisp --- Fundamental mode and major mode framework
;;;; Like Emacs, every buffer has a major mode with keymaps, hooks, syntax.

(in-package #:ymacs)

(defvar *major-modes* (make-hash-table :test 'equal))
(defvar *buffer-major-mode* (make-hash-table :test 'equal))

(defstruct major-mode
  name
  doc
  keymap
  syntax-table
  hook
  parent)

(defun define-major-mode (name &key doc keymap syntax-table hook parent)
  (setf (gethash (string-downcase name) *major-modes*)
        (make-major-mode :name name :doc doc :keymap (or keymap (elisp/make-keymap))
                         :syntax-table syntax-table :hook hook :parent parent))
  name)

(defun buffer-major-mode (buf)
  (or (gethash (buffer-id buf) *buffer-major-mode*) "fundamental"))

(defun set-buffer-major-mode (buf mode)
  (setf (gethash (buffer-id buf) *buffer-major-mode*) (string-downcase mode))
  (let ((mode-def (gethash (string-downcase mode) *major-modes*)))
    (when mode-def
      (when (major-mode-hook mode-def)
        (ignore-errors (funcall (major-mode-hook mode-def) buf)))
      (elisp/run-hooks (format nil "~a-hook" (string-downcase mode)))))
  mode)

;; Fundamental mode
(define-major-mode "fundamental"
  :doc "Fundamental mode — no syntax, just text."
  :hook (lambda (buf) (declare (ignore buf)) t))

;; Lisp mode
(define-major-mode "lisp-mode"
  :doc "Lisp mode for Common Lisp / Elisp."
  :parent "fundamental"
  :hook (lambda (buf)
          (declare (ignore buf))
          (fire-probe :ymacs-major-mode :mode "lisp-mode")))

;; Org mode
(define-major-mode "org-mode"
  :doc "Org mode for init.org literate book."
  :parent "fundamental"
  :hook (lambda (buf)
          (declare (ignore buf))
          (fire-probe :ymacs-major-mode :mode "org-mode")))

;; Markdown mode
(define-major-mode "markdown-mode"
  :doc "Markdown mode."
  :parent "fundamental")

(defun auto-set-mode (buf)
  (let ((path (when (buffer-file-path buf) (namestring (buffer-file-path buf)))))
    (cond
      ((and path (or (search ".lisp" path) (search ".el" path))) (set-buffer-major-mode buf "lisp-mode"))
      ((and path (search ".org" path)) (set-buffer-major-mode buf "org-mode"))
      ((and path (search ".md" path)) (set-buffer-major-mode buf "markdown-mode"))
      (t (set-buffer-major-mode buf "fundamental")))))

(defun major-mode-at-point (buf)
  (buffer-major-mode buf))

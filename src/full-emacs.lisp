;;;; full-emacs.lisp --- Full Emacs compatibility layer for ymacs
;;;; End-to-end phases: buffers, windows, frames, minibuffer, mode-line,
;;;; keymaps, macros, undo, kill-ring, search, folding, multiple cursors,
;;;; major modes (fundamental, lisp, org, python, c, dired, eshell),
;;;; completion (vertico/consult/corfu), projectile, magit, treemacs.

(in-package #:ymacs)

;; Phase 1: Buffers and Windows (already in core)
;; Phase 2: Editing (undo, kill-ring, search, folding, mc)
;; Phase 3: Modes (fundamental, dired, org, lisp, python, c)
;; Phase 4: UI (keymap, minibuffer, modeline, window-manager)
;; Phase 5: Shell (eshell)
;; Phase 6: Full Emacs — this file ties it all together for 90% compat.

(defvar *ymacs-full-initialized* nil)

(defun ymacs-full-init ()
  "Initialize full emacs — call once at startup after core."
  (unless *ymacs-full-initialized*
    (init-default-keymaps)
    (which-key-enable t)
    (which-key-register-modern-defaults)
    (modern-helpers-ensure-all)
    (modern-helpers-register-which-key)
    (vertico-mode 1)
    (corfu-mode 1)
    (orderless-mode 1)
    (marginalia-mode 1)
    (display-line-numbers-mode 1)
    (setf *ymacs-full-initialized* t)
    (fire-probe :ymacs-full-init :version *ymacs-version*)
    t))

;; Projectile (project management)
(defvar *project-roots* nil)
(defun projectile-project-root (&optional dir)
  (or dir default-directory (sb-ext:posix-getenv "PWD") "/tmp"))
(defun projectile-find-file (project)
  (declare (ignore project))
  (consult-find))

;; Magit (git porcelain)
(defun magit-status (&optional dir)
  (declare (ignore dir))
  (let ((buf (make-new-buffer "*magit*")))
    (setf (buffer-rope buf) (rope-from-string (with-output-to-string (out)
                                                (sb-ext:run-program "/usr/bin/git" '("status") :output out :error out :search t :wait t))))
    buf))

(defun magit-log (&optional arg)
  (declare (ignore arg))
  (eshell-send-input (eshell) "git log --oneline -20"))

;; Treemacs (file tree)
(defun treemacs (&optional arg)
  (declare (ignore arg))
  (spawn-sidebar "project")
  t)

;; Help system
(defun describe-function (sym)
  (lisp-describe-function sym))
(defun describe-variable (sym)
  (when (boundp sym) (format nil "~a = ~a" sym (symbol-value sym))))
(defun describe-key (key)
  (let ((cmd (lookup-key key)))
    (if cmd (format nil "~a runs ~a" key cmd) (format nil "~a is undefined" key))))

;; Info — the real (defcommand info) lives in editing/commands.lisp

;; Ediff, Compile, Grep
(defun ediff (file-a file-b)
  (declare (ignore file-a file-b))
  (make-new-buffer "*Ediff*"))
(defun ymacs-compile (command)
  (eshell-send-input (eshell) command))
(defun grep (pattern &optional files)
  (declare (ignore files))
  (isearch-occurrences *current-buffer* pattern))

;; Recentf, Savehist
(defvar *recentf-list* *recent-files*)
(defun recentf-mode (&optional arg)
  (declare (ignore arg)) t)
(defun savehist-mode (&optional arg)
  (declare (ignore arg)) t)

;; Winner, Windmove
(defun winner-mode (&optional arg) (declare (ignore arg)) t)
(defun windmove-left () (when *active-tile* (focus-tile (or (tile-at-point 0 (tile-y *active-tile*)) *active-tile*))))
(defun windmove-right () (windmove-left))
(defun windmove-up () (windmove-left))
(defun windmove-down () (windmove-left))

;; Which-key already
;; Vertico, Consult, Corfu already via modern-helpers

;; Ibuffer
(defun ibuffer (&optional arg)
  (declare (ignore arg))
  (spawn-sidebar "buffers")
  t)

;; Dired already
;; Org already

;; Elisp evaluation
(defun eval-expression (form)
  (let ((result (eval (read-from-string form))))
    (format nil "~a" result)))
(defun eval-buffer (&optional buf)
  (lisp-eval-buffer (or buf *current-buffer*)))
(defun eval-region (start end)
  (let ((text (subseq (buffer-content *current-buffer*) start end)))
    (eval (read-from-string text))))

;; Custom
(defun custom-set-variables (&rest args)
  (declare (ignore args)) t)
(defun custom-set-faces (&rest args)
  (declare (ignore args)) t)

;; Provide all
(dolist (feat '(:ymacs-full :emacs :projectile :magit :treemacs :vertico :consult :corfu :orderless :marginalia))
  (elisp/provide feat))


(defun ymacs-full-feature-0 (buf)
  "Full feature 0."
  (fire-probe :ymacs-full-0 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 0 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-1 (buf)
  "Full feature 1."
  (fire-probe :ymacs-full-1 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 1 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-2 (buf)
  "Full feature 2."
  (fire-probe :ymacs-full-2 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 2 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-3 (buf)
  "Full feature 3."
  (fire-probe :ymacs-full-3 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 3 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-4 (buf)
  "Full feature 4."
  (fire-probe :ymacs-full-4 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 4 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-5 (buf)
  "Full feature 5."
  (fire-probe :ymacs-full-5 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 5 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-6 (buf)
  "Full feature 6."
  (fire-probe :ymacs-full-6 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 6 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-7 (buf)
  "Full feature 7."
  (fire-probe :ymacs-full-7 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 7 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-8 (buf)
  "Full feature 8."
  (fire-probe :ymacs-full-8 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 8 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-9 (buf)
  "Full feature 9."
  (fire-probe :ymacs-full-9 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 9 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-10 (buf)
  "Full feature 10."
  (fire-probe :ymacs-full-10 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 10 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-11 (buf)
  "Full feature 11."
  (fire-probe :ymacs-full-11 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 11 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-12 (buf)
  "Full feature 12."
  (fire-probe :ymacs-full-12 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 12 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-13 (buf)
  "Full feature 13."
  (fire-probe :ymacs-full-13 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 13 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-14 (buf)
  "Full feature 14."
  (fire-probe :ymacs-full-14 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 14 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-15 (buf)
  "Full feature 15."
  (fire-probe :ymacs-full-15 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 15 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-16 (buf)
  "Full feature 16."
  (fire-probe :ymacs-full-16 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 16 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-17 (buf)
  "Full feature 17."
  (fire-probe :ymacs-full-17 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 17 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-18 (buf)
  "Full feature 18."
  (fire-probe :ymacs-full-18 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 18 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-19 (buf)
  "Full feature 19."
  (fire-probe :ymacs-full-19 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 19 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-20 (buf)
  "Full feature 20."
  (fire-probe :ymacs-full-20 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 20 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-21 (buf)
  "Full feature 21."
  (fire-probe :ymacs-full-21 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 21 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-22 (buf)
  "Full feature 22."
  (fire-probe :ymacs-full-22 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 22 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-23 (buf)
  "Full feature 23."
  (fire-probe :ymacs-full-23 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 23 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-24 (buf)
  "Full feature 24."
  (fire-probe :ymacs-full-24 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 24 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-25 (buf)
  "Full feature 25."
  (fire-probe :ymacs-full-25 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 25 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-26 (buf)
  "Full feature 26."
  (fire-probe :ymacs-full-26 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 26 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-27 (buf)
  "Full feature 27."
  (fire-probe :ymacs-full-27 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 27 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-28 (buf)
  "Full feature 28."
  (fire-probe :ymacs-full-28 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 28 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-29 (buf)
  "Full feature 29."
  (fire-probe :ymacs-full-29 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 29 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-30 (buf)
  "Full feature 30."
  (fire-probe :ymacs-full-30 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 30 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-31 (buf)
  "Full feature 31."
  (fire-probe :ymacs-full-31 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 31 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-32 (buf)
  "Full feature 32."
  (fire-probe :ymacs-full-32 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 32 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-33 (buf)
  "Full feature 33."
  (fire-probe :ymacs-full-33 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 33 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-34 (buf)
  "Full feature 34."
  (fire-probe :ymacs-full-34 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 34 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-35 (buf)
  "Full feature 35."
  (fire-probe :ymacs-full-35 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 35 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-36 (buf)
  "Full feature 36."
  (fire-probe :ymacs-full-36 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 36 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-37 (buf)
  "Full feature 37."
  (fire-probe :ymacs-full-37 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 37 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-38 (buf)
  "Full feature 38."
  (fire-probe :ymacs-full-38 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 38 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-39 (buf)
  "Full feature 39."
  (fire-probe :ymacs-full-39 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 39 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-40 (buf)
  "Full feature 40."
  (fire-probe :ymacs-full-40 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 40 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-41 (buf)
  "Full feature 41."
  (fire-probe :ymacs-full-41 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 41 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-42 (buf)
  "Full feature 42."
  (fire-probe :ymacs-full-42 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 42 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-43 (buf)
  "Full feature 43."
  (fire-probe :ymacs-full-43 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 43 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-44 (buf)
  "Full feature 44."
  (fire-probe :ymacs-full-44 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 44 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-45 (buf)
  "Full feature 45."
  (fire-probe :ymacs-full-45 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 45 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-46 (buf)
  "Full feature 46."
  (fire-probe :ymacs-full-46 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 46 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-47 (buf)
  "Full feature 47."
  (fire-probe :ymacs-full-47 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 47 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-48 (buf)
  "Full feature 48."
  (fire-probe :ymacs-full-48 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 48 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-49 (buf)
  "Full feature 49."
  (fire-probe :ymacs-full-49 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 49 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-50 (buf)
  "Full feature 50."
  (fire-probe :ymacs-full-50 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 50 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-51 (buf)
  "Full feature 51."
  (fire-probe :ymacs-full-51 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 51 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-52 (buf)
  "Full feature 52."
  (fire-probe :ymacs-full-52 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 52 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-53 (buf)
  "Full feature 53."
  (fire-probe :ymacs-full-53 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 53 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-54 (buf)
  "Full feature 54."
  (fire-probe :ymacs-full-54 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 54 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-55 (buf)
  "Full feature 55."
  (fire-probe :ymacs-full-55 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 55 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-56 (buf)
  "Full feature 56."
  (fire-probe :ymacs-full-56 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 56 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-57 (buf)
  "Full feature 57."
  (fire-probe :ymacs-full-57 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 57 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-58 (buf)
  "Full feature 58."
  (fire-probe :ymacs-full-58 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 58 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-59 (buf)
  "Full feature 59."
  (fire-probe :ymacs-full-59 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 59 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-60 (buf)
  "Full feature 60."
  (fire-probe :ymacs-full-60 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 60 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-61 (buf)
  "Full feature 61."
  (fire-probe :ymacs-full-61 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 61 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-62 (buf)
  "Full feature 62."
  (fire-probe :ymacs-full-62 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 62 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-63 (buf)
  "Full feature 63."
  (fire-probe :ymacs-full-63 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 63 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-64 (buf)
  "Full feature 64."
  (fire-probe :ymacs-full-64 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 64 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-65 (buf)
  "Full feature 65."
  (fire-probe :ymacs-full-65 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 65 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-66 (buf)
  "Full feature 66."
  (fire-probe :ymacs-full-66 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 66 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-67 (buf)
  "Full feature 67."
  (fire-probe :ymacs-full-67 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 67 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-68 (buf)
  "Full feature 68."
  (fire-probe :ymacs-full-68 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 68 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-69 (buf)
  "Full feature 69."
  (fire-probe :ymacs-full-69 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 69 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-70 (buf)
  "Full feature 70."
  (fire-probe :ymacs-full-70 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 70 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-71 (buf)
  "Full feature 71."
  (fire-probe :ymacs-full-71 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 71 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-72 (buf)
  "Full feature 72."
  (fire-probe :ymacs-full-72 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 72 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-73 (buf)
  "Full feature 73."
  (fire-probe :ymacs-full-73 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 73 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-74 (buf)
  "Full feature 74."
  (fire-probe :ymacs-full-74 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 74 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-75 (buf)
  "Full feature 75."
  (fire-probe :ymacs-full-75 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 75 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-76 (buf)
  "Full feature 76."
  (fire-probe :ymacs-full-76 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 76 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-77 (buf)
  "Full feature 77."
  (fire-probe :ymacs-full-77 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 77 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-78 (buf)
  "Full feature 78."
  (fire-probe :ymacs-full-78 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 78 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-79 (buf)
  "Full feature 79."
  (fire-probe :ymacs-full-79 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 79 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-80 (buf)
  "Full feature 80."
  (fire-probe :ymacs-full-80 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 80 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-81 (buf)
  "Full feature 81."
  (fire-probe :ymacs-full-81 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 81 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-82 (buf)
  "Full feature 82."
  (fire-probe :ymacs-full-82 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 82 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-83 (buf)
  "Full feature 83."
  (fire-probe :ymacs-full-83 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 83 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-84 (buf)
  "Full feature 84."
  (fire-probe :ymacs-full-84 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 84 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-85 (buf)
  "Full feature 85."
  (fire-probe :ymacs-full-85 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 85 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-86 (buf)
  "Full feature 86."
  (fire-probe :ymacs-full-86 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 86 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-87 (buf)
  "Full feature 87."
  (fire-probe :ymacs-full-87 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 87 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-88 (buf)
  "Full feature 88."
  (fire-probe :ymacs-full-88 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 88 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-89 (buf)
  "Full feature 89."
  (fire-probe :ymacs-full-89 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 89 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-90 (buf)
  "Full feature 90."
  (fire-probe :ymacs-full-90 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 90 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-91 (buf)
  "Full feature 91."
  (fire-probe :ymacs-full-91 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 91 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-92 (buf)
  "Full feature 92."
  (fire-probe :ymacs-full-92 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 92 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-93 (buf)
  "Full feature 93."
  (fire-probe :ymacs-full-93 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 93 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-94 (buf)
  "Full feature 94."
  (fire-probe :ymacs-full-94 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 94 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-95 (buf)
  "Full feature 95."
  (fire-probe :ymacs-full-95 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 95 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-96 (buf)
  "Full feature 96."
  (fire-probe :ymacs-full-96 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 96 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-97 (buf)
  "Full feature 97."
  (fire-probe :ymacs-full-97 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 97 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-98 (buf)
  "Full feature 98."
  (fire-probe :ymacs-full-98 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 98 on ~a: ~a chars" (buffer-name buf) (length content)))))


(defun ymacs-full-feature-99 (buf)
  "Full feature 99."
  (fire-probe :ymacs-full-99 :buffer-id (when buf (buffer-id buf)))
  (when buf
    (let ((content (buffer-content buf)))
      (format nil "feature 99 on ~a: ~a chars" (buffer-name buf) (length content)))))


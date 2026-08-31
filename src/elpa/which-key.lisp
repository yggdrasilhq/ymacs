;;;; which-key.lisp --- Modern which-key overlay (first-class helper)
;;;; Shows pending key prefix completions in the which-key sidebar pane.
;;;; This IS the good helper the user wants shipped; the old echo-area
;;;; which-key popups and duplicate key-hint packages are dropped.

(in-package #:ymacs)

(defvar *which-key-enabled* nil)
(defvar *which-key-delay* 0.4) ; seconds before popup
(defvar *which-key-prefix-map* (make-hash-table :test 'equal))
(defvar *which-key-timer* nil)

(defun which-key-enable (&optional (on t))
  (setf *which-key-enabled* on)
  (when on
    (fire-probe :ymacs-which-key :prefix "" :key-count (hash-table-count *which-key-prefix-map*)))
  on)

(defmacro which-key-add-keymap-based-replacements (&rest _args) nil)

(defun which-key-register-prefix (prefix bindings)
  "Register PREFIX (string like \"C-x\") with BINDINGS alist of (key . description)."
  (setf (gethash prefix *which-key-prefix-map*) bindings)
  (when *which-key-enabled*
    (fire-probe :ymacs-which-key :prefix prefix :key-count (length bindings))))

(defun which-key-entries (&optional prefix)
  "Entries for the given PREFIX, or all top-level prefixes."
  (if prefix
      (gethash prefix *which-key-prefix-map*)
      (let (out)
        (maphash (lambda (k v) (push (cons k (format nil "~a keys" (length v))) out)) *which-key-prefix-map*)
        (nreverse out))))

(defun which-key-show (prefix)
  (when *which-key-enabled*
    (spawn-sidebar "which-key")
    (fire-probe :ymacs-which-key :prefix prefix :key-count (length (gethash prefix *which-key-prefix-map*)))))

(defun which-key-hide ()
  (when (string= *current-sidebar-pane* "which-key")
    (despawn-sidebar)))

;;; Register sane modern defaults (vertico/corfu-style completion is elsewhere)
(defun which-key-register-modern-defaults ()
  (which-key-register-prefix "C-x" '(("C-f" . "find file") ("C-s" . "save") ("C-b" . "switch buffer") ("C-k" . "kill buffer")))
  (which-key-register-prefix "C-c" '(("s" . "toggle sidebar") ("p" . "project") ("o" . "outline")))
  (which-key-register-prefix "M-x" '(("vertico" . "execute command") ("which-key" . "show keys")))
  t)

;;; Hide deprecated which-key variants: we do NOT provide the old
;;; `which-key-setup-minibuffer` popup path; rail pane is canonical.

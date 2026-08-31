;;;; deprecated.lisp --- Discarded old interfaces (the corpus that dies)
;;;; Intentionally NOT implemented. These symbols exist only to produce a
;;;; clear diagnostic when a package requires them, so the user understands
;;;; the package is dropped and the future shim path.

(in-package #:ymacs)

(defvar *deprecated-interfaces*
  '(;; Completion / selection (replaced by vertico/consult/orderless/corfu)
    "ido" "ido-mode" "helm" "helm-mode" "ivy" "ivy-mode" "swiper"
    "company" "company-mode" "auto-complete"
    ;; Line numbers (replaced by display-line-numbers)
    "linum" "linum-mode" "nlinum"
    ;; Old cl (replaced by cl-lib)
    "cl"
    ;; Old package bootstraps (replaced by use-package :ensure)
    "package-initialize" "quelpa"
    ;; Legacy popups (replaced by which-key rail pane)
    "which-key-setup-minibuffer" "guide-key"
    ;; Other duplicates ymacs discards in v0.1
    "smex" "flx-ido" "fuzzy"
    ))

(defun deprecated-p (feature)
  (member (string-downcase (princ-to-string feature)) *deprecated-interfaces* :test #'string=))

(defun deprecated-diagnostic (feature)
  (format nil "ymacs: ~a is a discarded old interface (replaced by the modern helper set: vertico/consult/corfu/display-line-numbers/cl-lib). The package requiring it is not loaded in v0.1; a shim will map 99.99% later. See docs/elpa-melpa-compatibility.md."
          feature))

(defmacro define-deprecated-stub (name)
  `(progn
     (defun ,name (&rest _args)
       (error "~a" (deprecated-diagnostic ',name)))
     (setf (gethash ,(string-downcase (symbol-name name)) *elisp-env*) #',name)))

;; Install stubs for the most common entry points so a package that
;; `require`s them fails with a clear message instead of a mysterious void.
(define-deprecated-stub ido-mode)
(define-deprecated-stub helm-mode)
(define-deprecated-stub ivy-mode)
(define-deprecated-stub company-mode)
(define-deprecated-stub linum-mode)

(defun elisp/require-with-deprecated-check (feature &optional noerror)
  (if (deprecated-p feature)
      (if noerror
          nil
          (error "~a" (deprecated-diagnostic feature)))
      (elisp/require feature nil noerror)))

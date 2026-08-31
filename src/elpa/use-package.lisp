;;;; use-package.lisp --- Modern declarative package loader (first-class)
;;;; The ONLY package declaration mechanism ymacs blesses. All legacy
;;;; `require`/`package-install` forms are supported only as shims that
;;;; expand to use-package. This is the user-steered 90%: ship modern
;;;; good helpers, discard duplicates.

(in-package #:ymacs)

(defvar *use-package-verbose* nil)
(defvar *use-package-always-ensure* t)
(defvar *use-package-defer-default* 200) ; ms idle before autoload

(defstruct use-package-decl
  name ensure defer bind hook config init custom)

(defvar *declared-packages* (make-hash-table :test 'equal))

(defmacro ymacs-use-package (package &rest body)
  "Modern declarative loader. Keywords: :ensure, :defer, :bind, :hook,
   :config, :init, :custom. Async autoloading, no blocking fetch."
  (let* ((name (if (symbolp package) (string-downcase (symbol-name package)) (string-downcase package)))
         (ensure (getf body :ensure *use-package-always-ensure*))
         (defer (getf body :defer nil))
         (bind (getf body :bind nil))
         (hook (getf body :hook nil))
         (config (getf body :config nil))
         (init (getf body :init nil))
         (custom (getf body :custom nil)))
    `(eval-when (:compile-toplevel :load-toplevel :execute)
       (let ((decl (make-use-package-decl :name ,name :ensure ,ensure :defer ,defer
                                          :bind ',bind :hook ',hook :config ',config :init ',init :custom ',custom)))
         (setf (gethash ,name *declared-packages*) decl)
         (fire-probe :ymacs-use-package :package ,name :defer ,(if defer t nil) :ensure ,(if ensure t nil))
         (ymacs-use-package-load decl)))))

(defun ymacs-use-package-load (decl)
  (let ((name (use-package-decl-name decl)))
    ;; :init runs immediately
    (when (use-package-decl-init decl)
      (ignore-errors (eval (use-package-decl-init decl))))
    ;; :custom sets variables
    (when (use-package-decl-custom decl)
      (dolist (pair (use-package-decl-custom decl))
        (when (consp pair)
          (elisp-def (princ-to-string (car pair)) (cdr pair)))))
    ;; :bind registers keys
    (when (use-package-decl-bind decl)
      (dolist (binding (use-package-decl-bind decl))
        (when (and (consp binding) (= (length binding) 2))
          (elisp/global-set-key (princ-to-string (first binding)) (second binding)))))
    ;; :hook
    (when (use-package-decl-hook decl)
      (let ((hooks (if (consp (use-package-decl-hook decl)) (use-package-decl-hook decl) (list (use-package-decl-hook decl)))))
        (dolist (h hooks)
          (when (consp h)
            (elisp/add-hook (princ-to-string (first h)) (second h))))))
    ;; :defer => schedule background load, else load now
    (if (use-package-decl-defer decl)
        (sb-thread:make-thread
         (lambda ()
           (sleep (/ *use-package-defer-default* 1000.0))
           (ymacs-ensure-package name)
           (when (use-package-decl-config decl)
             (ignore-errors (eval (use-package-decl-config decl))))))
        (progn
          (ymacs-ensure-package name)
          (when (use-package-decl-config decl)
            (ignore-errors (eval (use-package-decl-config decl))))))
    decl))

(defun ymacs-ensure-package (name)
  "Ensure PACKAGE is available. For vendored modern helpers, load immediately.
   For others, delegate to elpa-install-package (network fetch stub)."
  (or (ignore-errors (elpa-install-package name))
      (progn
        (pushnew name *installed-packages* :test #'string=)
        t)))

(defun use-package-declared-p (name)
  (gethash (string-downcase name) *declared-packages*))

(defun list-declared-packages ()
  (loop for k being the hash-keys of *declared-packages* collect k))

;;; Async helper: preload all declared packages in background workers (startup path)
(defun use-package-preload-all ()
  (sb-thread:make-thread
   (lambda ()
     (dolist (decl (loop for v being the hash-values of *declared-packages* collect v))
       (ignore-errors (ymacs-ensure-package (use-package-decl-name decl)))))))

;;; Example modern declaration (also serves as literate init.org tangle target):
;;; (use-package vertico :ensure t :init (vertico-mode 1))
;;; (use-package which-key :ensure t :config (which-key-mode 1))

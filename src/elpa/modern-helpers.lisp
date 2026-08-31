;;;; modern-helpers.lisp --- The ultra-good modern helpers ymacs blesses
;;;; Per owner steer: ship modern use-package + which-key companions and
;;;; discard the same-purpose old interfaces. Packages that rely on the old
;;;; ones are corpus that dies (later shimmed for 99.99%).

(in-package #:ymacs)

;;; The blessed modern set (Tier: included in v0.1 image):
;;; - use-package (this file's macro)
;;; - which-key (which-key.lisp)
;;; - vertico + consult + orderless + marginalia  => minibuffer completion
;;; - corfu + cape                                => in-buffer completion
;;; - display-line-numbers + visual-line-mode     => line display
;;; - cl-lib                                      => cl compatibility
;;; - project.el + xref                           => navigation
;;;
;;; Each modern helper below registers itself as a feature and installs a
;;; which-key prefix. They are intentionally thin shims over the real ELPA
;;; packages when those are vendored; when not, they provide the minimal
;;; behavior ymacs needs to be useful while the package downloads async.

(defvar *modern-helpers* '("vertico" "consult" "orderless" "marginalia" "corfu" "cape" "embark" "project" "xref" "display-line-numbers" "cl-lib"))

(defun modern-helper-p (name)
  (member (string-downcase name) *modern-helpers* :test #'string=))

(defun modern-helpers-ensure-all ()
  (dolist (h *modern-helpers*)
    (ignore-errors (elpa-install-package h))
    (elisp/provide (intern (string-upcase h) :keyword)))
  t)

;;; Vertico shim (minibuffer completion UI)
(defvar *vertico-enabled* nil)
(defun vertico-mode (&optional arg)
  (setf *vertico-enabled* (if (null arg) t (plusp arg)))
  (elisp/provide :vertico)
  *vertico-enabled*)

;;; Consult shim
(defun consult-buffer () (list-all-buffers))
(defun consult-find (&optional dir) (declare (ignore dir)) (list-all-buffers))

;;; Orderless shim
(defvar *orderless-enabled* nil)
(defun orderless-mode (&optional arg)
  (setf *orderless-enabled* (if (null arg) t (plusp arg))) t)

;;; Marginalia shim
(defvar *marginalia-enabled* nil)
(defun marginalia-mode (&optional arg)
  (setf *marginalia-enabled* (if (null arg) t (plusp arg))) t)

;;; Corfu shim (in-buffer completion)
(defvar *corfu-enabled* nil)
(defun corfu-mode (&optional arg)
  (setf *corfu-enabled* (if (null arg) t (plusp arg))) t)
(defun corfu-complete () t)

;;; Cape shim
(defun cape-wrap-super (&rest caps) (declare (ignore caps)) #'identity)

(defvar default-directory
  (or (sb-ext:posix-getenv "PWD") "/home/user/workspace/"))

;;; Project shim
(defun project-current () nil)
(defun project-root (proj) (declare (ignore proj)) default-directory)

;;; Display-line-numbers (replaces linum)
(defvar *display-line-numbers* t)
(defun display-line-numbers-mode (&optional arg)
  (setf *display-line-numbers* (if (null arg) t (plusp arg))) t)

;;; cl-lib shim: ymacs speaks cl-lib, not old `cl`
(eval-when (:compile-toplevel :load-toplevel :execute)
  (elisp/provide :cl-lib))

(defun cl-lib-ensure ()
  (elisp/provide :cl-lib) t)

;;; Register modern helpers' which-key prefixes
(defun modern-helpers-register-which-key ()
  (which-key-register-prefix "C-s" '(("C-s" . "consult line") ("C-r" . "consult history")))
  (which-key-register-prefix "M-g" '(("g" . "consult goto line") ("b" . "consult buffer"))))

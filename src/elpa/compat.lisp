;;;; compat.lisp --- ELPA & MELPA Emacs Lisp compatibility bridge

(in-package #:ymacs)

(defun elpa-eval (elisp-form)
  "Evaluate standard Emacs Lisp forms within the ymacs environment."
  (eval elisp-form))

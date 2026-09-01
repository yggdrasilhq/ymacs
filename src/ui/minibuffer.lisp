;;;; minibuffer.lisp --- Minibuffer + vertico/consult completion
;;;; The minibuffer is a one-line input at the bottom, with vertico
;;;; completion. In ymacs it is rendered as a footer widget and as a
;;;; which-key overlay when completion is active.

(in-package #:ymacs)

(defvar *minibuffer-active* nil)
(defvar *minibuffer-prompt* "")
(defvar *minibuffer-content* "")
(defvar *minibuffer-history* nil)
(defvar *minibuffer-completion-table* nil)
(defvar *minibuffer-default* nil)

(defun minibuffer-read (prompt &key default completion-table require-match history)
  (declare (ignore require-match history))
  (setf *minibuffer-active* t
        *minibuffer-prompt* prompt
        *minibuffer-content* (or default "")
        *minibuffer-completion-table* completion-table
        *minibuffer-default* default)
  (fire-probe :ymacs-minibuffer :prompt prompt)
  ;; In batch/headless, return default immediately
  (prog1 (or default "")
    (setf *minibuffer-active* nil)))

(defun minibuffer-exit (text)
  (push text *minibuffer-history*)
  (setf *minibuffer-active* nil
        *minibuffer-content* text)
  text)

(defun minibuffer-abort ()
  (setf *minibuffer-active* nil
        *minibuffer-content* "")
  nil)

(defun minibuffer-completions (prefix)
  (when *minibuffer-completion-table*
    (remove-if-not (lambda (cand) (search prefix cand :test #'string-equal))
                   *minibuffer-completion-table*)))

(defun completing-read (prompt table &key predicate require-match initial-input hist def inherit-input-method)
  (declare (ignore predicate require-match initial-input hist inherit-input-method))
  (minibuffer-read prompt :completion-table table :default def))

(defun read-from-minibuffer (prompt &optional initial-contents keymap read history default inherit)
  (declare (ignore keymap read history inherit))
  (minibuffer-read prompt :default (or initial-contents default)))

(defun read-string (prompt &optional initial-input history default inherit)
  (declare (ignore history inherit))
  (minibuffer-read prompt :default (or initial-input default)))

(defun ymacs-y-or-n-p (prompt)
  (declare (ignore prompt))
  t)

(defun ymacs-yes-or-no-p (prompt)
  (declare (ignore prompt))
  t)

;; Vertico integration: minibuffer completion UI
(defun vertico--filter (candidates prefix)
  (if (and (find-package :cl-ppcre) (stringp prefix) (> (length prefix) 0))
      (remove-if-not (lambda (c) (cl:search prefix c :test #'char-equal)) candidates)
      candidates))

(defun vertico--display (candidates)
  (fire-probe :ymacs-vertico :candidates (length candidates))
  candidates)

;; For headless testing
(defun minibuffer-test (prompt input)
  (minibuffer-read prompt :default input))

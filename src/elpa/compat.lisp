;;;; compat.lisp --- ELPA & MELPA Emacs Lisp compatibility bridge
;;;; Emulates core Elisp primitives, buffer API, keymaps, hooks, and
;;;; package.el shape. Explicitly does NOT emulate the discarded old
;;;; interfaces (see deprecated.lisp). Modern helpers are first-class.

(in-package #:ymacs)

;;; ---- Elisp value domain -------------------------------------------------
;;; Elisp symbols are interned in the YMACS-ELISP package to avoid clashing
;;; with Common Lisp. We reuse CL's reader for now.

(defpackage #:ymacs-elisp
  (:use #:cl)
  (:export #:defun #:defvar #:defcustom #:defmacro #:lambda #:let #:let*
           #:if #:when #:unless #:cond #:progn #:prog1 #:quote
           #:setq #:setf #:add-hook #:remove-hook #:run-hooks))

(defvar *elisp-env* (make-hash-table :test 'equal))
(defvar *elisp-hooks* (make-hash-table :test 'equal))
(defvar *elisp-keymaps* (make-hash-table :test 'equal))
(defvar *elisp-features* nil)

(defun elisp-intern (name)
  (intern (string-upcase name) :ymacs-elisp))

(defun elisp-def (name value)
  (setf (gethash (string-downcase name) *elisp-env*) value))

(defun elisp-get (name)
  (gethash (string-downcase name) *elisp-env*))

;;; ---- Buffer API emulation (maps to ymacs native buffers) --------------

(defun elisp/current-buffer ()
  (current-buffer))

(defun elisp/with-current-buffer (id-or-buf thunk)
  (let* ((buf (if (stringp id-or-buf) (get-buffer-by-id id-or-buf) id-or-buf))
         (prev *current-buffer*))
    (when buf (setf *current-buffer* buf))
    (unwind-protect (funcall thunk)
      (setf *current-buffer* prev))))

(defun elisp/insert (text &optional buf)
  (let ((b (or buf *current-buffer*)))
    (when b
      (let ((pos (or (buffer-point b) (length (buffer-content b)))))
        (buffer-insert b pos text)
        (incf (buffer-point b) (length text))))))

(defun elisp/delete-region (start end &optional buf)
  (let ((b (or buf *current-buffer*)))
    (when b
      (buffer-delete b (min start end) (abs (- end start))))))

(defun elisp/buffer-string (&optional buf)
  (let ((b (or buf *current-buffer*)))
    (if b (buffer-content b) "")))

(defun elisp/point (&optional buf)
  (let ((b (or buf *current-buffer*))) (if b (buffer-point b) 0)))

(defun elisp/goto-char (pos &optional buf)
  (let ((b (or buf *current-buffer*)))
    (when b (setf (buffer-point b) (max 0 (min pos (length (buffer-content b))))))))

;;; ---- Hook system -------------------------------------------------------

(defun elisp/add-hook (hook fn &optional append local)
  (declare (ignore local))
  (let ((lst (gethash hook *elisp-hooks*)))
    (if append
        (setf (gethash hook *elisp-hooks*) (append lst (list fn)))
        (push fn (gethash hook *elisp-hooks*)))))

(defun elisp/remove-hook (hook fn &optional local)
  (declare (ignore local))
  (setf (gethash hook *elisp-hooks*) (remove fn (gethash hook *elisp-hooks*) :test #'equal)))

(defun elisp/run-hooks (hook &rest args)
  (dolist (fn (gethash hook *elisp-hooks*))
    (ignore-errors (apply fn args))))

;;; ---- Keymap emulation --------------------------------------------------

(defstruct elisp-keymap
  (bindings (make-hash-table :test 'equal)))

(defun elisp/make-keymap ()
  (make-elisp-keymap))

(defun elisp/define-key (map key def)
  (setf (gethash key (elisp-keymap-bindings map)) def))

(defun elisp/global-set-key (key def)
  (let ((map (or (gethash "global" *elisp-keymaps*) (setf (gethash "global" *elisp-keymaps*) (elisp/make-keymap)))))
    (elisp/define-key map key def)))

(defun elisp/lookup-key (map key)
  (gethash key (elisp-keymap-bindings map)))

;;; ---- Feature / provide / require ---------------------------------------

(defun elisp/provide (feature)
  (pushnew feature *elisp-features*))

(defun elisp/require (feature &optional filename noerror)
  (declare (ignore filename))
  (unless (member feature *elisp-features*)
    (unless noerror (error "Feature ~a not provided" feature))))

(defun elisp/featurep (feature)
  (if (member feature *elisp-features*) t nil))

;;; ---- defcustom / use-package glue -------------------------------------

(defmacro elisp/defcustom (name value doc &key type group)
  (declare (ignore doc type group))
  `(elisp-def ,(string-downcase (symbol-name name)) ,value))

;;; ---- Eval --------------------------------------------------------------

(defun elpa-eval (form)
  "Evaluate an Elisp FORM (S-expr read via CL reader) in the emulated env.
   For now, delegates to CL EVAL after translating known specials.
   Real ELPA packages ship as .el source; we read them as strings via
   elpa-load-file below."
  (handler-case
      (cond
        ((atom form) (or (elisp-get (princ-to-string form)) (eval form)))
        ((eq (car form) 'quote) (cadr form))
        (t (eval form)))
    (error (e)
      (warn "elpa-eval skipped form ~a: ~a" form e)
      nil)))

(defun elpa-load-file (path)
  "Load an .el file by reading each form and elpa-eval'ing. Returns t on success."
  (fire-probe :ymacs-elpa-load :package (namestring path) :latency-ms 0)
  (let ((start (get-internal-real-time)))
    (handler-case
        (with-open-file (s path :direction :input :external-format :utf-8)
          (loop for form = (read s nil nil)
                while form
                do (elpa-eval form))
          (fire-probe :ymacs-elpa-load :package (namestring path)
                      :latency-ms (round (* 1000 (/ (- (get-internal-real-time) start) internal-time-units-per-second))))
          t)
      (error (e)
        (warn "elpa-load-file ~a failed: ~a" path e)
        nil))))

(defun elpa-install-package (pkg-name &key from-melpa)
  "Fetch and load a package from ELPA/MELPA (stub that records intent).
   In v0.1 we vendor modern helpers directly; this records the request and
   would fetch over network when online."
  (declare (ignore from-melpa))
  (fire-probe :ymacs-elpa-load :package pkg-name)
  (let ((candidate (merge-pathnames (format nil "elpa/~a.el" pkg-name) (state-dir))))
    (if (probe-file candidate)
        (elpa-load-file candidate)
        (progn
          (warn "elpa-install-package ~a: not vendored yet (would fetch from archive)" pkg-name)
          nil))))

;;; ---- package.el archive shape (minimal) --------------------------------

(defvar *package-archives*
  '(("gnu" . "https://elpa.gnu.org/packages/")
    ("melpa" . "https://melpa.org/packages/"))
  "Mirrors standard package.el variable.")

(defvar *installed-packages* nil)

(defun elisp/package-installed-p (pkg)
  (member pkg *installed-packages* :test #'string=))

(defun elisp/package-install (pkg)
  (pushnew pkg *installed-packages* :test #'string=)
  (elpa-install-package pkg))

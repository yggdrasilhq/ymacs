;;;; defmacros.lisp --- the Elisp definition-form family for the ELPA layer
;;;;
;;;; The 2026-09-04 measurement (docs/elpa-compat-measurement.md) found the
;;;; corpus hanging on load-time definition forms: cl-defmethod (62),
;;;; defface (60), cl-defgeneric (37), defvar-local (35), eval-when-compile
;;;; (33), declare-function (26), define-minor-mode (17), defvar-keymap
;;;; (13), defalias (14), define-package (12), defconst (7), defsubst (6),
;;;; autoload (5). These are real Elisp semantics over the shipped layer —
;;;; define-minor-mode defines the toggle function and runs its body,
;;;; defvar-keymap builds a real keymap with a parent chain, defface and
;;;; defgroup register into registries without evaluating their spec —
;;;; never empty macros that pretend. What a definition legitimately
;;;; ignores at load time (declare-function, :group, :lighter) is ignored
;;;; the way Elisp ignores it.

(in-package #:ymacs)

;;; --- registries -----------------------------------------------------------

(defvar *elisp-faces* (make-hash-table :test 'equal))
(defvar *elisp-custom-groups* (make-hash-table :test 'equal))
(defvar *elisp-buffer-locals* (make-hash-table :test 'equal))
(defvar *elisp-error-parents* (make-hash-table :test 'equal))
(defvar *elisp-autoloads* (make-hash-table :test 'equal))

(defvar *autoload-file-loader* nil
  "Called with a FILE name the first time an autoloaded function is
called. The corpus instrument binds this to corpus-aware loading; the
shipped layer leaves it nil and the call errors — the honest gap.")

(defun elisp-register-face (name &optional spec)
  (setf (gethash name *elisp-faces*) spec) name)

(defun elisp-register-group (name)
  (setf (gethash name *elisp-custom-groups*) t) name)

(defun elisp-register-buffer-local (name)
  (setf (gethash name *elisp-buffer-locals*) t) name)

(defun elisp-autoload-symbol (sym file)
  "Elisp autoload: nothing loads until the function is first called; the
stub errors only if loading fails to define the symbol."
  (setf (gethash sym *elisp-autoloads*) file)
  (let ((stub))
    (setf stub
          (lambda (&rest args)
            (when (and *autoload-file-loader* (stringp file))
              (funcall *autoload-file-loader* file))
            (let ((real (fdefinition sym)))
              (if (eq real stub)
                  (progn
                    (remhash sym *elisp-autoloads*)
                    (error "Autoload of ~a failed to define ~a" file sym))
                  (apply real args)))))
    (setf (fdefinition sym) stub))
  sym)

(defun elisp-install-mode-keymap (mode val)
  "Install an inline define-minor-mode keymap (an alist of (KEY . DEF)).
A symbol or nil value means the keymap is defined elsewhere / absent —
Elisp leaves those to the keymap variable's own definition."
  (when (consp val)
    (let ((name (intern (format nil "~a-MAP" (symbol-name mode))
                        (find-package :ymacs-elisp))))
      (setf (symbol-value name) (elisp/make-keymap))
      (let ((map (symbol-value name))
            (bindings (if (consp (car val)) val (list val))))
        (dolist (b bindings)
          (elisp/define-key map (car b) (cdr b))))
      name)))

;;; --- variable definitions --------------------------------------------------

(defmacro elisp/defvar-local (name &optional value doc)
  (declare (ignore doc))
  `(progn (cl:defvar ,name ,value)
          (ymacs::elisp-register-buffer-local ',name)))

(defmacro elisp/defconst (name value &optional doc)
  ;; Elisp defconst (re)sets unconditionally, unlike defvar.
  (declare (ignore doc))
  `(progn (cl:defvar ,name) (setq ,name ,value) ',name))

(defmacro elisp/defsubst (name args &rest body)
  ;; Elisp defsubst = defun + inline advice for the byte compiler; the
  ;; interpreter behavior is plain defun, and the interpreter is what
  ;; this layer ships.
  `(cl:defun ,name ,args ,@body))

(defmacro elisp/cl-defun (name args &rest body)
  `(cl:defun ,name ,args ,@body))

(defmacro elisp/cl-defmacro (name args &rest body)
  `(cl:defmacro ,name ,args ,@body))

(defmacro elisp/cl-defsubst (name args &rest body)
  `(cl:defun ,name ,args ,@body))

;;; --- generic functions -----------------------------------------------------

(defmacro elisp/cl-defgeneric (name args &rest options)
  ;; Elisp allows a bare doc string before the options; CL wants it as a
  ;; (:documentation …) option.
  (multiple-value-bind (doc rest-options)
      (if (and options (stringp (first options)))
          (values (first options) (rest options))
          (values nil options))
    `(cl:defgeneric ,name ,args
       ,@(when doc `((:documentation ,doc)))
       ,@rest-options)))

(defmacro elisp/cl-defmethod (name &rest rest)
  ;; (cl-defmethod NAME [:before|:after|:around|*] ARGS body…); Elisp's
  ;; `*' qualifier has no CL counterpart and is dropped.
  (let ((qualifier (when (and rest (or (keywordp (first rest))
                                       (eq (first rest) '*)))
                     (pop rest))))
    `(cl:defmethod ,name
       ,@(when (and qualifier (not (eq qualifier '*))) (list qualifier))
       ,@rest)))

;;; --- faces, groups, errors --------------------------------------------------

(defmacro elisp/defface (face spec &optional doc &rest args)
  ;; The spec is data for the display engine, never evaluated at load.
  (declare (ignore doc args))
  `(ymacs::elisp-register-face ',face ',spec))

(defmacro elisp/defgroup (name members &optional doc &rest args)
  (declare (ignore members doc args))
  `(ymacs::elisp-register-group ',name))

(defun elisp/define-error (name message &optional parent)
  (declare (ignore message))
  (setf (gethash name *elisp-error-parents*) parent)
  name)

;;; --- eval timing ------------------------------------------------------------

;; Interpreted code has no separate compile phase, so Elisp's own
;; interpreter semantics apply: both evaluate their body once, now.
(defmacro elisp/eval-when-compile (&rest body)
  `(progn ,@body))

(defmacro elisp/eval-and-compile (&rest body)
  `(progn ,@body))

(defmacro elisp/declare-function (&rest args)
  ;; Byte-compiler metadata; no runtime effect in Elisp either.
  (declare (ignore args))
  nil)

;;; --- minor modes -------------------------------------------------------------

(defmacro elisp/define-minor-mode (mode doc &rest rest)
  ;; (define-minor-mode MODE DOC [INIT-VALUE LIGHTER KEYMAP] [:kw val]…
  ;;  BODY…) — positional slots first, then keyword options, then body.
  (let ((init nil) (keymap nil) (kws '()))
    (when (and rest (not (keywordp (first rest)))) (setf init (pop rest)))
    (when (and rest (not (keywordp (first rest)))) (pop rest)) ; LIGHTER, unused
    (when (and rest (not (keywordp (first rest)))) (setf keymap (pop rest)))
    (loop while (keywordp (first rest))
          do (push (pop rest) kws) (push (pop rest) kws))
    (let* ((kws (nreverse kws))
           (body rest)
           (init (or (getf kws :init-value) init))
           (keymap (or (getf kws :keymap) keymap)))
      `(progn
         (cl:defvar ,mode ,init)
         (ymacs::elisp-install-mode-keymap ',mode ,keymap)
         (cl:defun ,mode (&optional (arg :unset))
           ,@(when (stringp doc) (list doc))
           (setq ,mode
                 (cond ((member arg '(:unset nil toggle))
                        (not ,mode))
                       ((numberp arg) (plusp arg))
                       (t t)))
           ,@body
           ,mode)))))

;;; --- keymaps ------------------------------------------------------------------

(defmacro elisp/defvar-keymap (name &rest options)
  ;; (defvar-keymap NAME [:doc | :parent | :suppress | :full | :name val]…
  ;;  "KEY" DEF …) — keyword options, then binding pairs.
  (let ((opts '()))
    (loop while (keywordp (first options))
          do (push (pop options) opts) (push (pop options) opts))
    (let* ((opts (nreverse opts))
           (parent (getf opts :parent))
           (pairs (loop for tail on options by #'cddr
                        while (first tail)
                        collect (list (first tail) (second tail)))))
      `(progn
         (cl:defvar ,name (ymacs::elisp/make-keymap))
         ,@(when parent
             `((setf (ymacs::elisp-keymap-parent ,name) ,parent)))
         ,@(mapcar (lambda (p)
                     `(ymacs::elisp/define-key ,name ,(first p) ,(second p)))
                   pairs)
         ',name))))

;;; --- functions the corpus calls by name ----------------------------------------

(defun elisp/defalias (sym def &optional doc)
  (declare (ignore doc))
  (remhash sym *elisp-autoloads*)
  (setf (fdefinition sym)
        (cond ((functionp def) def)
              ((and (symbolp def) (fboundp def)) (fdefinition def))
              (t (error "defalias: ~a does not name a function" def))))
  sym)

(defmacro elisp/autoload (function file &optional type interactive doc)
  (declare (ignore type interactive doc))
  ;; CL's #'sym evaluates to a function object, losing the name; Elisp
  ;; sharp-quote yields the symbol. Unwrap so the autoload lands on the
  ;; symbol where Elisp puts it.
  `(ymacs::elisp-autoload-symbol
    ,(if (and (consp function)
              (eq (first function) 'function)
              (symbolp (second function)))
         `',(second function)
         function)
    ,file))

(defun elisp/define-package (name version summary &optional deps &rest extra)
  (declare (ignore version summary deps extra))
  (pushnew name *installed-packages* :test #'string=)
  name)

;;; --- cl-block family (special operators cannot be aliased) ----------------------

;; cl-lib's cl-block etc are CL special operators in this layer; a special
;; operator name can carry neither a function nor a macro cell to alias, so
;; these re-emit the CL special form instead.
(defmacro elisp/cl-block (name &rest body)
  `(cl:block ,name ,@body))

(defmacro elisp/cl-return-from (name &optional value)
  `(cl:return-from ,name ,value))

(defmacro elisp/cl-tagbody (&rest body)
  `(cl:tagbody ,@body))

(defmacro elisp/cl-progv (symbols values &rest body)
  `(cl:progv ,symbols ,values ,@body))

;;; --- subr-x ---------------------------------------------------------------
;;;;
;;;; The modern-helper macros Emacs moved into subr-x. Implemented for
;;;; real (nested binding with the all-non-nil condition), and the layer
;;;; provides the feature — this is what "the layer ships subr-x" means.

(defun elisp--let-pairs (spec)
  "Normalize an if-let/when-let SPEC: both the flat (var val var val…)
form and the ((var val) (var val)) form, including a single (var val)
pair, become a list of (var value-form) pairs."
  (cond ((null spec) nil)
        ((and (symbolp (first spec)) (rest spec))
         (loop for tail on spec by #'cddr
               collect (list (first tail) (second tail))))
        ((symbolp (first spec)) (list spec))
        (t spec)))

(defmacro elisp/if-let* (bindings then &optional else)
  (let ((pairs (elisp--let-pairs bindings)))
    (labels ((build (ps)
               (if (null ps)
                   `(progn ,then)
                   `(let ((,(first (first ps)) ,(second (first ps))))
                      (if ,(first (first ps))
                          ,(build (rest ps))
                          ,else)))))
      (build pairs))))

(defmacro elisp/when-let* (bindings &rest body)
  `(elisp/if-let* ,bindings (progn ,@body)))

(defmacro elisp/while-let (bindings &rest body)
  (let ((pairs (elisp--let-pairs bindings)))
    (labels ((build (ps)
               (if (null ps)
                   `(progn ,@body)
                   `(let ((,(first (first ps)) ,(second (first ps))))
                      (if ,(first (first ps))
                          ,(build (rest ps))
                          (cl:return))))))
      `(cl:loop ,(build pairs)))))

(defmacro elisp/thread-first (form &rest forms)
  (labels ((th (acc fs)
             (if (null fs)
                 acc
                 (let ((f (first fs)))
                   (th (if (consp f)
                           `(,(first f) ,acc ,@(rest f))
                           `(,f ,acc))
                       (rest fs))))))
    (th form forms)))

(defmacro elisp/thread-last (form &rest forms)
  (labels ((th (acc fs)
             (if (null fs)
                 acc
                 (let ((f (first fs)))
                   (th (if (consp f)
                           `(,@f ,acc)
                           `(,f ,acc))
                       (rest fs))))))
    (th form forms)))

(defmacro elisp/thread-as (form var &rest body)
  `(let ((,var ,form)) ,@body))

(defmacro elisp/with-eval-after-load (file &rest body)
  ;; Elisp defers BODY until FILE's feature is loaded; when the feature
  ;; is already present the body runs now, otherwise it is registered
  ;; (and in a one-shot load, honestly, never fires).
  `(ymacs::elisp-run-after-load ',(if (and (consp file) (eq (first file) 'quote))
                                      (second file)
                                      file)
                                (lambda () ,@body)))

(defun elisp-run-after-load (feature thunk)
  (if (or (member feature *elisp-features*)
          (and (boundp '*measure-features*) *measure-features*
               (member (string-downcase (princ-to-string feature))
                       *measure-features* :test #'string=)))
      (funcall thunk)
      nil))

(defmacro elisp/define-globalized-minor-mode (name mode turn-on &rest body)
  (declare (ignore mode body))
  `(progn
     (cl:defvar ,name nil)
     (cl:defun ,name (&optional (arg :unset))
       (setq ,name
             (cond ((member arg '(:unset nil toggle)) (not ,name))
                   ((numberp arg) (plusp arg))
                   (t t)))
       (when ,name (funcall (fdefinition ',turn-on)))
       ,name)))

;;; --- small runtime functions the histogram surfaced -------------------------

(defun elisp/ignore (&rest args)
  (declare (ignore args))
  nil)

(defun elisp/concat (&rest seqs)
  (apply #'concatenate
         'string
         (mapcar (lambda (s)
                   (typecase s
                     (string s)
                     (symbol (symbol-name s))
                     (number (format nil "~a" s))
                     (character (string s))
                     (t (error "concat: cannot concatenate ~a" s))))
                 seqs)))

(defun elisp/mapconcat (fn seq sep)
  (let ((parts (mapcar fn seq)))
    (if (null parts) ""
        (apply #'elisp/concat
               (cons (first parts)
                     (loop for p in (rest parts)
                           collect sep
                           collect p))))))

(defun elisp/put (sym prop value)
  (setf (get sym prop) value))

(defun elisp/fset (sym def)
  (remhash sym *elisp-autoloads*)
  (setf (fdefinition sym)
        (cond ((functionp def) def)
              ((and (symbolp def) (fboundp def)) (fdefinition def))
              (t (error "fset: ~a does not name a function" def))))
  sym)

(defun elisp/advice-add (symbol where advice &rest props)
  (declare (ignore props))
  ;; before / after / around with Elisp's calling conventions (an around
  ;; advice receives the original function as its first argument); other
  ;; advice classes are an honest error, not a silent pretend.
  (let ((base (if (fboundp symbol)
                  (fdefinition symbol)
                  (error "advice-add: ~a has no function to advise" symbol)))
        (a advice))
    (setf (fdefinition symbol)
          (ecase where
            (:before (lambda (&rest args) (apply a args) (apply base args)))
            (:after  (lambda (&rest args) (apply base args) (apply a args)))
            (:around (lambda (&rest args) (apply a (cons base args))))))
    symbol))

(defun elisp/define-obsolete-function-alias (obsolete current &optional when doc)
  (declare (ignore when doc))
  (elisp/defalias obsolete current))

(defun elisp/define-obsolete-variable-alias (obsolete current &optional when doc)
  (declare (ignore when doc))
  (when (boundp current) (set obsolete (symbol-value current)))
  obsolete)


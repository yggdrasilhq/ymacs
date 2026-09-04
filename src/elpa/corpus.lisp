;;;; corpus.lisp --- step 8: ELPA compat depth measured on a public corpus
;;;;
;;;; docs/spec-primitives.md §5 step 8. The corpus is the blessed modern
;;;; helper stack, vendored verbatim from GNU ELPA (the pin and provenance
;;;; live in vendor/elpa-corpus/README.md). Depth ladder, honest:
;;;;   0 READ    — the Elisp reader cannot read the file whole
;;;;   1 LOAD    — reads, but some forms fail to evaluate (missing
;;;;               primitives, unmet features, load-time errors)
;;;;   2 PROVIDE — every form evaluated and the file's own provide ran
;;;; The evaluator is the shipped compat layer (src/elpa/compat.lisp)
;;;; bound under its Elisp names, never a measurement-friendly fake:
;;;; what fails, fails into the report. The only measurement machinery
;;;; beyond the compat layer is require resolution against the vendored
;;;; corpus (package.el semantics: a dependency loads from the archive)
;;;; and provide tracking. A provide is credited to THIS file only when
;;;; the file itself has a top-level (provide …) form and everything
;;;; evaluated — a dependency's provide never inflates the parent.

(in-package #:ymacs)

(defparameter *corpus-packages*
  '("seq" "compat" "map" "dash" "use-package" "cape" "corfu" "consult"
    "marginalia" "orderless" "tempel" "vertico")
  "Measurement order: foundation libraries first, so require pulls a
   dependency from its own vendored slot instead of mid-corpus surprise.")

(defun corpus-root ()
  (or (probe-file "vendor/elpa-corpus/")
      (merge-pathnames "../vendor/elpa-corpus/"
                       (asdf:system-source-directory :ymacs))))

(defun corpus-repo-root ()
  (merge-pathnames (make-pathname :directory '(:relative :up :up))
                   (corpus-root)))

(defun corpus-package-dir (pkg)
  "…/vendor/elpa-corpus/<pkg>-<ver>/<pkg>-<ver>/ — GNU ELPA tars extract
   one inner directory of the same name; the version is part of the pin."
  (or (first (directory (merge-pathnames (format nil "~a-*/*/" pkg)
                                         (corpus-root))))
      (error "corpus package dir missing: ~a" pkg)))

(defun corpus-el-files (pkg)
  (sort (directory (merge-pathnames "*.el" (corpus-package-dir pkg)))
        #'string< :key #'namestring))

(defun corpus-path-package (path)
  (let ((s (namestring path)))
    (or (find-if (lambda (pkg)
                   (search (concatenate 'string "/" pkg "-") s))
                 *corpus-packages*)
        "unknown")))

(defun find-corpus-file (feature)
  (dolist (pkg *corpus-packages*)
    (dolist (f (corpus-el-files pkg))
      (when (string= (pathname-name f) feature)
        (return-from find-corpus-file f)))))

;;; --- the Elisp-name environment over the shipped compat layer ------------

(defparameter *measure-fn-bindings*
  '((add-hook elisp/add-hook) (remove-hook elisp/remove-hook)
    (run-hooks elisp/run-hooks) (make-keymap elisp/make-keymap)
    (define-key elisp/define-key) (global-set-key elisp/global-set-key)
    (lookup-key elisp/lookup-key) (featurep elisp/featurep)
    (current-buffer elisp/current-buffer) (insert elisp/insert)
    (delete-region elisp/delete-region) (buffer-string elisp/buffer-string)
    (point elisp/point) (goto-char elisp/goto-char)
    (defalias elisp/defalias) (define-package elisp/define-package)
    (define-error elisp/define-error) (fset elisp/fset) (put elisp/put)
    (concat elisp/concat) (mapconcat elisp/mapconcat)
    (ignore elisp/ignore) (advice-add elisp/advice-add)
    (define-obsolete-function-alias elisp/define-obsolete-function-alias)
    (define-obsolete-variable-alias elisp/define-obsolete-variable-alias)))

(defparameter *measure-macro-bindings*
  '((defcustom elisp/defcustom) (use-package ymacs-use-package)
    ;; the definition-form family (defmacros.lisp) — the 2026-09-04
    ;; measurement showed the corpus hanging on exactly these
    (defvar-local elisp/defvar-local) (defconst elisp/defconst)
    (defsubst elisp/defsubst) (defface elisp/defface) (defgroup elisp/defgroup)
    (cl-defun elisp/cl-defun) (cl-defmacro elisp/cl-defmacro)
    (cl-defsubst elisp/cl-defsubst) (cl-defgeneric elisp/cl-defgeneric)
    (cl-defmethod elisp/cl-defmethod) (cl-block elisp/cl-block)
    (cl-return-from elisp/cl-return-from) (cl-tagbody elisp/cl-tagbody)
    (cl-progv elisp/cl-progv)
    (define-minor-mode elisp/define-minor-mode)
    (defvar-keymap elisp/defvar-keymap)
    (autoload elisp/autoload)
    (eval-when-compile elisp/eval-when-compile)
    (eval-and-compile elisp/eval-and-compile)
    (declare-function elisp/declare-function)
    (if-let elisp/if-let*) (if-let* elisp/if-let*)
    (when-let elisp/when-let*) (when-let* elisp/when-let*)
    (while-let elisp/while-let)
    (thread-first elisp/thread-first) (thread-last elisp/thread-last)
    (thread-as elisp/thread-as)
    (with-eval-after-load elisp/with-eval-after-load)
    (define-globalized-minor-mode elisp/define-globalized-minor-mode)))

(defparameter *measure-cl-aliases*
  '((cl-incf incf) (cl-decf decf) (cl-shiftf shiftf) (cl-rotatef rotatef)
    (cl-psetf psetf) (cl-pushnew pushnew) (cl-remf remf)
    (cl-loop loop) (cl-return return)
    (cl-multiple-value-bind multiple-value-bind)
    (cl-multiple-value-setq multiple-value-setq)
    (cl-destructuring-bind destructuring-bind)
    (cl-case case) (cl-ccase ccase) (cl-ecase ecase)
    (cl-typecase typecase) (cl-etypecase etypecase) (cl-ctypecase ctypecase)
    (cl-assert assert) (cl-check-type check-type)
    (cl-ignore-errors ignore-errors)
    (cl-first first) (cl-second second) (cl-third third) (cl-fourth fourth)
    (cl-rest rest) (cl-list* list*) (cl-nthcdr nthcdr)
    (cl-member member) (cl-assoc assoc) (cl-rassoc rassoc)
    (cl-find find) (cl-find-if find-if) (cl-find-if-not find-if-not)
    (cl-position position) (cl-count count) (cl-search search)
    (cl-mismatch mismatch) (cl-substitute substitute)
    (cl-remove remove) (cl-remove-if remove-if) (cl-remove-if-not remove-if-not)
    (cl-delete delete) (cl-delete-if delete-if) (cl-delete-if-not delete-if-not)
    (cl-subseq subseq) (cl-sort sort) (cl-stable-sort stable-sort)
    (cl-merge merge) (cl-reduce reduce)
    (cl-union union) (cl-intersection intersection)
    (cl-set-difference set-difference) (cl-subsetp subsetp)
    (cl-adjoin adjoin) (cl-remove-duplicates remove-duplicates)
    (cl-mapcar mapcar) (cl-mapc mapc) (cl-mapcan mapcan) (cl-maplist maplist)
    (cl-some some) (cl-every every) (cl-notany notany) (cl-notevery notevery)
    (cl-gensym gensym) (cl-parse-integer parse-integer)
    (cl-digit-char-p digit-char-p) (cl-concatenate concatenate)
    (cl-plusp plusp) (cl-minusp minusp) (cl-zerop zerop)
    (cl-evenp evenp) (cl-oddp oddp) (cl-min min) (cl-max max))
  "cl-lib names ARE CL here — CL is ymacs's implementation of cl-lib —
   so cl-incf is cl:incf and cl-loop is cl:loop. Aliases, not fakes.")

(defparameter *measure-features* nil)

(defun measure-elisp-symbol (name el)
  "Intern NAME in the Elisp package, shadowing CL inheritance.
   USE-PACKAGE etc come in from COMMON-LISP through :use #:cl — setting a
   function or macro cell on those is a package-lock violation in SBCL."
  (multiple-value-bind (sym status) (find-symbol name el)
    (when (and sym (eq status :inherited))
      (shadow (list name) el))
    (intern name el)))

(defun measure-bind-cl-aliases (el)
  "Bind cl-lib names onto their CL implementations in the Elisp package."
  (dolist (pair *measure-cl-aliases*)
    (let ((alias (measure-elisp-symbol (string (first pair)) el))
          (target (find-symbol (string (second pair)) :cl)))
      (when target
        (cond ((macro-function target)
               (setf (macro-function alias) (macro-function target)))
              ((fboundp target)
               (setf (fdefinition alias) (fdefinition target))))))))

(defun measure-install-env ()
  "Bind the shipped compat layer under its Elisp names in :ymacs-elisp."
  (let ((el (find-package :ymacs-elisp)))
    (dolist (b *measure-fn-bindings*)
      (let ((sym (find-symbol (string (second b)) (find-package :ymacs))))
        (when sym
          (setf (fdefinition (measure-elisp-symbol (string (first b)) el))
                (fdefinition sym)))))
    (dolist (b *measure-macro-bindings*)
      (let ((sym (find-symbol (string (second b)) (find-package :ymacs))))
        (when (and sym (macro-function sym))
          (setf (macro-function (measure-elisp-symbol (string (first b)) el))
                (macro-function sym)))))
    (measure-bind-cl-aliases el)
    ;; cl-lib is provided by the shipped image (CL itself is the cl-lib
    ;; implementation — the same stance modern-helpers.lisp blesses), and
    ;; subr-x by defmacros.lisp's macro family. Canonical-name push: the
    ;; require lookup downcases the symbol name, prin1 would package-
    ;; qualify a :ymacs symbol and never match.
    (pushnew "cl-lib" *measure-features* :test #'string=)
    (pushnew "subr-x" *measure-features* :test #'string=)
    ;; version-bound variables the corpus branches on
    (setf (symbol-value (measure-elisp-symbol "EMACS-MAJOR-VERSION" el)) 30
          (symbol-value (measure-elisp-symbol "EMACS-MINOR-VERSION" el)) 1)
    (setf *autoload-file-loader*
          (lambda (file)
            (let ((path (or (and (probe-file file) file)
                            (find-corpus-file (pathname-name file)))))
              (unless path
                (error 'corpus-unmet-dependency :feature file))
              (corpus-load-file path))))
    (setf (fdefinition (measure-elisp-symbol "PROVIDE" el)) #'corpus-provide)
    (setf (fdefinition (measure-elisp-symbol "REQUIRE" el)) #'corpus-require)))

(defun corpus-provide (feature)
  (pushnew (string-downcase (prin1-to-string feature))
           *measure-features* :test #'string=)
  feature)

(define-condition corpus-unmet-dependency (error)
  ((feature :initarg :feature :reader corpus-unmet-dependency-feature)))

(defun corpus-require (feature &optional filename noerror)
  (declare (ignore filename noerror))
  (let ((name (string-downcase (prin1-to-string feature))))
    (unless (member name *measure-features* :test #'string=)
      (let ((path (find-corpus-file name)))
        (unless path
          (error 'corpus-unmet-dependency :feature name))
        (corpus-load-file path :origin :dependency)
        (unless (member name *measure-features* :test #'string=)
          (error 'corpus-unmet-dependency :feature name)))))
  t)

;;; --- the measurement ------------------------------------------------------

(defstruct corpus-result
  package file depth forms evaluated missing errors provided-p origin)

(defparameter *measure-results* nil)
(defparameter *measure-by-path* (make-hash-table :test 'equal))
(defparameter *measure-in-flight* nil)

(defun measure-reset ()
  "Reset the bookkeeping AND the Elisp package itself: eval defuns and
   defvars from run N must not answer run N+1's missing-primitive probes
   (two runs of the same corpus once differed 797 vs 814 because of it)."
  (setf *measure-features* nil
        *measure-results* nil
        *measure-by-path* (make-hash-table :test 'equal)
        *measure-in-flight* nil)
  (setf *elisp-faces* (make-hash-table :test 'equal)
        *elisp-custom-groups* (make-hash-table :test 'equal)
        *elisp-buffer-locals* (make-hash-table :test 'equal)
        *elisp-error-parents* (make-hash-table :test 'equal)
        *elisp-autoloads* (make-hash-table :test 'equal)
        *autoload-file-loader* nil)
  (let ((el (find-package :ymacs-elisp)))
    (do-symbols (s el)
      (when (eq (symbol-package s) el)
        (when (fboundp s) (fmakunbound s))
        (when (macro-function s) (setf (macro-function s) nil))
        (when (boundp s) (ignore-errors (makunbound s)))))))

(defun measure-eval (form)
  "EVAL with SBCL's evaluator in interpret mode when available.
   SBCL's EVAL compiles by default — measuring 76 real packages under
   the compiler blew the dynamic space. Resolved through FIND-SYMBOL so
   the file also reads on ECL, where SB-EXT does not exist."
  (let ((sym (and (find-package :sb-ext)
                  (find-symbol (string :*evaluator-mode*) :sb-ext))))
    (if (and sym (boundp sym))
        (progv (list sym) (list :interpret) (eval form))
        (eval form))))

(defun measure-form (form)
  "Evaluate one form; NIL on success, else (:missing X) / (:error note)."
  (handler-case
      (progn (measure-eval form) nil)
    (corpus-unmet-dependency (e)
      (list :missing (format nil "feature:~a" (corpus-unmet-dependency-feature e))))
    (undefined-function (e) (list :missing (string (cell-error-name e))))
    (unbound-variable (e) (list :missing (string (cell-error-name e))))
    (error (e)
      (let ((msg (format nil "~a" e)))
        (list :error (subseq msg 0 (min 160 (length msg))))))))

(defun top-level-provide-p (forms)
  "Does FORMS contain a top-level (provide …)? Compared by name in the
   Elisp package — corpus forms are read in :ymacs-elisp, so YMACS:PROVIDE
   is a different symbol and a plain eq against it never fires."
  (some (lambda (f)
          (and (consp f)
               (let ((op (first f)))
                 (and (symbolp op)
                      (eq (symbol-package op) (find-package :ymacs-elisp))
                      (string= (symbol-name op) "PROVIDE")))))
        forms))

(defun corpus-load-file (path &key (origin :top-level))
  "Measure one corpus file once, honestly. Deduped by absolute namestring;
   a file mid-require signals circular-require instead of recursing."
  (let* ((key (namestring path))
         (cached (gethash key *measure-by-path*)))
    (when cached
      (return-from corpus-load-file cached))
    (when (member key *measure-in-flight* :test #'string=)
      (error 'corpus-unmet-dependency
             :feature (format nil "~a (circular require)" (pathname-name path))))
    (let ((*measure-in-flight* (cons key *measure-in-flight*)))
      (multiple-value-bind (forms failure) (read-elisp-forms path)
        (let ((missing '())
              (errors '())
              (evaluated 0))
          (when (null failure)
            (let ((*package* (find-package :ymacs-elisp)))
              (dolist (form forms)
                (let ((note (measure-form form)))
                  (cond ((null note) (incf evaluated))
                        ((eq (car note) :missing)
                         (push (second note) missing))
                        (t (push (second note) errors)))))))
          (let* ((complete (= evaluated (length forms)))
                 (provides (top-level-provide-p forms))
                 (result
                  (make-corpus-result
                   :package (corpus-path-package path)
                   :file (enough-namestring path (corpus-repo-root))
                   :depth (cond (failure 0)
                                ((and complete provides) 2)
                                (t 1))
                   :forms (length forms)
                   :evaluated evaluated
                   :missing (nreverse missing)
                   :errors (nreverse (if failure (cons failure errors) errors))
                   :provided-p (and complete provides)
                   :origin origin)))
            (setf (gethash key *measure-by-path*) result)
            (push result *measure-results*)
            result))))))

(defun measure-corpus ()
  "Measure every corpus file once; returns (values results summary)."
  (measure-reset)
  (measure-install-env)
  (dolist (pkg *corpus-packages*)
    (dolist (f (corpus-el-files pkg))
      (corpus-load-file f))
    ;; a full sweep per package keeps even the big suites (corfu, consult)
    ;; flat in memory — measurement is one-shot, dead forms are dead weight
    (when (find-package :sb-ext)
      (funcall (find-symbol "GC" :sb-ext) :full t)))
  (let ((summary (corpus-summary)))
    (print-corpus-summary summary)
    (values (reverse *measure-results*) summary)))

;;; --- aggregation and reports ----------------------------------------------

(defun corpus-summary ()
  (let ((results (reverse *measure-results*)))
    (labels ((pkg-results (pkg)
               (remove-if-not (lambda (r) (string= pkg (corpus-result-package r)))
                              results)))
      (list
       :packages-total (length *corpus-packages*)
       :files (length results)
       :read (count-if (lambda (r) (/= 0 (corpus-result-depth r))) results)
       :provided (count-if (lambda (r) (= 2 (corpus-result-depth r))) results)
       :forms (reduce #'+ results :key #'corpus-result-forms :initial-value 0)
       :forms-evaluated (reduce #'+ results :key #'corpus-result-evaluated
                                :initial-value 0)
       :per-package (loop for pkg in *corpus-packages*
                          collect (let ((rs (pkg-results pkg)))
                                    (list pkg
                                          (length rs)
                                          (count-if (lambda (r)
                                                      (= 2 (corpus-result-depth r)))
                                                    rs)
                                          (reduce #'+ rs :key #'corpus-result-forms
                                                  :initial-value 0)
                                          (reduce #'+ rs :key #'corpus-result-evaluated
                                                  :initial-value 0))))
       :top-missing (corpus-histogram
                     (lambda (r) (corpus-result-missing r)) results 25)
       :unmet-features (corpus-histogram
                        (lambda (r)
                          (loop for m in (corpus-result-missing r)
                                when (and (> (length m) 8)
                                          (string= "feature:" m :end2 8))
                                  collect (subseq m 8)))
                        results nil)))))

(defun corpus-histogram (extract results limit)
  (let ((h (make-hash-table :test 'equal)))
    (dolist (r results)
      (dolist (m (funcall extract r))
        (incf (gethash m h 0))))
    (let ((pairs nil))
      (maphash (lambda (k v) (push (cons k v) pairs)) h)
      (let ((sorted (sort pairs #'> :key #'cdr)))
        (if limit
            (subseq sorted 0 (min limit (length sorted)))
            sorted)))))

(defun corpus-now-string ()
  (multiple-value-bind (s m h d mo y)
      (get-decoded-time)
    (declare (ignore s))
    (format nil "~4d-~2,'0d-~2,'0d ~2,'0d:~2,'0d" y mo d h m)))

(defun print-corpus-summary (summary)
  (format t "ELPA corpus measurement (~a) — ~a packages, ~a files~%"
          (corpus-now-string)
          (getf summary :packages-total) (getf summary :files))
  (format t "  READ (depth >= 1):    ~a files~%" (getf summary :read))
  (format t "  PROVIDE (depth 2):    ~a files~%" (getf summary :provided))
  (format t "  forms evaluated:      ~a / ~a~%"
          (getf summary :forms-evaluated) (getf summary :forms))
  (format t "  unmet features: ~{~(~a~)(~a)~^ ~}~%"
          (apply #'append
                 (mapcar (lambda (p) (list (car p) (cdr p)))
                         (getf summary :unmet-features))))
  (format t "  top missing: ~{~(~a~)(~a)~^ ~}~%"
          (apply #'append
                 (mapcar (lambda (p) (list (car p) (cdr p)))
                         (getf summary :top-missing))))
  (dolist (pp (getf summary :per-package))
    (format t "  ~(~a~): files ~a, depth-2 ~a, forms ~a/~a~%"
            (first pp) (second pp) (third pp) (fifth pp) (fourth pp)))
  (force-output))

(defun corpus-json-string (s)
  (with-output-to-string (out)
    (loop for ch across s
          do (cond ((char= ch #\\) (write-string "\\\\" out))
                   ((char= ch #\") (write-string "\\\"" out))
                   ((char= ch #\newline) (write-string "\\n" out))
                   (t (write-char ch out))))))

(defun write-corpus-json (summary path)
  (with-open-file (out path :direction :output :if-exists :supersede
                            :if-does-not-exist :create :external-format :utf-8)
    (format out "{~%")
    (format out "  \"generated\": \"~a\",~%" (corpus-now-string))
    (format out "  \"packages_total\": ~a,~%" (getf summary :packages-total))
    (format out "  \"files\": ~a,~%" (getf summary :files))
    (format out "  \"files_read\": ~a,~%" (getf summary :read))
    (format out "  \"files_provided\": ~a,~%" (getf summary :provided))
    (format out "  \"forms\": ~a,~%" (getf summary :forms))
    (format out "  \"forms_evaluated\": ~a,~%" (getf summary :forms-evaluated))
    (format out "  \"unmet_features\": [~{[\"~a\", ~a]~^, ~}],~%"
            (apply #'append
                   (mapcar (lambda (p)
                             (list (corpus-json-string (car p)) (cdr p)))
                           (getf summary :unmet-features))))
    (format out "  \"top_missing\": [~{[\"~a\", ~a]~^, ~}],~%"
            (apply #'append
                   (mapcar (lambda (p)
                             (list (corpus-json-string (car p)) (cdr p)))
                           (getf summary :top-missing))))
    (format out "  \"packages\": [~%")
    (let ((pps (getf summary :per-package)))
      (dolist (pp pps)
        (format out "    {\"name\": \"~a\", \"files\": ~a, \"depth2\": ~a, ~
                          \"forms\": ~a, \"forms_evaluated\": ~a}~a~%"
                (first pp) (second pp) (third pp) (fourth pp) (fifth pp)
                (if (eq pp (first (last pps))) "" ","))))
    (format out "  ]~%}~%"))
  path)

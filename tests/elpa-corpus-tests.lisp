;;;; elpa-corpus-tests.lisp --- contract tests for the step-8 instrument
;;;;
;;;; The Elisp reader's token divergences, the corpus pin, and the honest
;;;; depth ladder (0 READ / 1 LOAD / 2 PROVIDE). The corpus NUMBERS are
;;;; never asserted — depth is allowed to be whatever the truth is; what
;;;; must hold is that the instrument measures every file and reports
;;;; structure.
;;;;
;;;; Run: sbcl --load tests/run-tests.lisp
;;;; Plain CL, no dependencies — CI installs bare SBCL only.

(in-package #:ymacs)

(defun ec-sandbox ()
  "Disk-backed sandbox under home — never /tmp (sidebar-tests pattern)."
  (ensure-directories-exist
   (merge-pathnames ".yggterm/scratchpad/ymacs-ec/" (user-homedir-pathname))))

(defun ec-write (name text)
  (let ((path (merge-pathnames name (ec-sandbox))))
    (with-open-file (s path :direction :output :if-exists :supersede
                            :external-format :utf-8)
      (write-string text s))
    path))

(defun ec-eval-text (text)
  "Fresh measure env, then evaluate TEXT's forms in the Elisp package.
Returns the failure notes — a null list means every form evaluated."
  (measure-reset)
  (measure-install-env)
  (let ((*package* (find-package :ymacs-elisp)))
    (remove-if #'null (mapcar #'measure-form (read-elisp-string text)))))

(defun run-corpus-tests ()
  (setf *test-pass* 0 *test-fail* 0)
  (format t "ymacs elpa corpus tests~%")

  (test "reader: ?c character literals read as integers"
    ;; the file is ONE list, so forms = ((97 1 32 127))
    (assert-eq* '((97 1 32 127))
                (read-elisp-string "(?a ?\\C-a ?\\s ?\\d)")))

  (test "reader: lenient Elisp string escapes (CL would reject \\()"
    (assert-eq* (list "(") (read-elisp-string "\"\\(\"")))

  (test "reader: vectors and backquote read"
    (assert-eq* t (vectorp (first (read-elisp-string "#(1 2 3)"))))
    (multiple-value-bind (forms failure) (read-elisp-string "`(a ,b ,@c)")
      (assert-eq* nil failure)
      (assert-eq* 1 (length forms))))

  (test "reader: [a b c] vector literal, splices included"
    (let ((v (first (read-elisp-string "[1 two \"three\"]"))))
      (assert-eq* t (vectorp v))
      (assert-eq* 3 (length v)))
    (multiple-value-bind (forms failure) (read-elisp-string "`[indicator ,(if t 'x)]")
      (assert-eq* nil failure)
      (assert-eq* 1 (length forms))))

  (test "reader: package-marker tokens resolve consistently (package shim)"
    ;; Elisp has no packages; the shim's contract is that the same token
    ;; always reads to the same symbol, in a stable home package
    (let ((a (first (read-elisp-string "use-package-normalize/:keyword")))
          (b (first (read-elisp-string "use-package-normalize/:keyword"))))
      (assert-eq* t (eq a b))
      (assert-eq* "USE-PACKAGE-NORMALIZE/" (package-name (symbol-package a))))
    (let ((a (first (read-elisp-string "dash-expand:&hash")))
          (b (first (read-elisp-string "dash-expand:&hash"))))
      (assert-eq* t (eq a b))
      (assert-eq* "DASH-EXPAND" (package-name (symbol-package a)))))

  (test "reader: token-initial colon reads keywords"
    (assert-eq* :background (first (read-elisp-string ":background"))))

  (test "reader: char modifier escapes compose (?\\A-\\0 family)"
    (assert-eq* 65 (first (read-elisp-string "?A")))
    ;; \A- composes with the escape that follows: alt+NUL in this reader's bits
    (let ((v (first (read-elisp-string "((?A . ?\\A-\\0))"))))
      (assert-eq* 65 (first (first v)))
      (assert-eq* #x8000000 (cdr (first v))))
    (assert-eq* 32 (first (read-elisp-string "?\\s")))
    (assert-eq* t (> (first (read-elisp-string "?\\s-\\C-a")) #x20000000)))

  (test "reader: unterminated string fails honestly with no completed forms"
    ;; the half-read list is abandoned by the reader — nothing completes
    (multiple-value-bind (forms failure) (read-elisp-string "(a \"unterminated")
      (assert-eq* t (not (null failure)))
      (assert-eq* 0 (length forms))))

  (test "corpus pin: 12 packages, 70+ elisp files vendored"
    (assert-eq* 12 (length *corpus-packages*))
    (let ((n (reduce #'+ (mapcar (lambda (p) (length (corpus-el-files p)))
                                 *corpus-packages*))))
      (assert-eq* t (>= n 70))))

  (test "env: compat layer bound under Elisp names, provide/require instrumented"
    (measure-reset)
    (measure-install-env)
    ;; fboundp returns a generalized boolean — may be the function itself
    (assert-eq* t (not (null (fboundp (intern "ADD-HOOK" :ymacs-elisp)))))
    (assert-eq* t (not (null (fboundp (intern "REQUIRE" :ymacs-elisp)))))
    (assert-eq* t (not (null (macro-function (intern "USE-PACKAGE"
                                                     :ymacs-elisp))))))

  ;; definition-macro family (defmacros.lisp): the corpus hung on these
  (test "defmacs: family bound under Elisp names after install"
    (measure-reset)
    (measure-install-env)
    (dolist (m '("DEFVAR-LOCAL" "DEFCONST" "DEFSUBST" "DEFFACE" "DEFGROUP"
                 "CL-DEFUN" "CL-DEFMACRO" "CL-DEFGENERIC" "CL-DEFMETHOD"
                 "CL-BLOCK" "CL-RETURN-FROM" "CL-TAGBODY" "CL-PROGV"
                 "DEFINE-MINOR-MODE" "DEFVAR-KEYMAP" "EVAL-WHEN-COMPILE"
                 "EVAL-AND-COMPILE" "DECLARE-FUNCTION" "AUTOLOAD"))
      (assert-eq* t (not (null (macro-function (intern m :ymacs-elisp))))))
    (dolist (f '("DEFALIAS" "DEFINE-PACKAGE" "DEFINE-ERROR"))
      (assert-eq* t (not (null (fboundp (intern f :ymacs-elisp)))))))

  (test "defmacs: defvar-local defines and registers buffer-locality"
    (assert-eq* nil (ec-eval-text "(defvar-local ec-dvl 7)"))
    (let ((s (intern "EC-DVL" :ymacs-elisp)))
      (assert-eq* 7 (symbol-value s))
      (assert-eq* t (gethash s *elisp-buffer-locals*))))

  (test "defmacs: defconst sets the value"
    (assert-eq* nil (ec-eval-text "(defconst ec-dc 3)"))
    (assert-eq* 3 (symbol-value (intern "EC-DC" :ymacs-elisp))))

  (test "defmacs: defface registers without evaluating its spec"
    (assert-eq* nil
                (ec-eval-text "(defface ec-face '((junk-not-a-fn 1)) \"d\" :group 'ec)"))
    (assert-eq* t (not (null (gethash (intern "EC-FACE" :ymacs-elisp)
                                      *elisp-faces*)))))

  (test "defmacs: cl-defgeneric/cl-defmethod dispatch"
    (assert-eq* nil
                (ec-eval-text "(cl-defgeneric ec-mg (x) \"doc\")
(cl-defmethod ec-mg ((x string)) \"str\")
(cl-defmethod ec-mg ((x number)) \"num\")
(cl-defmethod ec-mg (x) \"any\")"))
    (let ((f (fdefinition (intern "EC-MG" :ymacs-elisp))))
      (assert-eq* "str" (funcall f "a"))
      (assert-eq* "num" (funcall f 1))
      (assert-eq* "any" (funcall f 'sym))))

  (test "defmacs: define-minor-mode defines the toggle and runs the body"
    (assert-eq* nil
                (ec-eval-text "(defvar ec-mm-ran nil)
(define-minor-mode ec-mm \"d\" :init-value nil (setq ec-mm-ran t))"))
    (let ((s (intern "EC-MM" :ymacs-elisp)))
      (assert-eq* nil (symbol-value s))
      (funcall (fdefinition s) 1)
      (assert-eq* t (symbol-value s))
      (assert-eq* t (symbol-value (intern "EC-MM-RAN" :ymacs-elisp)))
      (funcall (fdefinition s))
      (assert-eq* nil (symbol-value s))))

  (test "defmacs: defvar-keymap builds a real keymap with bindings"
    (assert-eq* nil
                (ec-eval-text "(defun ec-km-cmd () t)
(defvar-keymap ec-km \"a\" #'ec-km-cmd)"))
    (let ((fn (elisp/lookup-key (symbol-value (intern "EC-KM" :ymacs-elisp))
                                "a")))
      (assert-eq* t (not (null fn)))
      (assert-eq* t (funcall fn))))

  (test "defmacs: autoload stub loads on first call, then dispatches"
    (let ((path (ec-write "ec-autoloaded.el"
                          (format nil "(defun ec-autoloaded () :loaded)~%(provide 'ec-autoloaded)"))))
      (assert-eq* nil
                  (ec-eval-text
                   (format nil "(autoload #'ec-autoloaded \"~a\")" (namestring path))))
      (let ((s (intern "EC-AUTOLOADED" :ymacs-elisp)))
        (assert-eq* t (not (null (gethash s *elisp-autoloads*))))
        (assert-eq* :loaded (funcall (fdefinition s)))
        (assert-eq* t (not (null (fboundp s)))))))

  (test "defmacs: declare-function and eval-and-compile evaluate cleanly"
    (assert-eq* nil
                (ec-eval-text "(declare-function ec-unbound \"nowhere\" (x))"))
    (assert-eq* nil (ec-eval-text "(eval-and-compile (defvar ec-eac 5))"))
    (assert-eq* 5 (symbol-value (intern "EC-EAC" :ymacs-elisp))))

  (test "defmacs: define-package and define-error register"
    (assert-eq* nil (ec-eval-text "(define-package \"ec-pkg\" \"1.0\" \"s\")"))
    (assert-eq* t (not (null (member "ec-pkg" *installed-packages* :test #'string=))))
    (assert-eq* nil (ec-eval-text "(define-error 'ec-err \"m\" 'error)"))
    (assert-eq* 'error (gethash (intern "EC-ERR" :ymacs-elisp)
                                *elisp-error-parents*)))

  (test "defmacs: cl-lib aliases resolve to CL"
    (assert-eq* nil
                (ec-eval-text "(defvar ec-ai 5)
(cl-incf ec-ai)"))
    (assert-eq* 6 (symbol-value (intern "EC-AI" :ymacs-elisp))))

  (test "defmacs: cl-lib provided by the shipped image"
    (assert-eq* nil (ec-eval-text "(require 'cl-lib)")))

  (test "defmacs: subr-x let-binding macros bind for real"
    (assert-eq* nil
                (ec-eval-text "(require 'subr-x)
(if-let ((a 1) (b 2)) (setq ec-til :both) (setq ec-til :none))
(if-let ((a 1) (b nil)) (setq ec-til :none) (setq ec-til :short))
(when-let* ((x 5) (y 6)) (setq ec-til (* x y)))"))
    (assert-eq* 30 (symbol-value (intern "EC-TIL" :ymacs-elisp))))

  (test "defmacs: thread macros thread"
    (assert-eq* nil
                (ec-eval-text "(defun ec-th-dub (x) (* 2 x))
(setq ec-thr (thread-first 5 ec-th-dub (- 3)))
(setq ec-thl (thread-last (list 1 2) (mapcar #'1+)))"))
    (assert-eq* 7 (symbol-value (intern "EC-THR" :ymacs-elisp)))
    (assert-eq* '(2 3) (symbol-value (intern "EC-THL" :ymacs-elisp))))

  (test "defmacs: mapconcat maps and joins"
    (assert-eq* nil
                (ec-eval-text "(setq ec-mc (mapconcat #'1+ (list 1 2 3) \",\"))"))
    (assert-eq* "2,3,4" (symbol-value (intern "EC-MC" :ymacs-elisp))))

  (test "ladder: an evaluable file with a provide is depth 2"
    (measure-reset)
    (measure-install-env)
    (let ((r (corpus-load-file
              (ec-write "ec-smoke.el"
                        (format nil "(defvar ec-smoke-var 1)~%(provide 'ec-smoke)~%")))))
      (assert-eq* 2 (corpus-result-depth r))
      (assert-eq* t (corpus-result-provided-p r))))

  (test "ladder: a top-level missing primitive is depth 1 with the gap recorded"
    (measure-reset)
    (measure-install-env)
    (let ((r (corpus-load-file
              (ec-write "ec-broken.el"
                        (format nil "(frobnicate-entirely-unknown-thing 1)~%~
                                     (provide 'ec-broken)~%")))))
      (assert-eq* 1 (corpus-result-depth r))
      (assert-eq* '("FROBNICATE-ENTIRELY-UNKNOWN-THING")
                  (corpus-result-missing r))
      (assert-eq* nil (corpus-result-provided-p r))))

  (test "require of a feature outside the corpus fails honestly"
    (measure-reset)
    (measure-install-env)
    (assert-eq* t
                (handler-case (progn (corpus-require 'ec-no-such-feature) nil)
                  (corpus-unmet-dependency (e) t))))

  (test "measure-corpus measures every corpus file exactly once"
    (multiple-value-bind (results) (measure-corpus)
      (let ((expected (reduce #'+ (mapcar (lambda (p) (length (corpus-el-files p)))
                                          *corpus-packages*))))
        (assert-eq* expected (length results)))
      (dolist (r results)
        (assert-eq* t (not (null (member (corpus-result-depth r) '(0 1 2)))))
        (assert-eq* t (not (null (corpus-result-file r)))))))

  (test "report: JSON structure lands with totals, packages, and gaps"
    (multiple-value-bind (results summary) (measure-corpus)
      (let* ((path (write-corpus-json summary
                                     (merge-pathnames "ec-report.json"
                                                      (ec-sandbox))))
             (text (with-open-file (s path)
                     (with-output-to-string (o)
                       (loop for line = (read-line s nil nil)
                             while line do (write-line line o))))))
        ;; search returns the match index (generalized boolean), not T
        (assert-eq* t (not (null (search "\"files_read\"" text))))
        (assert-eq* t (not (null (search "\"top_missing\"" text))))
        (assert-eq* t (not (null (search "\"packages\"" text))))
        (assert-eq* t (not (null (search (format nil "\"files\": ~a" (length results))
                                         text)))))))

  (format t "~a passed, ~a failed~%" *test-pass* *test-fail*)
  (zerop *test-fail*))

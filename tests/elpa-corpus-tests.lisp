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

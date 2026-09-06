;;;; info-tests.lisp --- the manual is readable by the reader it ships.
;;;; The docs law's litmus: makeinfo output parsed by ymacs's Info mode
;;;; yields the manual's nodes, chapter spine included.
;;;;
;;;; Run: sbcl --load tests/run-tests.lisp
;;;; Plain CL, no dependencies.

(in-package #:ymacs)

(defvar *info-test-pass* 0)
(defvar *info-test-fail* 0)

(defmacro info-test (name &body body)
  `(progn
     (format t "  ~a ..." ,name)
     (handler-case (progn ,@body (incf *info-test-pass*) (format t " ok~%"))
       (error (e) (incf *info-test-fail*) (format t " FAIL: ~a~%" e)))))

(defun info-assert-equal (want got)
  (unless (equal want got)
    (error "expected ~s, got ~s" want got)))

(defun run-info-tests ()
  (let ((*info-test-pass* 0) (*info-test-fail* 0))
    (let ((path (merge-pathnames "docs/emacs-manual/ymacs/ymacs.info"
                                 (truename "."))))
      (info-test "the built manual exists next to its source"
        (info-assert-equal t (and (probe-file path) t)))
      (when (probe-file path)
        (let ((text (read-file-string path)))
          (info-test "the built manual parses into nodes"
            (multiple-value-bind (order nodes) (info-parse text)
              (info-assert-equal t (and (plusp (length order)) t))
              ;; The entry node and the chapter spine, in file order.
              (info-assert-equal "Top" (first order))
              (info-assert-equal "Durable Buffers" (second order))
              (info-assert-equal t (and (gethash "Top" nodes) t))
              (let ((pos (position "The Command Palette" order :test #'string=)))
                (info-assert-equal t (and pos t))
                (let ((chapter (info-node-text (gethash "The Command Palette" nodes))))
                  (info-assert-equal t (and (search "command palette" chapter) t))
                  (info-assert-equal t (and (search "C-g" chapter) t)))))))))
    (format t "ymacs info suite: ~a passed, ~a failed~%"
            *info-test-pass* *info-test-fail*)
    (zerop *info-test-fail*)))

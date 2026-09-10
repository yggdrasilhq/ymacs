;;;; rendering-tests.lisp --- the rendering law holds end to end.
;;;; docs/spec-rendering.md: capable major modes arm a projection, the
;;;; global wrapper defaults it on, the schema emits the markdown widget,
;;;; follow-link routes, and typing drops to raw.
;;;;
;;;; Run: sbcl --load tests/run-tests.lisp

(in-package #:ymacs)

(defvar *rendering-test-pass* 0)
(defvar *rendering-test-fail* 0)

(defmacro rendering-test (name &body body)
  `(progn
     (format t "  ~a ..." ,name)
     (handler-case (progn ,@body (incf *rendering-test-pass*) (format t " ok~%"))
       (error (e) (incf *rendering-test-fail*) (format t " FAIL: ~a~%" e)))))

(defun rendering-assert-equal (want got)
  (unless (equal want got)
    (error "expected ~s, got ~s" want got)))

(defun run-rendering-tests ()
  (let ((*rendering-test-pass* 0) (*rendering-test-fail* 0)
        (*rendered-mode-buffers* (make-hash-table :test 'equal))
        (*global-rendered-mode* t))
    (rendering-test "info-mode declares a rich parser; org-mode too"
      (rendering-assert-equal
       t (and (major-mode-rich-parser (gethash "info-mode" *major-modes*)) t))
      (rendering-assert-equal
       t (and (major-mode-rich-parser (gethash "org-mode" *major-modes*)) t)))
    (rendering-test "set-buffer-major-mode arms the producer and the default"
      (let ((*buffers* (make-hash-table :test 'equal)) (*current-buffer* nil))
        (let ((buf (make-new-buffer "*rt-org*" "")))
          (set-buffer-major-mode buf "org-mode")
          (rendering-assert-equal
           t (and (buffer-prose-producer buf) t))
          (rendering-assert-equal t (and (rendered-mode-p buf) t))
          ;; Fundamental stays incapable and raw.
          (let ((f (make-new-buffer "*rt-fund*" "")))
            (set-buffer-major-mode f "fundamental")
            (rendering-assert-equal nil (buffer-prose-producer f))
            (rendering-assert-equal nil (rendered-mode-p f))))))
    (rendering-test "the info projection: heading, spine links, menu links"
      (let ((*buffers* (make-hash-table :test 'equal)) (*current-buffer* nil)
            (*info-file-override*
              (merge-pathnames "docs/emacs-manual/ymacs/ymacs.info" (truename "."))))
        (let ((buf (info-open)))
          (let ((md (rendering-prose-for buf)))
            (rendering-assert-equal t (and (search "# Top" md) t))
            (rendering-assert-equal
             t (and (search "[Durable Buffers](<info:Durable Buffers>)" md) t))
            (rendering-assert-equal t (and (search "**Menu**" md) t))))))
    (rendering-test "follow-link routes info: hrefs to the node"
      (let ((*buffers* (make-hash-table :test 'equal)) (*current-buffer* nil)
            (*info-file-override*
              (merge-pathnames "docs/emacs-manual/ymacs/ymacs.info" (truename "."))))
        (let ((buf (info-open)))
          (setf *current-buffer* buf)
          (info-select-node buf "Top")
          (rendering-assert-equal
           "Durable Buffers" (rendering-follow-link "info:Durable Buffers"))
          (rendering-assert-equal
           "Durable Buffers" (info-current-node-name buf))
          (rendering-assert-equal nil (rendering-follow-link "https://example.com")))))
    (rendering-test "the schema emits the markdown widget when rendered"
      (let ((*buffers* (make-hash-table :test 'equal)) (*current-buffer* nil)
            (*info-file-override*
              (merge-pathnames "docs/emacs-manual/ymacs/ymacs.info" (truename "."))))
        (let* ((buf (info-open)))
          (setf *current-buffer* buf)
          (let* ((schema (document-schema))
                 (widgets (cdr (assoc "widgets" schema :test #'string=)))
               (editor (find-if (lambda (w) (string= (cdr (assoc "kind" w :test 'string=))
                           "markdown")) (coerce widgets 'list))))
            (rendering-assert-equal t (and editor t))
            (rendering-assert-equal
             "follow-link" (cdr (assoc "links_action" editor :test #'string=)))))))
    (rendering-test "typing drops to raw, then inserts"
      (let ((*buffers* (make-hash-table :test 'equal)) (*current-buffer* nil)
            (*info-file-override*
              (merge-pathnames "docs/emacs-manual/ymacs/ymacs.info" (truename "."))))
        (let ((buf (info-open)))
          (setf *current-buffer* buf)
          (rendering-assert-equal t (and (rendered-mode-p buf) t))
          (command-execute 'self-insert-command :args (list 1 #\x))
          (rendering-assert-equal nil (rendered-mode-p buf))
          (rendering-assert-equal t (and (search "x" (buffer-content buf)) t)))))
    (rendering-test "the ribbon names the toggle; the mode line names the modes"
      (let ((*buffers* (make-hash-table :test 'equal)) (*current-buffer* nil)
            (*info-file-override*
              (merge-pathnames "docs/emacs-manual/ymacs/ymacs.info" (truename "."))))
        (let ((buf (info-open)))
          (setf *current-buffer* buf)
          (let ((group (rendering-ribbon-group buf)))
            (rendering-assert-equal
             "Raw" (cdr (assoc "label"
                               (aref (cdr (assoc "buttons" group :test #'string=)) 0)
                               :test #'string=))))
          (rendering-assert-equal
           t (and (search "Rendered" (rendering-mode-tag buf)) t))))
      ;; An incapable buffer gets neither.
      (let ((*buffers* (make-hash-table :test 'equal)) (*current-buffer* nil))
        (let ((f (make-new-buffer "*rt-plain*" "hello")))
          (setf *current-buffer* f)
          (rendering-assert-equal nil (rendering-ribbon-group f))
          (rendering-assert-equal "" (rendering-mode-tag f)))))
    (rendering-test "global-rendered-mode off: capable buffers start raw"
      (let ((*buffers* (make-hash-table :test 'equal)) (*current-buffer* nil)
            (*global-rendered-mode* nil))
        (let ((buf (make-new-buffer "*rt-org2*" "* H1\ntext")))
          (set-buffer-major-mode buf "org-mode")
          (rendering-assert-equal t (and (buffer-prose-producer buf) t))
          (rendering-assert-equal nil (rendered-mode-p buf))
          ;; The projection still works when explicitly requested.
          (rendered-mode-on buf)
          (rendering-assert-equal
           t (and (search "# H1" (rendering-prose-for buf)) t)))))
    (format t "rendering: ~a passed, ~a failed~%"
            *rendering-test-pass* *rendering-test-fail*)
    (zerop *rendering-test-fail*)))

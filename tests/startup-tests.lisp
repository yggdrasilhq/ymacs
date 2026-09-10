;;;; startup-tests.lisp --- the startup screen is the front door.
;;;; Owner request 2026-09-10 (board ACK-83f10bee0f): the screen shows
;;;; on a fresh boot, its links walk with TAB and fire with RET, the
;;;; manual link opens Info, and the screen is a read-only view.
;;;;
;;;; Run: sbcl --load tests/run-tests.lisp
;;;; Plain CL, no dependencies.

(in-package #:ymacs)

(defvar *startup-test-pass* 0)
(defvar *startup-test-fail* 0)

(defmacro startup-test (name &body body)
  `(progn
     (format t "  ~a ..." ,name)
     (handler-case (progn ,@body (incf *startup-test-pass*) (format t " ok~%"))
       (error (e) (incf *startup-test-fail*) (format t " FAIL: ~a~%" e)))))

(defun startup-assert-equal (want got)
  (unless (equal want got)
    (error "expected ~s, got ~s" want got)))

(defun run-startup-tests ()
  (let ((*startup-test-pass* 0) (*startup-test-fail* 0))
    (startup-test "the splash text carries version, manual link and the GPL line"
      (let ((text (ymacs-splash-text)))
        (startup-assert-equal t (and (search *ymacs-version* text) t))
        (startup-assert-equal t (and (search "* The Ymacs Manual" text) t))
        (startup-assert-equal t (and (search "* Visit New File" text) t))
        (startup-assert-equal t (and (search "GNU GPL version 3" text) t))))
    (startup-test "ymacs-splash-ensure creates *GNU Ymacs* once, a view buffer"
      (let ((*buffers* (make-hash-table :test 'equal)) (*current-buffer* nil))
        (let ((first (ymacs-splash-ensure))
              (second (ymacs-splash-ensure)))
          (startup-assert-equal t (eq first second))
          (startup-assert-equal t (and (splash-buffer-p first) t))
          (startup-assert-equal "*GNU Ymacs*" (buffer-name first))
          (startup-assert-equal 1 (hash-table-count *buffers*)))))
    (startup-test "fresh boot law: splash active, manual NOT force-opened"
      (let ((*buffers* (make-hash-table :test 'equal))
            (*current-buffer* nil)
            (*ymacs-manual-path-override* "/nonexistent/manual.org"))
        (ensure-boot-buffers)
        (startup-assert-equal t (and (splash-buffer-p *current-buffer*) t))
        (startup-assert-equal t (some (lambda (b) (string= "*scratchpad-01*" (buffer-name b)))
                                      (list-all-buffers)))
        (startup-assert-equal nil (find-if #'buffer-file-path (list-all-buffers)))))
    (startup-test "TAB walks the links and wraps"
      (let ((*buffers* (make-hash-table :test 'equal)) (*current-buffer* nil))
        (let ((buf (ymacs-splash-ensure)))
          (setf *current-buffer* buf)
          (startup-next-link)
          (startup-assert-equal 10 (splash-line-index buf))
          (startup-next-link)
          (startup-assert-equal 11 (splash-line-index buf))
          (startup-next-link)
          (startup-assert-equal 10 (splash-line-index buf)))))
    (startup-test "S-TAB walks back, wrapping to the last link"
      (let ((*buffers* (make-hash-table :test 'equal)) (*current-buffer* nil))
        (let ((buf (ymacs-splash-ensure)))
          (setf *current-buffer* buf)
          (setf (buffer-point buf) 1)
          (startup-previous-link)
          (startup-assert-equal 11 (splash-line-index buf)))))
    (startup-test "RET on the manual link opens the manual in Info"
      (let ((*buffers* (make-hash-table :test 'equal)) (*current-buffer* nil)
            (*info-file-override*
              (merge-pathnames "docs/emacs-manual/ymacs/ymacs.info" (truename "."))))
        (let ((buf (ymacs-splash-ensure)))
          (setf *current-buffer* buf)
          (startup-next-link)
          (startup-activate-link)
          (startup-assert-equal "*info: ymacs*" (buffer-name *current-buffer*))
          (startup-assert-equal t (and (info-buffer-p *current-buffer*) t)))))
    (startup-test "RET on a non-link line is a message, not a crash"
      (let ((*buffers* (make-hash-table :test 'equal)) (*current-buffer* nil))
        (let ((buf (ymacs-splash-ensure)))
          (setf *current-buffer* buf)
          (setf (buffer-point buf) (splash-line-start buf 5))
          (startup-activate-link)
          (startup-assert-equal t (eq buf *current-buffer*)))))
    (startup-test "typing on the splash is refused: the screen is read-only"
      (let ((*buffers* (make-hash-table :test 'equal)) (*current-buffer* nil))
        (let ((buf (ymacs-splash-ensure)))
          (setf *current-buffer* buf)
          (let ((before (buffer-content buf)))
            (command-execute 'self-insert-command :args (list 1 #\x))
            (startup-assert-equal before (buffer-content buf))))))
    (startup-test "q kills the screen and selects the next real buffer"
      (let ((*buffers* (make-hash-table :test 'equal)) (*current-buffer* nil))
        (let ((scratch (make-new-buffer "*scratchpad-01*" ""))
              (buf (ymacs-splash-ensure)))
          (setf *current-buffer* buf)
          (startup-quit)
          (startup-assert-equal t (eq scratch *current-buffer*))
          (startup-assert-equal nil (find-if #'splash-buffer-p (list-all-buffers))))))
    (startup-test "C-h r is bound to the manual command globally"
      (init-default-keymaps)
      (startup-assert-equal t (eq 'info (lookup-key "C-h r"))))
    (format t "startup: ~a passed, ~a failed~%" *startup-test-pass* *startup-test-fail*)
    (zerop *startup-test-fail*)))

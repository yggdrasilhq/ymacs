;;;; info-tests.lisp --- the manual is readable by the reader it ships.
;;;; The docs law's litmus: makeinfo output parsed by ymacs's Info mode
;;;; yields the manual's nodes, the chapter spine, and working
;;;; navigation (n/p/u/RET/l/s/q) inside the live editor.
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
                  (info-assert-equal t (and (search "C-g" chapter) t))))))
          (info-test "the header spine parses (Next/Prev/Up)"
            (multiple-value-bind (order nodes) (info-parse text)
              (declare (ignore order))
              (info-assert-equal "Durable Buffers"
                                 (info-node-next (gethash "Top" nodes)))
              (info-assert-equal "Top"
                                 (info-node-prev (gethash "Durable Buffers" nodes)))
              (info-assert-equal "Top"
                                 (info-node-up (gethash "Durable Buffers" nodes)))
              (info-assert-equal "(dir)" (info-node-up (gethash "Top" nodes)))))
          (info-test "the Top menu extracts to chapter nodes"
            (multiple-value-bind (order nodes) (info-parse text)
              (let ((entries (info-menu-entries (gethash "Top" nodes))))
                (info-assert-equal "Durable Buffers"
                                   (cdr (assoc "Durable Buffers"
                                               entries :test #'string=)))
                (info-assert-equal "The Command Palette"
                                   (cdr (assoc "The Command Palette"
                                               entries :test #'string=)))
                ;; every chapter is reachable from the Top menu
                (info-assert-equal (length (rest order)) (length entries)))))
          (info-test "cross references resolve at point"
            (let ((xref "*note Reading this manual: Info Mode."))
              (info-assert-equal "Info Mode" (info-xref-node-at xref 10))
              (info-assert-equal "Info Mode" (info-xref-node-at xref 33))
              (info-assert-equal nil (info-xref-node-at xref 40)))
            (let ((double "*note Durable Buffers::"))
              (info-assert-equal "Durable Buffers" (info-xref-node-at double 5))
              (info-assert-equal nil (info-xref-node-at double 30)))))
        ;; --- navigation in the live editor ---------------------------
        (info-test "info-open lands on Top in info-mode"
          (let ((buf (info-open)))
            (info-assert-equal "*info: ymacs*" (buffer-name buf))
            (info-assert-equal "info-mode" (buffer-major-mode buf))
            (info-assert-equal "Top" (info-current-node-name buf))))
        (info-test "n/p walk the spine; Up past the root is refused"
          (let ((buf (info-open)))
            (info-next-node)
            (info-assert-equal "Durable Buffers" (info-current-node-name buf))
            (info-prev-node)
            (info-assert-equal "Top" (info-current-node-name buf))
            (info-up-node)
            (info-assert-equal "Top" (info-current-node-name buf))))
        (info-test "RET follows the menu entry under point"
          (let ((buf (info-open)))
            (let* ((content (buffer-content buf))
                   (menu-line (search "* Durable Buffers::" content)))
              (info-assert-equal t (and menu-line t))
              (setf (buffer-point buf) (+ menu-line 1 5))
              (info-follow-nearest-node)
              (info-assert-equal "Durable Buffers" (info-current-node-name buf))
              ;; RET on plain text refuses without moving
              (setf (buffer-point buf) 1)
              (info-follow-nearest-node)
              (info-assert-equal "Durable Buffers" (info-current-node-name buf)))))
        (info-test "u climbs to Top from a chapter"
          (let ((buf (info-open)))
            (info-select-node buf "The Store")
            (info-up-node)
            (info-assert-equal "Top" (info-current-node-name buf))))
        (info-test "l steps back through history"
          (let ((buf (info-open)))
            (info-select-node buf "The Store")
            (info-select-node buf "Profiles")
            (info-history-back)
            (info-assert-equal "The Store" (info-current-node-name buf))
            (info-history-back)
            (info-assert-equal "Top" (info-current-node-name buf))))
        (info-test "s finds a node by its content"
          (let ((buf (info-open)))
            (info-select-node buf "Top")
            (info-search "palette")
            (let* ((name (buffer-name buf))
                   (found (info-current-node-name buf))
                   (node-text (info-node-text (gethash found (gethash name *info-by-name*)))))
              (info-assert-equal t (and found node-text t))
              (info-assert-equal t (and (search "palette" node-text :test #'char-equal) t)))
            ;; a miss must not move the view
            (let ((before (info-current-node-name buf)))
              (info-search "zzz-no-such-thing-in-this-manual")
              (info-assert-equal before (info-current-node-name buf)))))
        (info-test "SPC at the last line advances to the Next node"
          (let ((buf (info-open)))
            (setf (buffer-point buf) (length (buffer-content buf)))
            (info-scroll-up)
            (info-assert-equal "Durable Buffers" (info-current-node-name buf))))
        (info-test "q kills the view and selects another buffer"
          (let ((buf (info-open)))
            (info-exit)
            (info-assert-equal nil
                               (find-if (lambda (b) (eq b buf))
                                        (list-all-buffers)))))))
    (format t "ymacs info suite: ~a passed, ~a failed~%"
            *info-test-pass* *info-test-fail*)
    (zerop *info-test-fail*)))

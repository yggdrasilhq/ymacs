;;;; sidebar-tests.lisp --- contract tests for the ONE rail pane
;;;; (docs/spec-primitives.md §1.2: max one sidebar; views multiplex behind
;;;; GET /pane/ymacs) and the bare-boot default buffer (the manual).
;;;;
;;;; Run: sbcl --load tests/run-tests.lisp
;;;; Plain CL, no dependencies — CI installs bare SBCL only.

(in-package #:ymacs)

(defun sb-count (needle haystack)
  (loop with n = 0 with start = 0
        for pos = (search needle haystack :start2 start)
        while pos do (incf n) (setf start (+ pos (max 1 (length needle))))
        finally (return n)))

(defun sb-declared-payload ()
  "The JSON emit-declare would base64: capture the OSC, decode it."
  (let* ((out (with-output-to-string (s)
                (let ((*standard-output* s)
                      (*current-buffer* nil))
                  (emit-declare "s" "c" "1"))))
         (b64 (subseq out (+ (search "declare;" out) (length "declare;"))
                      (position (code-char 7) out))))
    (sb-ext:octets-to-string (base64-decode-to-octets b64)
                             :external-format :utf-8)))

(defun sb-sandbox ()
  "Disk-backed sandbox under home — never /tmp (settings-tests pattern)."
  (merge-pathnames ".yggterm/scratchpad/ymacs-sb/" (user-homedir-pathname)))

(defun run-sidebar-tests ()
  (setf *test-pass* 0 *test-fail* 0)
  (format t "ymacs single-sidebar tests~%")

  (test "the declare carries exactly one rail pane: the ymacs pane"
    (let ((payload (sb-declared-payload)))
      (assert-eq* 1 (sb-count "\"placement\":\"rail\"" payload))
      (assert-eq* 1 (sb-count "\"placement\":\"viewport\"" payload))
      (assert-eq* 1 (sb-count "\"id\":\"ymacs\"" payload))))

  (test "view dispatch serves each schema behind the one pane"
    (let ((*sidebar-visible* t))
      (dolist (view-title '(("buffers" . "Buffers") ("outline" . "Outline")
                            ("which-key" . "Which Key") ("settings" . nil)))
        (setf *current-sidebar-pane* (car view-title))
        (let ((schema (sidebar-pane-schema)))
          (if (cdr view-title)
              (assert-eq* (cdr view-title)
                          (cdr (assoc "title" schema :test #'string=)))
              ;; settings without a book renders the honest empty schema —
              ;; still a schema, never a hole.
              (assert-eq* t (not (null (cdr (assoc "title" schema :test #'string=))))))))))

  (test "unknown views fall back to buffers, never a 404"
    (let ((*sidebar-visible* t)
          (*current-sidebar-pane* "project"))
      (assert-eq* "Buffers"
                  (cdr (assoc "title" (sidebar-pane-schema) :test #'string=)))))

  (test "the hidden card offers a way back"
    (let ((*sidebar-visible* nil))
      (let ((body (format nil "~a" (sidebar-pane-schema))))
        (assert-eq* t (not (null (search "toggle-sidebar" body)))))))

  (test "switching views moves the document version (the ping edge)"
    (let ((*sidebar-visible* nil)
          (*current-sidebar-pane* "buffers"))
      (let ((before (document-version)))
        (spawn-sidebar "outline")
        (assert-eq* t (not (null (string/= before (document-version)))))
        (assert-eq* "outline" *current-sidebar-pane*)
        (despawn-sidebar)
        (assert-eq* nil *sidebar-visible*))))

  (test "M-x sidebar opens the buffers view through the choke point"
    (let ((*sidebar-visible* nil)
          (*current-sidebar-pane* "outline"))
      (assert-eq* t (not (null (member "sidebar" (minibuffer-command-names)
                                       :test #'string=))))
      (command-execute 'sidebar)
      (assert-eq* t *sidebar-visible*)
      (assert-eq* "buffers" *current-sidebar-pane*)
      (despawn-sidebar)))

  (test "M-x settings is registered (bare interactive never was)"
    (assert-eq* t (not (null (member "settings" (minibuffer-command-names)
                                     :test #'string=)))))

  (test "boot never hijacks a live session (store closed, no writes)"
    ;; ensure-boot-buffers with no store open and no manual override
    ;; creates only the scratchpad when the session is empty.
    (let* ((*buffers* (make-hash-table :test 'equal))
           (*current-buffer* nil)
           (*ymacs-manual-path-override* "/nonexistent/manual.org"))
      (ensure-boot-buffers)
      (assert-eq* t (not (null *current-buffer*)))
      (let ((kept *current-buffer*))
        (ensure-boot-buffers)
        (assert-eq* kept *current-buffer*))))

  (format t "~a passed, ~a failed~%" *test-pass* *test-fail*)
  (zerop *test-fail*))

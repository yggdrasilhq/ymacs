;;;; ingress-tests.lisp --- the HTTP ingress contract: GUI-shaped bodies
;;;; parse whole (nested values included) and dispatch to the right arms.
;;;;
;;;; Regression: parse-flat-json could not see nested objects, so EVERY
;;;; action carrying values failed — M-x chords (not of type LIST), editor
;;;; drafts (save silently kept stale text), palette input, settings rows.
;;;; Both ends were tested; the joint was not. These tests speak the exact
;;;; shapes the GUI POSTs (document_pane_forward_key / run_action).
;;;;
;;;; Run: sbcl --load tests/run-tests.lisp
;;;; Plain CL, no dependencies — CI installs bare SBCL only.

(in-package #:ymacs)

(defun run-ingress-tests ()
  (setf *test-pass* 0 *test-fail* 0)
  (format t "ymacs ingress tests~%")

  (test "nested objects parse to nested alists"
    (let ((j (json-parse "{\"pane\":\"doc\",\"action\":\"key\",\"values\":{\"key\":\"M-x\"}}")))
      (assert-eq* "key" (cdr (assoc "action" j :test #'string=)))
      (assert-eq* "M-x" (cdr (assoc "key" (cdr (assoc "values" j :test #'string=))
                                    :test #'string=)))))

  (test "escapes decode: quotes, backslash, newline, unicode, emoji"
    (let ((j (json-parse "{\"form\":\"(string-upcase \\\"abc\\\")\",\"u\":\"caf\\u00e9 \\ud83d\\ude00\"}")))
      (assert-eq* "(string-upcase \"abc\")" (cdr (assoc "form" j :test #'string=)))
      (assert-eq* t (not (null (search "caf" (cdr (assoc "u" j :test #'string=))))))))

  (test "literals and numbers read truly"
    (let ((j (json-parse "{\"a\":true,\"b\":false,\"c\":null,\"n\":42}")))
      (assert-eq* t (cdr (assoc "a" j :test #'string=)))
      (assert-eq* :false (cdr (assoc "b" j :test #'string=)))
      (assert-eq* nil (cdr (assoc "c" j :test #'string=)))
      (assert-eq* 42 (cdr (assoc "n" j :test #'string=)))))

  (test "arrays read as lists, empty shapes hold"
    (let ((j (json-parse "{\"order\":[\"a\",\"b\"],\"e\":{},\"l\":[]}")))
      (assert-eq* '("a" "b") (cdr (assoc "order" j :test #'string=)))
      (assert-eq* nil (cdr (assoc "e" j :test #'string=)))
      (assert-eq* nil (cdr (assoc "l" j :test #'string=)))))

  (test "malformed bodies signal, never return garbage"
    (let ((failed nil))
      (dolist (bad '("{\"a\":" "{\"a\":1,}" "[1,2" "\"unterminated" "{oops}"))
        (handler-case (json-parse bad)
          (json-parse-error () (setf failed (1+ (or failed 0))))))
      (assert-eq* 5 failed)))

  (test "M-x through the real ingress opens the palette"
    (let* ((*buffers* (make-hash-table :test 'equal))
           (*current-buffer* nil)
           (*minibuffer-active* nil))
      (make-new-buffer "*ig*" "")
      (let* ((body (json-parse "{\"pane\":\"doc\",\"action\":\"key\",\"values\":{\"key\":\"M-x\"}}"))
             (reply (handle-action body)))
        (assert-eq* t *minibuffer-active*)
        (assert-eq* t (not (null (cdr (assoc "schema" reply :test #'string=))))))
      ;; And C-g puts it away again.
      (let* ((body (json-parse "{\"pane\":\"doc\",\"action\":\"key\",\"values\":{\"key\":\"C-g\"}}"))
             (reply (handle-action body)))
        (declare (ignore reply))
        (assert-eq* nil *minibuffer-active*))))

  (test "a draft round-trips: keystrokes then save persist"
    (let* ((*buffers* (make-hash-table :test 'equal))
           (*current-buffer* nil)
           (*recent-files* nil)
           (dir (sb-sandbox))
           (f nil))
      (ensure-directories-exist dir)
      (setf f (merge-pathnames "draft.txt" dir))
      (with-open-file (s f :direction :output :if-exists :supersede)
        (write-string "old" s))
      (open-file-buffer (namestring f))
      ;; GUI shape: values carry the draft AND its buffer identity.
      (let* ((bid (buffer-id *current-buffer*))
             (body (json-parse
                    (format nil "{\"pane\":\"doc\",\"action\":\"save\",\"values\":{\"editor\":\"new text \\u2014 here\"},\"value_keys\":{\"editor\":~a}}"
                            (json-string bid))))
             (reply (handle-action body)))
        (assert-eq* t (not (null (cdr (assoc "toast" reply :test #'string=)))))
        (assert-eq* "new text — here" (buffer-content *current-buffer*)))
      (ignore-errors (delete-file f))))

  (test "row clicks switch by the nested value"
    (let* ((*buffers* (make-hash-table :test 'equal))
           (*current-buffer* nil))
      (make-new-buffer "*ia*" "a")
      (let ((b (make-new-buffer "*ib*" "b")))
        (declare (ignore b))
        (setf *current-buffer* (first (list-all-buffers)))
        (let* ((want (second (list-all-buffers)))
               (body (json-parse
                      (format nil "{\"pane\":\"buffers\",\"action\":\"switch-buffer\",\"values\":{\"value\":~a}}"
                              (json-string (buffer-id want))))))
          (handle-action body)
          (assert-eq* (buffer-id want) (buffer-id *current-buffer*))))))

  (format t "~a passed, ~a failed~%" *test-pass* *test-fail*)
  (zerop *test-fail*))

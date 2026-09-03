;;;; store-tests.lisp --- the durable-store contract: every buffer is a
;;;; file or a row; profiles isolate open sets; the daemon is perpetual.
;;;;
;;;; Run via tests/store-runner.lisp (own sbcl image). The store is
;;;; pointed at sandbox files so tests never touch the user's real
;;;; ~/.yggterm/ymacs/state.sqlite3. Each test opens a FRESH store file —
;;;; never delete-and-reuse a name whose -wal/-shm siblings may linger.

(in-package #:ymacs)

(defun sb-dir ()
  "Disk-backed sandbox under the user's home — never /tmp."
  (merge-pathnames ".yggterm/scratchpad/ymacs-store/" (user-homedir-pathname)))

(defvar *store-file-counter* 0)

(defun sb-store-path (name)
  "A FRESH store file per call."
  (incf *store-file-counter*)
  (merge-pathnames (format nil "~a-~a-~a.sqlite3" name
                           (get-universal-time) *store-file-counter*)
                   (sb-dir)))

(defmacro stest (name &body body)
  `(progn
     (format t "  ~a ..." ,name)
     (force-output)
     (handler-case (progn ,@body (incf *test-pass*) (format t " ok~%") (force-output))
       (error (e) (incf *test-fail*) (format t " FAIL: ~a~%" e) (force-output)))))

(defun run-store-tests ()
  (setf *test-pass* 0 *test-fail* 0)
  (format t "ymacs durable-store tests~%")
  (force-output)

  ;; 1. durability: create -> row exists -> crash-sim restore -> delete.
  (let* ((*store-path-override* (sb-store-path "persist"))
         (*store* nil)
         (*profile* "default")
         (*buffers* (make-hash-table :test 'equal))
         (*current-buffer* nil))
    (stest "unnamed buffers persist at create and restore by id"
      (store-open)
      (let ((buf (make-new-buffer "*persist-me*" "survives anything")))
        (setf *current-buffer* buf)
        (assert-eq* t (store-buffer-exists-p (buffer-id buf)))
        (assert-eq* "survives anything" (store-buffer-content (buffer-id buf)))
        (let ((id (buffer-id buf)))
          (store-close)
          (setf *buffers* (make-hash-table :test 'equal) *current-buffer* nil)
          (store-open)
          (restore-unnamed-from-store id)
          (assert-eq* t (not (null (gethash id *buffers*))))
          (assert-eq* "survives anything"
                      (buffer-content (gethash id *buffers*)))
          (kill-buffer id)
          (assert-eq* nil (store-buffer-exists-p id))))
      (store-close)))

  ;; 2. profiles isolate open sets; switching never loses work.
  (let* ((*store-path-override* (sb-store-path "profiles"))
         (*store* nil)
         (*profile* "default")
         (*buffers* (make-hash-table :test 'equal))
         (*current-buffer* nil)
         (*recent-files* nil)
         (*sidebar-visible* nil)
         (*ymacs-manual-path-override* "/nonexistent/manual.org"))
    (stest "profiles isolate open sets; switching never loses work"
      (store-open)
      (let ((buf (make-new-buffer "*work-only*" "the other profile must not see this")))
        (setf *current-buffer* buf)
        (store-save-session (list (list (cons "id" (buffer-id buf))))
                            (buffer-id buf) 1))
      (ymacs-switch-profile "next")
      (assert-eq* "next" *profile*)
      (assert-eq* 0 (hash-table-count *buffers*))
      (let ((*profile* "default"))
        (assert-eq* t (not (null (store-list-buffer-ids)))))
      (ymacs-switch-profile "default")
      (assert-eq* t (not (null (some (lambda (b) (string= "*work-only*" (buffer-name b)))
                                     (list-all-buffers)))))
      (store-close)))

  ;; 3. the profiles view lists profiles, live one selected.
  (let* ((*store-path-override* (sb-store-path "profileview"))
         (*store* nil)
         (*profile* "default")
         (*buffers* (make-hash-table :test 'equal))
         (*current-buffer* nil))
    (stest "profiles schema lists rows with the live one selected"
      (store-open)
      (store-touch-profile "work")
      (let* ((schema (profiles-schema))
             (widgets (coerce (cdr (assoc "widgets" schema :test #'string=)) 'list))
             (rows (remove-if-not (lambda (w) (string= "list-row" (cdr (assoc "kind" w :test #'string=))))
                                  widgets)))
        (assert-eq* 2 (length rows))
        (assert-eq* t (cdr (assoc "selected" (find "default" rows
                                                   :key (lambda (w)
                                                          (cdr (assoc "id" w :test #'string=)))
                                                   :test #'string=)
                                   :test #'string=))))
      (store-close)))

  ;; 4. file-buffer drafts live in the store, per profile.
  (let* ((*store-path-override* (sb-store-path "drafts"))
         (*store* nil)
         (*profile* "default"))
    (stest "file-buffer drafts live in the store, not on disk"
      (store-open)
      (store-put-draft "/tmp/ymacs-store-test.txt" "draft body")
      (assert-eq* "draft body" (store-get-draft "/tmp/ymacs-store-test.txt"))
      (store-delete-draft "/tmp/ymacs-store-test.txt")
      (assert-eq* nil (store-get-draft "/tmp/ymacs-store-test.txt"))
      (store-close)))

  ;; 5. boot law: manual + scratchpad-01, manual active, create-once.
  (let* ((dir (sb-dir))
         (*store-path-override* (sb-store-path "boot"))
         (*store* nil)
         (*buffers* (make-hash-table :test 'equal))
         (*current-buffer* nil)
         (*recent-files* nil)
         (manual (merge-pathnames "manual.org" dir)))
    (stest "the boot law: manual + scratchpad-01, manual active"
      (ensure-directories-exist dir)
      (with-open-file (s manual :direction :output :if-exists :supersede
                                :external-format :utf-8)
        (write-string "* The Ymacs Manual~%" s))
      (let ((*ymacs-manual-path-override* (namestring manual)))
        (store-open)
        (ensure-boot-buffers)
        (assert-eq* t (some (lambda (b) (string= "*scratchpad-01*" (buffer-name b)))
                            (list-all-buffers)))
        (assert-eq* t (not (null *current-buffer*)))
        (assert-eq* t (and (buffer-file-path *current-buffer*)
                           (not (null (search "manual"
                                              (namestring (buffer-file-path *current-buffer*))
                                              :test #'string-equal)))))
        (ensure-boot-buffers)
        (assert-eq* 2 (hash-table-count *buffers*))
        (store-close))
      (ignore-errors (delete-file manual))))

  ;; 6. M-x surface of the law.
  (stest "save-buffers-kill-ymacs is registered for M-x"
    (assert-eq* t (not (null (member "save-buffers-kill-ymacs"
                                     (minibuffer-command-names)
                                     :test #'string=)))))

  (format t "~a passed, ~a failed~%" *test-pass* *test-fail*)
  (force-output)
  (zerop *test-fail*))

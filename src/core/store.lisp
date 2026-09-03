;;;; store.lisp --- THE durable store (sqlite), profiles and durable buffers
;;;;
;;;; Law (spec-primitives §1.4): every buffer is either a FILE or a row in
;;;; this store. There is no memory-only buffer, so no work is ever lost —
;;;; the yedit doctrine (state.sqlite3, WAL) in Common Lisp. The daemon is
;;;; PERPETUAL: switching profiles never stops it; only an explicit
;;;; save-buffers-kill-ymacs (or the OS) ends it.
;;;;
;;;; Storage: vendored cl-sqlite over cffi (see vendor/ — imported
;;;; ecosystems, the same doctrine as Rust's vendored crates), libsqlite3
;;;; is the one system library (Debian: libsqlite3-0; CI/hosts:
;;;; libsqlite3-dev at build time is NOT needed — cffi talks to the
;;;; runtime lib directly).

(in-package #:ymacs)

(defvar *store* nil "The open sqlite connection, or NIL.")
(defvar *store-path-override* nil "Test/diagnostic override.")
(defvar *profile* "default" "The live profile (Chrome tab-set semantics).")

(defun store-path ()
  (or *store-path-override*
      (let ((env (sb-ext:posix-getenv "YMACS_STORE")))
        (and env (plusp (length env)) env))
      (merge-pathnames "state.sqlite3" (ymacs-state-dir))))

(define-condition store-error (error)
  ((what :initarg :what :reader store-error-what))
  (:report (lambda (c s) (format s "ymacs store: ~a" (store-error-what c)))))

(defun store-open ()
  "Open (and migrate) the store. Idempotent."
  (unless *store*
    (ensure-state-dir)
    (require :asdf)
    (handler-case
        (let ((db (sqlite:connect (namestring (store-path)))))
          ;; WAL uses an mmap'd -shm; through cffi on this stack it
          ;; corrupted the heap under repeat open/close. Rollback-journal
          ;; mode is single-writer (ymacs is the only writer) and stable.
          (sqlite:execute-non-query db "PRAGMA journal_mode=DELETE")
          (sqlite:execute-non-query db "PRAGMA synchronous=FULL")
          (store-migrate db)
          (setf *store* db))
      (error (e)
        (error 'store-error :what (format nil "cannot open ~a: ~a" (store-path) e)))))
  *store*)

(defun store-close ()
  (when *store*
    (ignore-errors (sqlite:disconnect *store*))
    (setf *store* nil)))

(defmacro with-store (&body body)
  `(progn (store-open) ,@body))

(defun store-migrate (db)
  "Idempotent schema. v1: profiles, buffers (unnamed durable content),
session (the per-profile open set), drafts (file-buffer crash safety)."
  (sqlite:execute-non-query db
    "CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)")
  (sqlite:execute-non-query db
    "INSERT OR IGNORE INTO meta (key, value) VALUES ('schema_version', '1')")
  (sqlite:execute-non-query db
    "CREATE TABLE IF NOT EXISTS profiles (
        id TEXT PRIMARY KEY,
        created_at INTEGER NOT NULL,
        last_used INTEGER NOT NULL)")
  (sqlite:execute-non-query db
    "INSERT OR IGNORE INTO profiles (id, created_at, last_used) VALUES ('default', 0, 0)")
  (sqlite:execute-non-query db
    "CREATE TABLE IF NOT EXISTS buffers (
        id TEXT PRIMARY KEY,
        profile TEXT NOT NULL REFERENCES profiles(id),
        name TEXT NOT NULL,
        content TEXT NOT NULL DEFAULT '',
        kind TEXT NOT NULL DEFAULT 'scratch',
        created_at INTEGER NOT NULL,
        modified_at INTEGER NOT NULL)")
  (sqlite:execute-non-query db
    "CREATE INDEX IF NOT EXISTS buffers_by_profile ON buffers(profile)")
  (sqlite:execute-non-query db
    "CREATE TABLE IF NOT EXISTS session (
        profile TEXT PRIMARY KEY REFERENCES profiles(id),
        open_json TEXT NOT NULL DEFAULT '[]',
        active TEXT NOT NULL DEFAULT '',
        epoch INTEGER NOT NULL DEFAULT 0)")
  (sqlite:execute-non-query db
    "CREATE TABLE IF NOT EXISTS drafts (
        profile TEXT NOT NULL,
        path TEXT NOT NULL,
        content TEXT NOT NULL,
        saved_at INTEGER NOT NULL,
        PRIMARY KEY (profile, path))"))

(defun store-now ()
  (get-universal-time))

;;; --- profiles ---------------------------------------------------------

(defun store-list-profiles ()
  (with-store
    (sqlite:execute-to-list *store*
      "SELECT id FROM profiles ORDER BY last_used DESC, id")))

(defun store-touch-profile (id)
  (with-store
    (sqlite:execute-non-query *store*
      "INSERT OR IGNORE INTO profiles (id, created_at, last_used) VALUES (?, ?, ?)"
      id (store-now) (store-now))
    (sqlite:execute-non-query *store*
      "UPDATE profiles SET last_used = ? WHERE id = ?" (store-now) id)))

;;; --- durable (unnamed) buffers ----------------------------------------

(defun store-buffer-exists-p (id)
  (with-store
    (let ((rows (sqlite:execute-to-list *store*
                  "SELECT id FROM buffers WHERE id = ? AND profile = ?"
                  id *profile*)))
      (not (null rows)))))

(defun store-put-buffer (buf &key (kind "scratch"))
  "Durably persist the CONTENT of an unnamed buffer. Called at create and
on every mutation — the write IS the save, there is no dirty state."
  (with-store
    (sqlite:execute-non-query *store*
      "INSERT INTO buffers (id, profile, name, content, kind, created_at, modified_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET name=excluded.name, content=excluded.content,
         kind=excluded.kind, modified_at=excluded.modified_at"
      (buffer-id buf) *profile* (buffer-name buf)
      (buffer-content buf) kind (store-now) (store-now))))

(defun store-get-buffer (id)
  "Values: NAME CONTENT KIND, or all NIL when absent."
  (with-store
    (let ((rows (sqlite:execute-to-list *store*
                  "SELECT name, content, kind, created_at FROM buffers
                   WHERE id = ? AND profile = ?" id *profile*)))
      (if rows
          (let ((row (first rows)))
            (values (first row) (second row) (third row)))
          (values nil nil nil)))))

(defun store-buffer-content (id)
  "The durable content of one unnamed buffer, or NIL."
  (multiple-value-bind (name content kind) (store-get-buffer id)
    (declare (ignore name kind))
    content))

(defun store-delete-buffer (id)
  (with-store
    (sqlite:execute-non-query *store*
      "DELETE FROM buffers WHERE id = ? AND profile = ?" id *profile*)))

(defun store-list-buffer-ids ()
  (with-store
    (mapcar #'first
            (sqlite:execute-to-list *store*
              "SELECT id FROM buffers WHERE profile = ? ORDER BY created_at" *profile*))))

;;; --- drafts (file-buffer crash safety, in the store now) ---------------

(defun store-put-draft (path content)
  (with-store
    (sqlite:execute-non-query *store*
      "INSERT INTO drafts (profile, path, content, saved_at) VALUES (?, ?, ?, ?)
       ON CONFLICT(profile, path) DO UPDATE SET content=excluded.content,
         saved_at=excluded.saved_at"
      *profile* (namestring path) content (store-now))))

(defun store-get-draft (path)
  (with-store
    (let ((rows (sqlite:execute-to-list *store*
                  "SELECT content FROM drafts WHERE profile = ? AND path = ?"
                  *profile* (namestring path))))
      (when rows (first (first rows))))))

(defun store-delete-draft (path)
  (with-store
    (sqlite:execute-non-query *store*
      "DELETE FROM drafts WHERE profile = ? AND path = ?"
      *profile* (namestring path))))

;;; --- session (per-profile open set) ------------------------------------

(defun store-save-session (open-entries active epoch)
  "OPEN-ENTRIES: alist of entries ((\"id\" . id) | (\"path\" . path)) in
window order."
  (store-touch-profile *profile*)
  (with-store
    (sqlite:execute-non-query *store*
      "INSERT INTO session (profile, open_json, active, epoch) VALUES (?, ?, ?, ?)
       ON CONFLICT(profile) DO UPDATE SET open_json=excluded.open_json,
         active=excluded.active, epoch=excluded.epoch"
      *profile* (json-string open-entries) (or active "") epoch)))

(defun store-load-session ()
  "Values: OPEN-ENTRIES ACTIVE EPOCH PRESENT-P. PRESENT-P distinguishes
a row that exists (possibly an empty list) from no row ever saved —
the legacy session.json import may run only on a first boot."
  (with-store
    (let ((rows (sqlite:execute-to-list *store*
                  "SELECT open_json, active, epoch FROM session WHERE profile = ?"
                  *profile*)))
      (if rows
          (let* ((raw (first (first rows)))
                 (entries (ignore-errors (json-parse raw))))
            (values (or entries nil)
                    (second (first rows))
                    (third (first rows))
                    t))
          (values nil nil nil nil)))))

;;; --- profiles: switch ---------------------------------------------------

(defun store-profile-open-ids ()
  "Unnamed durable buffers OF THE LIVE PROFILE (they always reopen)."
  (store-list-buffer-ids))

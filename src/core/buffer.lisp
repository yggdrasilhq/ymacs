;;;; buffer.lisp --- Buffer engine, file I/O, session persistence
;;;; Value-key discipline: every buffer carries an opaque `value-key`
;;;; (its stable id). The GUI's `values.editor` draft posts back
;;;; `value_keys: {"editor": value-key}` so a late draft lands on the
;;;; buffer it was typed in, not whatever is active now.

(in-package #:ymacs)

(defstruct buffer
  id
  name
  file-path
  rope
  point
  mark
  modified-p
  value-key
  ;; Revision guard: mtime_ms:size at load/save (yedit's disk_revision).
  loaded-revision
  created-at)

(defvar *buffers* (make-hash-table :test 'equal))
(defvar *current-buffer* nil)
(defvar *buffer-epoch* 0)
(defvar *recent-files* nil)

(defun buffer-content (buf)
  (if (buffer-rope buf)
      (rope-to-string (buffer-rope buf))
      ""))

(defun (setf buffer-content) (new-val buf)
  (setf (buffer-rope buf) (rope-from-string new-val))
  (setf (buffer-modified-p buf) t)
  (buffer-sync buf)
  new-val)

(defun state-dir ()
  (let ((home (or (sb-ext:posix-getenv "HOME")
                  (namestring (user-homedir-pathname)))))
    (merge-pathnames ".yggterm/ymacs/" (parse-namestring (concatenate 'string home "/")))))

(defun ensure-state-dir ()
  (let ((dir (state-dir)))
    (ensure-directories-exist dir)
    dir))

(defun disk-revision (path)
  (if (probe-file path)
      (let* ((mtime (file-write-date path))
             (sz (with-open-file (s path :element-type '(unsigned-byte 8)) (file-length s))))
        (format nil "~a:~a" mtime sz))
      "new"))

(defun ymacs-note-id (path)
  "FNV-1a hex id for PATH, like yedit's note_id (stable, not an index)."
  (let ((str (namestring path))
        (hash #xCBF29CE484222325)
        (prime #x100000001B3))
    (loop for ch across str do
      (setf hash (logxor hash (char-code ch)))
      (setf hash (logand #xFFFFFFFFFFFFFFFF (* hash prime))))
    (format nil "~16,'0x" hash)))

(defun make-new-buffer (name &optional content)
  (let* ((id (format nil "buf-~a-~a" (get-universal-time) (random 100000)))
         (rope (rope-from-string (or content "")))
         (buf (make-buffer :id id
                           :name name
                           :rope rope
                           :point 0
                           :mark 0
                           :modified-p nil
                           :value-key id
                           :loaded-revision "new"
                           :created-at (get-universal-time)
                           :file-path nil)))
    (setf (gethash id *buffers*) buf)
    (unless *current-buffer*
      (setf *current-buffer* buf))
    ;; The store law: an unnamed buffer is a DB row the moment it exists.
    (buffer-sync buf)
    (incf *buffer-epoch*)
    buf))

(defun buffer-sync (buf)
  "DURABILITY CHOKE POINT. File buffer: crash-safety draft into the
store's drafts table. Unnamed buffer: the content row IS the save —
called at create and after every command (command-execute), so no work
is ever only in memory. No-op until the store is open (unit tests,
--help), so tests never touch the disk store."
  (when *store*
    (unless (and (fboundp 'info-buffer-p) (info-buffer-p buf))
      (ignore-errors
       (if (buffer-file-path buf)
           (store-put-draft (buffer-file-path buf) (buffer-content buf))
           (store-put-buffer buf))))))

(defun open-file-buffer (pathspec &key (content nil))
  "Open file at PATHSPEC as a buffer. Creates new untitled buffer if file missing.
   Returns buffer."
  (let* ((path (if (stringp pathspec) (pathname pathspec) pathspec))
         (truename (ignore-errors (truename path)))
         (effective (or truename path))
         (name (or (pathname-name path) (file-namestring path) "untitled"))
         (existing (find-buffer-by-path effective)))
    (when existing
      (setf *current-buffer* existing)
      (return-from open-file-buffer existing))
    (let* ((id (ymacs-note-id effective))
           (already (gethash id *buffers*)))
      (when already
        (setf *current-buffer* already)
        (return-from open-file-buffer already))
      (multiple-value-bind (file-content revision)
          (if (probe-file effective)
              (values (read-file-string effective) (disk-revision effective))
              (values (or content "") "new"))
        (let* ((rope (rope-from-string file-content))
               (buf (make-buffer :id id
                                 :name (file-namestring effective) ; display: filename (Emacs parity).
                                  ;; Identity stays the full path (id,
                                  ;; file-path, value-key); same-named files
                                  ;; in different dirs collide in display —
                                  ;; disambiguation is open work.
                                 :file-path effective
                                 :rope rope
                                 :point 0
                                 :mark 0
                                 :modified-p nil
                                 :value-key id
                                 :loaded-revision revision
                                 :created-at (get-universal-time))))
          (setf (gethash id *buffers*) buf)
          (setf *current-buffer* buf)
          (pushnew (namestring effective) *recent-files* :test #'string=)
          (when (> (length *recent-files*) 20)
            (setf *recent-files* (subseq *recent-files* 0 20)))
          (incf *buffer-epoch*)
          buf)))))

(defun find-buffer-by-path (path)
  (loop for buf being the hash-values of *buffers*
        when (and (buffer-file-path buf)
                  (string= (namestring (buffer-file-path buf)) (namestring path)))
        return buf))

(defun read-file-string (path)
  (with-open-file (s path :direction :input :external-format :utf-8
                       :if-does-not-exist nil)
    (when s
      (let ((content (make-string (file-length s))))
        ;; file-length is bytes for utf-8; read via stream instead
        (let ((out (make-string-output-stream)))
          (loop for ch = (read-char s nil nil)
                while ch do (write-char ch out))
          (get-output-stream-string out))))))

(defun get-buffer-by-id (id)
  (gethash id *buffers*))

(defun list-all-buffers ()
  (loop for v being the hash-values of *buffers* collect v))

(defun current-buffer ()
  *current-buffer*)

(defun switch-to-buffer (id)
  (let ((buf (gethash id *buffers*)))
    (when buf (setf *current-buffer* buf) t)))

(defun kill-buffer (id)
  (let ((buf (gethash id *buffers*)))
    (when buf
      (remhash id *buffers*)
      (when *store*
        (ignore-errors
         (if (buffer-file-path buf)
             (store-delete-draft (buffer-file-path buf))
             (store-delete-buffer id))))
      (when (and *current-buffer* (string= (buffer-id *current-buffer*) id))
        (setf *current-buffer* (first (list-all-buffers))))
      (incf *buffer-epoch*)
      t)))

(defun buffer-insert (buf pos text)
  (fire-probe :ymacs-buffer-mutation :buffer-id (buffer-id buf) :operation "insert" :length (length text))
  (setf (buffer-rope buf) (rope-insert (buffer-rope buf) pos text))
  (setf (buffer-modified-p buf) t)
  (buffer-sync buf)
  (incf *buffer-epoch*)
  (bump-document-version)
  buf)

(defun buffer-delete (buf pos len)
  (fire-probe :ymacs-buffer-mutation :buffer-id (buffer-id buf) :operation "delete" :length len)
  (setf (buffer-rope buf) (rope-delete (buffer-rope buf) pos len))
  (setf (buffer-modified-p buf) t)
  (buffer-sync buf)
  (incf *buffer-epoch*)
  (bump-document-version)
  buf)

(defun buffer-replace (buf target replacement)
  (let ((content (buffer-content buf)))
    (let ((pos (search target content)))
      (when pos
        (buffer-delete buf pos (length target))
        (buffer-insert buf pos replacement))))
  buf)

(defun buffer-save (buf &key force)
  "Save BUF to its file-path. Returns :saved, :conflict, or :no-file."
  (unless (buffer-file-path buf)
    (return-from buffer-save :no-file))
  (let* ((path (buffer-file-path buf))
         (disk (disk-revision path))
         (loaded (buffer-loaded-revision buf)))
    (when (and (not force) (not (string= disk loaded)) (not (string= disk "new")))
      (return-from buffer-save :conflict))
    (ensure-directories-exist path)
    (with-open-file (s path :direction :output :if-exists :supersede
                         :external-format :utf-8 :if-does-not-exist :create)
      (write-string (buffer-content buf) s))
    (setf (buffer-loaded-revision buf) (disk-revision path))
    (setf (buffer-modified-p buf) nil)
    ;; Persist draft removal: delete any draft row (see session persistence)
    (delete-draft (namestring path))
    (incf *buffer-epoch*)
    :saved))

(defun close-buffer (id)
  (kill-buffer id))

;;; Draft persistence (crash safety): each dirty buffer gets a draft file
;;; ~/.yggterm/ymacs/drafts/<id>.lisp  (full content, not diff).
;;; On startup, drafts restore.

;; Crash-safety drafts live IN the store now (drafts table, per profile);
;; the legacy drafts/ directory is no longer read or written.

(defun persist-draft (buf)
  (buffer-sync buf))

(defun delete-draft (path-or-id)
  (when *store*
    (ignore-errors (store-delete-draft
                    (if (pathnamep path-or-id) path-or-id (pathname path-or-id))))))

(defun persist-session ()
  "The store is the session SSOT: the per-profile open set + active.
Entry shape: ((\"id\" . id)) for unnamed durable buffers, ((\"path\"
. path)) for file buffers."
  (let* ((open-entries
           (loop for b being the hash-values of *buffers*
                 collect (if (buffer-file-path b)
                             (list (cons "path" (namestring (buffer-file-path b))))
                             (list (cons "id" (buffer-id b))))))
         (active (when *current-buffer*
                   (if (buffer-file-path *current-buffer*)
                       (namestring (buffer-file-path *current-buffer*))
                       (buffer-id *current-buffer*)))))
    (when *store*
      (ignore-errors
       (store-save-session open-entries active *buffer-epoch*)))
    (setf *session-last-save* (get-universal-time))
    (fire-probe :ymacs-session :action "save" :buffers (hash-table-count *buffers*))
    t))

(defun restore-session (&key (allow-legacy t))
  "Store first. A legacy session.json (pre-store) is imported once —
boot only, never on a profile switch — and the first persist moves
everything into the store."
  (multiple-value-bind (entries active epoch present-p)
      (ignore-errors (store-load-session))
    (if present-p
        (progn
          (dolist (e entries)
            (let ((id (cdr (assoc "id" e :test #'string=)))
                  (path (cdr (assoc "path" e :test #'string=))))
              (cond
                (id (restore-unnamed-from-store id))
                ((and path (plusp (length path)))
                 (ignore-errors (open-file-buffer path))))))
          (let ((hit (or (and active (gethash active *buffers*))
                         (and active (plusp (length active))
                              (ignore-errors
                               (find-buffer-by-path (pathname active)))))))
            (when hit (setf *current-buffer* hit)))
          (when epoch (setf *buffer-epoch* epoch)))
        (let ((path (and allow-legacy
                         (merge-pathnames "session.json" (state-dir)))))
          (when (and path (probe-file path))
            (ignore-errors
              (let* ((json (read-file-string path))
                     (data (json-decode json))
                     (open-list (cdr (assoc "open" data :test #'string=))))
                (dolist (p open-list)
                  (ignore-errors (open-file-buffer (pathname p))))
                (let ((a (cdr (assoc "active" data :test #'string=))))
                  (when a
                    (let ((buf (or (find-buffer-by-path a) (get-buffer-by-id a))))
                      (when buf (setf *current-buffer* buf))))))
              (let ((recent (ignore-errors
                              (let* ((json (read-file-string path))
                                     (data (json-decode json)))
                                (cdr (assoc "recent" data :test #'string=))))))
                (when recent (setf *recent-files* recent))))))))
  (fire-probe :ymacs-session :action "restore" :buffers (hash-table-count *buffers*))
  t)

(defun restore-unnamed-from-store (id)
  "Recreate one unnamed durable buffer from its store row."
  (multiple-value-bind (name content kind) (ignore-errors (store-get-buffer id))
    (declare (ignore kind))
    (let ((buf (make-buffer :id id
                            :name (or name id)
                            :rope (rope-from-string (or content ""))
                            :point 0
                            :mark 0
                            :modified-p nil
                            :value-key id
                            :loaded-revision "store"
                            :created-at (get-universal-time)
                            :file-path nil)))
      (setf (gethash id *buffers*) buf)
      (when (null *current-buffer*) (setf *current-buffer* buf))
      buf)))

;;; Minimal JSON encode/decode for session.json (no external dep).
(defun json-encode (alist)
  (with-output-to-string (out)
    (write-char #\{ out)
    (loop for (pair . rest) on alist
          for (k . v) = pair
          do (format out "\"~a\":" k)
             (cond
               ((stringp v) (format out "\"~a\"" (json-escape v)))
               ((numberp v) (format out "~a" v))
               ((null v) (format out "null"))
               ((listp v) (format out "[~{~a~^,~}]"
                                   (mapcar (lambda (x) (format nil "\"~a\"" (json-escape (if (stringp x) x (princ-to-string x))))) v)))
               (t (format out "\"~a\"" (json-escape (princ-to-string v)))))
          when rest do (write-char #\, out))
    (write-char #\} out)))

(defun json-escape (s)
  (with-output-to-string (out)
    (loop for ch across s do
      (case ch
        (#\" (write-string "\\\"" out))
        (#\\ (write-string "\\\\" out))
        (#\Newline (write-string "\\n" out))
        (#\Return (write-string "\\r" out))
        (#\Tab (write-string "\\t" out))
        (otherwise (write-char ch out))))))

(defun json-decode (str)
  "Very small JSON parser for session.json only (flat object, string arrays)."
  (let ((result nil))
    ;; Extract "open": [...] etc via cl-ppcre-like manual scan if available.
    ;; Fallback: use simple search without regex library.
    (flet ((extract-string (key)
             (let* ((needle (format nil "\"~a\":" key))
                    (pos (search needle str)))
               (when pos
                 (let* ((start (+ pos (length needle)))
                        (q1 (position #\" str :start start))
                        (q2 (when q1 (position #\" str :start (1+ q1)))))
                   (when (and q1 q2)
                     (subseq str (1+ q1) q2))))))
           (extract-array (key)
             (let* ((needle (format nil "\"~a\":" key))
                    (pos (search needle str)))
               (when pos
                 (let* ((start (+ pos (length needle)))
                        (b1 (position #\[ str :start start))
                        (b2 (when b1 (position #\] str :start b1))))
                   (when (and b1 b2)
                     (let* ((inner (subseq str (1+ b1) b2))
                            (items nil)
                            (i 0))
                       (loop while (< i (length inner)) do
                         (let ((q1 (position #\" inner :start i)))
                           (unless q1 (return))
                           (let ((q2 (position #\" inner :start (1+ q1))))
                             (unless q2 (return))
                             (push (subseq inner (1+ q1) q2) items)
                             (setf i (1+ q2)))))
                       (nreverse items))))))))
      (let ((open (extract-array "open"))
            (recent (extract-array "recent"))
            (active (extract-string "active"))
            (epoch (let* ((needle "\"epoch\":")
                          (pos (search needle str)))
                     (when pos
                       (let* ((start (+ pos (length needle)))
                              (end (or (position-if (lambda (c) (find c ",}")) str :start start)
                                       (length str))))
                         (ignore-errors (parse-integer (string-trim '(#\Space #\Newline #\Tab) (subseq str start end)))))))))
        (push (cons "open" open) result)
        (push (cons "recent" recent) result)
        (push (cons "active" active) result)
        (push (cons "epoch" epoch) result)
        result))))



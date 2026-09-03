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
    (incf *buffer-epoch*)
    buf))

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
  (when (gethash id *buffers*)
    (remhash id *buffers*)
    (when (and *current-buffer* (string= (buffer-id *current-buffer*) id))
      (setf *current-buffer* (first (list-all-buffers))))
    (incf *buffer-epoch*)
    t))

(defun buffer-insert (buf pos text)
  (fire-probe :ymacs-buffer-mutation :buffer-id (buffer-id buf) :operation "insert" :length (length text))
  (setf (buffer-rope buf) (rope-insert (buffer-rope buf) pos text))
  (setf (buffer-modified-p buf) t)
  (incf *buffer-epoch*)
  (bump-document-version)
  buf)

(defun buffer-delete (buf pos len)
  (fire-probe :ymacs-buffer-mutation :buffer-id (buffer-id buf) :operation "delete" :length len)
  (setf (buffer-rope buf) (rope-delete (buffer-rope buf) pos len))
  (setf (buffer-modified-p buf) t)
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

(defun drafts-dir ()
  (merge-pathnames "drafts/" (state-dir)))

(defun draft-path (id)
  (merge-pathnames (concatenate 'string id ".draft") (drafts-dir)))

(defun persist-draft (buf)
  (when (buffer-modified-p buf)
    (ensure-directories-exist (drafts-dir))
    (with-open-file (s (draft-path (buffer-id buf)) :direction :output :if-exists :supersede
                         :external-format :utf-8)
      (write-string (buffer-content buf) s))))

(defun delete-draft (path-or-id)
  (let ((p (merge-pathnames (concatenate 'string (ymacs-note-id (pathname path-or-id)) ".draft")
                            (drafts-dir))))
    (ignore-errors (delete-file p)))
  ;; Also try direct id
  (ignore-errors (delete-file (draft-path path-or-id))))

(defun persist-session ()
  "Write session.json: open buffers, active, epoch."
  (let* ((dir (ensure-state-dir))
         (path (merge-pathnames "session.json" dir))
         (open-buffers (loop for b being the hash-values of *buffers*
                             when (buffer-file-path b)
                             collect (namestring (buffer-file-path b))))
         (active (when *current-buffer* (if (buffer-file-path *current-buffer*)
                                            (namestring (buffer-file-path *current-buffer*))
                                            (buffer-id *current-buffer*)))))
    (with-open-file (s path :direction :output :if-exists :supersede :external-format :utf-8)
      (write-string (json-encode `(("open" . ,open-buffers)
                                   ("active" . ,active)
                                   ("epoch" . ,*buffer-epoch*)
                                   ("recent" . ,*recent-files*))) s))))

(defun restore-session ()
  (let ((path (merge-pathnames "session.json" (state-dir))))
    (when (probe-file path)
      (ignore-errors
        (let* ((json (read-file-string path))
               (data (json-decode json))
               (open-list (cdr (assoc "open" data :test #'string=))))
          (dolist (p open-list)
            (ignore-errors (open-file-buffer (pathname p))))
          (let ((active (cdr (assoc "active" data :test #'string=))))
            (when active
              (let ((buf (or (find-buffer-by-path active) (get-buffer-by-id active))))
                (when buf (setf *current-buffer* buf)))))
          (let ((recent (cdr (assoc "recent" data :test #'string=))))
            (when recent (setf *recent-files* recent))))))
    ;; Restore drafts
    (when (probe-file (drafts-dir))
      (dolist (draft-file (directory (merge-pathnames "*.draft" (drafts-dir))))
        (ignore-errors
          (let* ((id (pathname-name draft-file))
                 (content (read-file-string draft-file))
                 (buf (get-buffer-by-id id)))
            (if buf
                (setf (buffer-rope buf) (rope-from-string content)
                      (buffer-modified-p buf) t)
                ;; Orphan draft: create buffer named after id
                (let ((nb (make-new-buffer id content)))
                  (setf (buffer-id nb) id
                        (buffer-value-key nb) id
                        (buffer-modified-p nb) t)
                  (setf (gethash id *buffers*) nb)))))))))

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

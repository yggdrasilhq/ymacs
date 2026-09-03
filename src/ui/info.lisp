;;;; info.lisp --- Info mode: read the forked Ymacs manual inside ymacs.
;;;;
;;;; Interface law: the KEYSET is Emacs Info (n/p/u/RET/l/q/s) so the
;;;; fingers transfer from GNU Emacs; the implementation is CL, reading
;;;; the built .info file (makeinfo output) by node markers. Divergences
;;;; from Emacs Info are recorded in docs/emacs-manual/divergences.org.

(in-package #:ymacs)

(defparameter *info-sep* (code-char 31)
  "The ^_ node separator of the .info format.")

(defvar *info-file-override* nil "Test/diagnostic override.")
(defvar *info-history* nil "List of (file node point), most recent first.")

(defun info-file ()
  (or *info-file-override*
      (let ((env (sb-ext:posix-getenv "YMACS_INFO_PATH")))
        (and env (plusp (length env)) (probe-file env) env))
      (let ((share (merge-pathnames ".local/share/ymacs/ymacs.info"
                                    (pathname (concatenate 'string (ymacs-home) "/")))))
        (and (probe-file share) share))
      ;; repo/daemon-cwd fallbacks
      (let ((cwd (merge-pathnames "docs/emacs-manual/ymacs/ymacs.info"
                                  (truename "."))))
        (and (probe-file cwd) cwd))))

(defstruct info-node
  name text next prev up)

(defun info-parse (text)
  "Returns (VALUES ORDER NODES): ORDER is the node names in file order
(first is the entry node), NODES a name -> info-node table. Nodes are
separated by the ^_ control character; each header carries Node: NAME."
  (let ((nodes (make-hash-table :test 'equal))
        (order nil)
        (starts nil)
        (len (length text)))
    (loop for i from 0 below len
          when (char= (char text i) (*info-sep*))
          do (push i starts))
    (setf starts (nreverse starts))
    (if (null starts)
        ;; not an .info file: one pseudo-node with the whole text.
        (progn
          (setf (gethash "(manual)" nodes)
                (make-info-node :name "(manual)" :text text))
          (setf (gethash "(manual)" nodes)
                (make-info-node :name "(manual)" :text text))
          (values (list "(manual)") nodes))
        (let ((entries nil))
          (dolist (s starts)
            (let* ((nl (or (position #\Newline text :start s) len))
                   (header (subseq text s nl))
                   (body-start (let ((p (position (*info-sep*) text :start (1+ s))))
                                 (or p len)))
                   (body-end (or (position (*info-sep*) text :start (1+ body-start))
                                 len))
                   (name (let ((n (search "Node: " header)))
                           (if n
                               (let ((comma (position #\, header :start (+ n 6))))
                                 (subseq header (+ n 6) (or comma (length header))))
                               (format nil "node-~a" s)))))
              (push (cons name (subseq text body-start body-end)) entries)
              (push name order)))
          (setf order (nreverse order))
          (dolist (e entries)
            (setf (gethash (car e) nodes)
                  (make-info-node :name (car e) :text (cdr e))))
          (values order nodes)))))

(defun info-open ()
  "M-x info — open the manual as an editable-in-principle, read-in-fact
buffer (Emacs Info keeps a copy too)."
  (interactive "")
  (let ((file (info-file)))
    (unless file
      (error "The Ymacs manual (.info) is not installed; see docs/emacs-manual/ymacs/"))
    (let* ((text (read-file-string file))
           (parse (multiple-value-list (info-parse text)))
           (order (first parse))
           (nodes (second parse))
           (first (first order))
           (name (format nil "*info: ymacs*"))
           (existing (find-if (lambda (b) (string= (buffer-name b) name))
                              (list-all-buffers))))
      (let ((buf (or existing
                     (make-new-buffer name (or (and first
                                                    (gethash first nodes)
                                                    (info-node-text (gethash first nodes)))
                                               "")))))
        ;; an info buffer is a VIEW: it is not user work, so the store law
        ;; does not apply to its mutations — we tag it (buffer-sync skips
        ;; views) and drop the durability row its creation wrote.
        (setf (gethash (buffer-id buf) *info-buffers*) t)
        (when *store* (ignore-errors (store-delete-buffer (buffer-id buf))))
        (setf (gethash name *info-by-name*) nodes)
        (setf *current-buffer* buf)
        (bump-document-version)
        buf))))

(defvar *info-buffers* (make-hash-table :test 'equal)
  "Buffer ids that are Info views (never persisted to the store).")
(defvar *info-by-name* (make-hash-table :test 'equal)
  "Buffer name -> node table of the open manual.")

(defun info-buffer-p (buf)
  (and buf (gethash (buffer-id buf) *info-buffers*)))

(defun info-show-node (buf node-name)
  (let ((nodes (gethash (buffer-name buf) *info-by-name*))
        (node (gethash node-name (gethash (buffer-name buf) *info-by-name*))))
    (when (and nodes node)
      (setf (buffer-rope buf) (rope-from-string (info-node-text node)))
      (setf (buffer-modified-p buf) nil)
      ;; view buffer: drop any durability row the create put there.
      (when *store* (ignore-errors (store-delete-buffer (buffer-id buf))))
      (bump-document-version)
      node-name)))



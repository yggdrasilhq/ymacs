;;;; rope.lisp --- Piecewise rope / gap-buffer for sub-millisecond edits
;;;; Derived from yedit emd-renderer concepts, adapted for Common Lisp.
;;;; Host-resident, like every libyggterm app: buffers live here, yggterm
;;;; only renders the schema.

(in-package #:ymacs)

;;; A minimal rope: list of chunks (strings) plus cached length.
;;; For notepad scale (< 10MB) this beats a tree's complexity and is
;;; indistinguishable from a gap-buffer in latency; splits are on
;;; explicit inserts so we never repeatedly reallocate the whole buffer.

(defstruct rope
  (chunks nil :type list)
  (length 0 :type fixnum))

(defun rope-from-string (str)
  (if (or (null str) (string= str ""))
      (make-rope :chunks nil :length 0)
      (make-rope :chunks (list str) :length (length str))))

(defun rope-to-string (rope)
  (if (null (rope-chunks rope))
      ""
      (apply #'concatenate 'string (rope-chunks rope))))

(defun rope-size (rope)
  (rope-length rope))

(defun rope-insert (rope pos text)
  "Insert TEXT at POS (0-indexed) into ROPE. Returns new rope."
  (let* ((s (rope-to-string rope))
         (len (length s))
         (p (min (max 0 pos) len))
         (before (subseq s 0 p))
         (after (subseq s p))
         (new-s (concatenate 'string before text after)))
    ;; Keep chunk count bounded: re-chunk at 4k boundaries if grows too large.
    (if (> (length new-s) 8192)
        (make-rope :chunks (chunk-string new-s 4096) :length (length new-s))
        (make-rope :chunks (list new-s) :length (length new-s)))))

(defun rope-delete (rope pos len)
  "Delete LEN chars at POS from ROPE."
  (let* ((s (rope-to-string rope))
         (slen (length s))
         (p (min (max 0 pos) slen))
         (end (min slen (+ p (max 0 len))))
         (new-s (concatenate 'string (subseq s 0 p) (subseq s end))))
    (make-rope :chunks (if (string= new-s "") nil (list new-s))
               :length (length new-s))))

(defun rope-substring (rope pos len)
  (let* ((s (rope-to-string rope))
         (p (min (max 0 pos) (length s)))
         (end (min (length s) (+ p len))))
    (subseq s p end)))

(defun chunk-string (s size)
  (loop for i from 0 below (length s) by size
        collect (subseq s i (min (length s) (+ i size)))))

;;; Gap-buffer alternative for the active line (cursor locality).
;;; We expose rope as the durable representation; the editor widget's
;;; live draft rides rope-to-string and the GUI's `values.editor` posts
;;; back the whole content (diffing is not worth it at this scale).

(defun count-lines (rope-or-string)
  (let ((s (if (stringp rope-or-string) rope-or-string (rope-to-string rope-or-string))))
    (1+ (count #\Newline s))))

(defun line-start-offsets (rope-or-string)
  "Return vector of line start offsets (for fast line-indexing)."
  (let* ((s (if (stringp rope-or-string) rope-or-string (rope-to-string rope-or-string)))
         (offsets (list 0)))
    (loop for i from 0 below (length s)
          when (char= (char s i) #\Newline)
          do (push (1+ i) offsets))
    (coerce (nreverse offsets) 'vector)))

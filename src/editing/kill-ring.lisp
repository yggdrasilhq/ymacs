;;;; kill-ring.lisp --- Kill ring (clipboard history) for ymacs
;;;; Like Emacs, kill-ring is a list of killed texts, yank pops.

(in-package #:ymacs)

(defvar *kill-ring* nil)
(defvar *kill-ring-max* 60)
(defvar *kill-ring-yank-pointer* nil)

(defun kill-ring-push (text)
  (when (and text (plusp (length text)))
    (push text *kill-ring*)
    (when (> (length *kill-ring*) *kill-ring-max*)
      (setf *kill-ring* (subseq *kill-ring* 0 *kill-ring-max*)))
    (setf *kill-ring-yank-pointer* *kill-ring*)
    (fire-probe :ymacs-kill-ring :operation "kill" :length (length text))))

(defun kill-region-in-buffer (buf start end)
  (let* ((s (min start end)) (e (max start end))
         (text (rope-substring (buffer-rope buf) s (- e s))))
    (kill-ring-push text)
    (buffer-delete-with-undo buf s (- e s))
    text))

(defun kill-line-in-buffer (buf)
  (let* ((content (buffer-content buf))
         (pt (buffer-point buf))
         (eol (or (position #\Newline content :start pt) (length content)))
         (text (subseq content pt (if (< eol (length content)) (1+ eol) eol))))
    (kill-ring-push text)
    (buffer-delete-with-undo buf pt (length text))
    text))

(defun yank-into-buffer (buf)
  (when *kill-ring-yank-pointer*
    (let ((text (first *kill-ring-yank-pointer*)))
      (buffer-insert-with-undo buf (buffer-point buf) text)
      (incf (buffer-point buf) (length text))
      text)))

(defun yank-pop-into-buffer (buf)
  (when (and *kill-ring-yank-pointer* (cdr *kill-ring-yank-pointer*))
    (let* ((prev (first *kill-ring-yank-pointer*))
           (next (second *kill-ring-yank-pointer*)))
      ;; Delete previous yank
      (buffer-delete buf (- (buffer-point buf) (length prev)) (length prev))
      (buffer-insert buf (- (buffer-point buf) (length prev)) next)
      (setf *kill-ring-yank-pointer* (cdr *kill-ring-yank-pointer*))
      next)))

(defun kill-ring-push-copy (text)
  (kill-ring-push text))

(defun kill-ring-clear ()
  (setf *kill-ring* nil
        *kill-ring-yank-pointer* nil))

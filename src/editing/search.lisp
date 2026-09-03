;;;; search.lisp --- Incremental search (isearch) for ymacs

(in-package #:ymacs)

(defvar *isearch-string* "")
(defvar *isearch-forward* t)
(defvar *isearch-regexp* nil)
(defvar *isearch-case-fold* t)
(defvar *isearch-overlays* nil)

(defun search-buffer-forward (buf str &key (from (buffer-point buf)) regexp case-fold)
  (let* ((content (buffer-content buf))
         (search-str (if case-fold (string-downcase str) str))
         (haystack (if case-fold (string-downcase content) content))
         (pos (if regexp
                  (ymacs-search-regexp search-str haystack :start from)
                  (cl:search search-str haystack :start2 from))))
    (when pos
      (setf (buffer-point buf) pos
            (buffer-mark buf) (+ pos (length str)))
      (bump-document-version)
      pos)))

(defun search-buffer-backward (buf str &key (from (buffer-point buf)) regexp case-fold)
  (let* ((content (buffer-content buf))
         (search-str (if case-fold (string-downcase str) str))
         (haystack (if case-fold (string-downcase content) content))
         (pos (if regexp
                  (ymacs-search-regexp-backward search-str haystack :end from)
                  (ymacs-search-backward search-str haystack :end from))))
    (when pos
      (setf (buffer-point buf) pos
            (buffer-mark buf) (+ pos (length str)))
      (bump-document-version)
      pos)))

(defun ymacs-search-backward (needle haystack &key (end (length haystack)))
  (cl:search needle haystack :end2 end :from-end t))

(defun ymacs-search-regexp (pattern str &key (start 0))
  (if (find-package :cl-ppcre)
      (let ((scanner (funcall (find-symbol "CREATE-SCANNER" :cl-ppcre) pattern :case-insensitive-mode *isearch-case-fold*)))
        (multiple-value-bind (s e) (funcall (find-symbol "SCAN" :cl-ppcre) scanner str :start start)
          (declare (ignore e))
          (when s s)))
      (cl:search pattern str :start2 start)))

(defun ymacs-search-regexp-backward (pattern str &key (end (length str)))
  (declare (ignore end))
  ;; Simplified: no backward regexp without cl-ppcre; fallback to plain backward
  (ymacs-search-backward pattern str :end (length str)))

(defun isearch-occurrences (buf pattern &key regexp)
  (let ((content (buffer-content buf)) (out nil))
    (if regexp
        (if (find-package :cl-ppcre)
            (let ((scanner (funcall (find-symbol "CREATE-SCANNER" :cl-ppcre) pattern)))
              (declare (ignore scanner))
              (loop for pos = (cl:search pattern content :start2 0) then (cl:search pattern content :start2 (1+ pos))
                    while pos do (push (cons pos (subseq content pos (min (length content) (+ pos 80)))) out)))
            (loop for pos = (cl:search pattern content :start2 0) then (cl:search pattern content :start2 (1+ pos))
                  while pos do (push (cons pos (subseq content pos (min (length content) (+ pos 80)))) out)))
        (loop for pos = (cl:search pattern content :start2 0) then (cl:search pattern content :start2 (1+ pos))
              while pos do (push (cons pos (subseq content pos (min (length content) (+ pos 80)))) out)))
    (nreverse out)))

(defun query-replace (buf from to &key regexp)
  (let ((content (buffer-content buf)) (count 0))
    (if regexp
        (if (find-package :cl-ppcre)
            (let ((new (funcall (find-symbol "REGEX-REPLACE-ALL" :cl-ppcre) from content to)))
              (setf count (if (string= new content) 0 1))
              (when (> count 0)
                (push-undo buf)
                (setf (buffer-rope buf) (rope-from-string new)
                      (buffer-modified-p buf) t)
                (bump-document-version)))
            (error "regexp replace requires cl-ppcre"))
        (let ((new content) (pos 0))
          (loop while (setf pos (cl:search from new :start2 pos))
                do (progn
                     (setf new (concatenate 'string (subseq new 0 pos) to (subseq new (+ pos (length from)))))
                     (incf pos (length to))
                     (incf count)))
          (when (> count 0)
            (push-undo buf)
            (setf (buffer-rope buf) (rope-from-string new)
                  (buffer-modified-p buf) t)
            (bump-document-version))))
    count))

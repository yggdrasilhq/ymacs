;;;; elisp-reader.lisp --- an Emacs Lisp reader for the ELPA compat layer
;;;;
;;;; Step 8 instrument front end (docs/spec-primitives.md §5): reads real
;;;; .el sources with Elisp token syntax — ?c character literals (Elisp
;;;; chars are integers, with composable \C- \M- \S- \A- \H- \s- modifier
;;;; escapes), lenient string escapes, [a b c] vector literals — so
;;;; corpus measurement starts from a faithful read instead of a CL-read
;;;; coincidence. Elisp has no package system but the CL reader cannot
;;;; unlearn its package markers, so a symbol like
;;;; use-package-normalize/:keyword triggers the on-demand package shim
;;;; below (the reader's one place it invents structure, and it invents
;;;; it consistently — every occurrence resolves to the same symbol).
;;;; The reader never guesses semantics: what it cannot read, it reports,
;;;; and the corpus records the file at depth 0. Known divergence: the
;;;; backslash-newline string continuation keeps the newline instead of
;;;; eliding it (rare in the corpus, honest in the report).

(in-package #:ymacs)

(define-condition elisp-read-error (reader-error)
  ((reason :initarg :reason :reader elisp-read-error-reason))
  (:report (lambda (c s) (format s "elisp read error: ~a" (elisp-read-error-reason c)))))

(defvar *elisp-readtable* (copy-readtable nil)
  "Standard readtable with the two Elisp token divergences installed.")

;;; --- escape table (shared by string and character syntax) ----------------

(defun elisp-read-hex (stream &optional (max 6))
  (let ((val 0) (n 0))
    (loop while (< n max)
          for p = (peek-char nil stream nil nil)
          while (and p (digit-char-p p 16))
          do (setf val (+ (* val 16) (digit-char-p (read-char stream) 16))
                   n (1+ n)))
    val))

(defun elisp-escape-code (stream)
  "Consume one backslash escape, return its character code.
   Unknown escapes read as the literal character (lenient, like Elisp).
   Modifier prefixes \C- \M- \S- \A- \H- \s- compose and nest (?M-\C-a,
   ?\A-\0); the modifier bits are this reader's own choice — they are
   data in the corpus, never compared against real key events."
  (let ((c (read-char stream)))
    (flet ((dash-p ()
             (let ((p (peek-char nil stream nil nil))) (and p (char= p #\-)))))
      (cond
        ;; modifier prefixes — composable, may nest (?M-\C-a, ?\s-\C-a)
        ((and (member c '(#\C #\M #\S #\A #\H #\s)) (dash-p))
         (read-char stream)
         (let ((p (peek-char nil stream nil nil)))
           (let ((base (if (and p (char= p #\\))
                           (progn (read-char stream) (elisp-escape-code stream))
                           (char-code (read-char stream)))))
             (case c
               (#\C (if (= base 63) 127 (logand base 31)))
               (#\M (logior base #x2000000))
               (#\S (logior base #x4000000))
               (#\A (logior base #x8000000))
               (#\H (logior base #x10000000))
               (t   (logior base #x20000000))))))   ; \s- = super
        ((char= c #\n) 10)
      ((char= c #\t) 9)
      ((char= c #\r) 13)
      ((char= c #\a) 7)
      ((char= c #\b) 8)
      ((char= c #\f) 12)
      ((char= c #\v) 11)
      ((char= c #\e) 27)
      ((char= c #\d) 127)
      ((char= c #\s) 32)
      ((char= c #\newline) 10)
      ((char= c #\x) (elisp-read-hex stream))
      ((char= c #\u) (elisp-read-hex stream 4))
      ((char= c #\U) (elisp-read-hex stream 8))
      ((digit-char-p c 8)
       (let ((val (digit-char-p c 8)))
         (loop repeat 2
               for p = (peek-char nil stream nil nil)
               while (and p (digit-char-p p 8))
               do (setf val (+ (* val 8) (digit-char-p (read-char stream) 8))))
         val))
      (t (char-code c))))))

;;; --- string literal -------------------------------------------------------

(defun elisp-read-string (stream char)
  (declare (ignore char))
  (let ((out (make-array 0 :element-type 'character :fill-pointer 0 :adjustable t)))
    (loop
      (let ((c (read-char stream)))
        (cond ((char= c #\") (return out))
              ((char= c #\\)
               (vector-push-extend (code-char (elisp-escape-code stream)) out))
              (t (vector-push-extend c out)))))))

;;; --- character literal ----------------------------------------------------

(defun elisp-read-char (stream char)
  (declare (ignore char))
  ;; Elisp characters are integers. Modifier composition happens inside
  ;; the escape (?  \C-\M-x, ?\A-\0 — the escape consumes its own dash
  ;; and base), so nothing chains at this level.
  (let ((p (peek-char nil stream)))
    (if (char= p #\\)
        (progn (read-char stream) (elisp-escape-code stream))
        (char-code (read-char stream)))))

;;; --- vector literal ---------------------------------------------------------

(defun elisp-read-vector (stream char)
  (declare (ignore char))
  ;; Elisp [a b c] — commas inside work (a backquote template may splice
  ;; into a vector), ] closes like ).
  (coerce (read-delimited-list #\] stream t) 'vector))

(set-macro-character #\" #'elisp-read-string nil *elisp-readtable*)
(set-macro-character #\? #'elisp-read-char nil *elisp-readtable*)
(set-macro-character #\[ #'elisp-read-vector t *elisp-readtable*)
(set-syntax-from-char #\] #\) *elisp-readtable*)

;;; --- the missing package system ---------------------------------------------
;;;;
;;;; Elisp has no package system, but the CL reader hard-codes package
;;;; markers into its tokenizer — no readtable treatment turns them off,
;;;; so `use-package-normalize/:keyword' parses as a package-qualified
;;;; symbol. The shim: when the reader reports a missing package, create
;;;; it (empty) and re-read the form. Every occurrence, in every file,
;;;; then resolves to the same symbol — which is all Elisp ever promised.

(defun elisp-missing-package-name (err)
  "The missing-package name from a reader error, or nil when ERR is
some other reader error."
  (let ((m (princ-to-string err)))
    (when (search "does not exist" m)
      (let* ((s (search "Package" m))
             (e (search " does not exist" m)))
        (when (and s e)
          (let ((name (string-trim '(#\" #\space) (subseq m (+ s 7) e))))
            (and (plusp (length name)) name)))))))

(defun elisp-missing-external-symbol (err)
  "The (symbol package) from a reader error like `Symbol \"X\" not
found in the Y package.', or nil when ERR is something else."
  (let ((m (princ-to-string err)))
    (when (search "not found in the" m)
      (let ((s1 (search "Symbol \"" m))
            (s2 (search "\" not found in the " m))
            (s3 (search " package." m)))
        (when (and s1 s2 s3)
          (values (subseq m (+ s1 8) s2)
                  (subseq m (+ s2 19) s3)))))))

(defun elisp-read-form (stream eof)
  "Read one form from STREAM; EOF is the eof value. Missing packages --
and missing external symbols in them -- are created on demand and the
form re-read (the package shim)."
  (let ((start (file-position stream))
        (retries 0))
    (loop
      (handler-case (return (read stream nil eof nil))
        (reader-error (e)
          (incf retries)
          (when (> retries 100)
            (error "elisp reader: package shim retry cap hit (~a)" e))
          (let ((pkg (elisp-missing-package-name e)))
            (cond (pkg
                   (unless (find-package pkg)
                     (make-package pkg :use '())))
                  (t
                   (multiple-value-bind (sym package)
                       (elisp-missing-external-symbol e)
                     (unless (and sym package) (error e))
                     (let ((p (or (find-package package)
                                  (make-package package :use '()))))
                       (multiple-value-bind (s found)
                           (find-symbol sym p)
                         (unless found (setf s (intern sym p)))
                         (export s p))))))
            (file-position stream start)))))))

;;; --- entry points ---------------------------------------------------------

(defun read-elisp-forms (path)
  "Read every top-level form of an Elisp file.
   Second value non-nil on a read failure (partial forms still returned)."
  (let ((forms '()) (failure nil) (eof (cons 'elisp-eof nil)))
    (handler-case
        (with-open-file (s path :direction :input :element-type 'character
                                :external-format :utf-8)
          (let ((*readtable* *elisp-readtable*)
                (*read-eval* nil)
                (*package* (find-package :ymacs-elisp)))
            (loop
              (let ((form (elisp-read-form s eof)))
                (when (eq form eof) (return))
                (push form forms)))))
      (error (e) (setf failure (format nil "~a" e))))
    (values (nreverse forms) failure)))

(defun read-elisp-string (s)
  "Read Elisp forms from a string. Same two values as read-elisp-forms."
  (let ((forms '()) (failure nil) (eof (cons 'elisp-eof nil)))
    (handler-case
        (with-input-from-string (stream s)
          (let ((*readtable* *elisp-readtable*)
                (*read-eval* nil)
                (*package* (find-package :ymacs-elisp)))
            (loop
              (let ((form (elisp-read-form stream eof)))
                (when (eq form eof) (return))
                (push form forms)))))
      (error (e) (setf failure (format nil "~a" e))))
    (values (nreverse forms) failure)))

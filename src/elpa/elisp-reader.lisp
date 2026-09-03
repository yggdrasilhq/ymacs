;;;; elisp-reader.lisp --- an Emacs Lisp reader for the ELPA compat layer
;;;;
;;;; Step 8 instrument front end (docs/spec-primitives.md §5): reads real
;;;; .el sources with Elisp token syntax — ?c character literals (Elisp
;;;; chars are integers), lenient string escapes — so corpus measurement
;;;; starts from a faithful read instead of a CL-read coincidence.
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
   Unknown escapes read as the literal character (lenient, like Elisp)."
  (let ((c (read-char stream)))
    (cond
      ;; modifier prefixes \C- \M- \S- — composable, may nest (?M-\C-a)
      ((and (member c '(#\C #\M #\S))
            (let ((p (peek-char nil stream nil nil))) (and p (char= p #\-))))
       (read-char stream)
       (let ((p (peek-char nil stream nil nil)))
         (let ((base (if (and p (char= p #\\))
                         (progn (read-char stream) (elisp-escape-code stream))
                         (char-code (read-char stream)))))
           (case c
             (#\C (if (= base 63) 127 (logand base 31)))
             (#\M (logior base #x2000000))
             (t   (logior base #x4000000))))))
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
      (t (char-code c)))))

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
  ;; Elisp characters are integers.
  (let ((p (peek-char nil stream)))
    (if (char= p #\\)
        (progn (read-char stream) (elisp-escape-code stream))
        (char-code (read-char stream)))))

(set-macro-character #\" #'elisp-read-string nil *elisp-readtable*)
(set-macro-character #\? #'elisp-read-char nil *elisp-readtable*)

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
              (let ((form (read s nil eof nil)))
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
              (let ((form (read stream nil eof nil)))
                (when (eq form eof) (return))
                (push form forms)))))
      (error (e) (setf failure (format nil "~a" e))))
    (values (nreverse forms) failure)))

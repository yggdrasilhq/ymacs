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
               ;; Emacs strings carry 22-bit chars; CL strings stop at
               ;; #x10FFFF — and SBCL's code-char SIGNALS past the impl
               ;; range rather than returning NIL. Out-of-range escapes
               ;; (pcomplete's \x3FFF7F) land as U+FFFD, guarded BEFORE
               ;; the call — a documented v0 divergence: corpus data,
               ;; never compared (the modifier-bit stance).
               (let ((code (elisp-escape-code stream)))
                 (vector-push-extend
                  (if (<= code #x10FFFF) (code-char code) #\U+FFFD) out)))
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
(set-macro-character #\? #'elisp-read-char t *elisp-readtable*)
(set-macro-character #\[ #'elisp-read-vector t *elisp-readtable*)
;; A token-start colon is an Elisp keyword (:type); a LONE colon —
;; `(: sym ...)` inside rx patterns — is the empty-name symbol Emacs
;; accepts and the standard reader rejects. Non-terminating, so
;; mid-symbol colons (pkg:sym, org:link) never reach this handler.
(defun elisp-read-colon (stream char)
  (declare (ignore char))
  (flet ((delimiter-p (c)
           (or (null c)
               (member c '(#\Space #\Newline #\Tab #\Return
                           #\( #\) #\` #\' #\, #\; #\")))))
    (let ((next (peek-char nil stream nil nil)))
      (if (delimiter-p next)
          (progn (read-char stream)
                 (intern ":" (find-package :ymacs-elisp)))
          (let ((token (with-output-to-string (out)
                         (loop for c = (peek-char nil stream nil nil)
                               while (not (delimiter-p c))
                               do (write-char (read-char stream) out)))))
            ;; the standard readtable reads :upcase — keywords match
            (intern (string-upcase token) (find-package :keyword)))))))

(set-macro-character #\: #'elisp-read-colon t *elisp-readtable*)
;; The comma-tolerant twin readtable: define-inline bodies contain
;; `,x` outside a backquote (the macro splices them itself), which the
;; standard reader rejects. On that error the form is re-read once with
;; `,` as a constituent — commas glue to the following symbol, the form
;; parses, and define-inline registers without its body ever evaluating.
(defparameter *elisp-readtable-comma* (copy-readtable *elisp-readtable*))
(set-syntax-from-char #\, #\A *elisp-readtable-comma*)
;; NOTE: mid-token colons (org-duration's `h:mm:ss` format symbols)
;; are NOT fixable at readtable level — SBCL's tokenizer hard-codes
;; package markers, no readtable treatment turns them off (measured
;; 2026-09-08: a colon-constituent twin readtable still raises "too
;; many colons"). Fixing that wants a real elisp tokenizer; queued.
(set-syntax-from-char #\] #\) *elisp-readtable*)
;; elisp's `|` is an ordinary symbol character (rx or-patterns: `(| "a"
;; "b")`); CL's multi-escape delimiter would swallow to the next `|`
;; — dash.el's font-lock rx ate the rest of the file that way.
(set-syntax-from-char #\| #\A *elisp-readtable*)
;; elisp's `##` token (obsolete self-reference, appears in
;; declare-function arglists — org-list.el) — CL's # dispatch would
;; demand a label integer. Read it as the plain symbol `##`.
(set-dispatch-macro-character #\# #\#
                              (lambda (stream sub-char numarg)
                                (declare (ignore stream sub-char numarg))
                                '|##|)
                              *elisp-readtable*)
;; elisp bool-vector literal #&[SIZE]"STRING" (ansi-color's init data)
;; — v0 unpacks to a simple bit vector, MSB-first per byte (the elisp
;; packed representation). The bool-vector function family is future
;; work; the literal only needs to read to a faithful object.
(set-dispatch-macro-character #\# #\&
                              (lambda (stream sub-char numarg)
                                (declare (ignore sub-char numarg))
                                (let ((digits (loop for c = (peek-char nil stream nil nil)
                                                    while (and c (digit-char-p c))
                                                    collect (read-char stream))))
                                  (let* ((size (when digits
                                                 (parse-integer (coerce digits 'string))))
                                         (str (read stream t))
                                         (bytes (map 'list #'char-code str))
                                         (n (or size (* 8 (length bytes))))
                                         (bits (make-array n :element-type 'bit
                                                           :initial-element 0)))
                                    (loop for bi below n
                                          for byte = (nth (floor bi 8) bytes)
                                          when (logbitp (- 7 (mod bi 8)) byte)
                                            do (setf (aref bits bi) 1))
                                    bits)))
                              *elisp-readtable*)

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
form re-read (the package shim). A stray comma outside a backquote
(define-inline bodies) re-reads once through the comma-tolerant
readtable."
  (let ((start (file-position stream))
        (retries 0)
        (comma-error nil))
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
                  ((search "Comma not inside" (format nil "~a" e))
                   ;; re-read once with commas as constituents. The
                   ;; failed read consumed up to the stray comma, so
                   ;; the retry MUST rewind to the form start —
                   ;; re-reading mid-form left `))))` strays and the
                   ;; file died on "unmatched close parenthesis"
                   ;; (org-element-ast.el, fixed 2026-09-08).
                   (when comma-error (error e))
                   (setf comma-error t)
                   (file-position stream start)
                   (let ((*readtable* *elisp-readtable-comma*))
                     (return (read stream nil eof nil))))
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
   Second value non-nil on a read failure (partial forms still
   returned). The file is DECODED TO A STRING first: on an fd-stream,
   file-position returns byte offsets while the reader's arithmetic is
   character-based, so one multibyte char (a single § in dash.el)
   shifts every package/comma retry restore by a byte and silently
   eats the rest of the file (measured 2026-09-08). String streams
   keep file-position char-consistent."
  (let ((text (with-open-file (s path :direction :input
                                      :external-format :utf-8)
                (with-output-to-string (out)
                  (loop for line = (read-line s nil nil)
                        while line
                        do (write-line line out))))))
    (read-elisp-string text)))

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

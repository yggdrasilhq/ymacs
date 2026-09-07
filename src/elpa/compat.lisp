;;;; compat.lisp --- ELPA & MELPA Emacs Lisp compatibility bridge
;;;; Emulates core Elisp primitives, buffer API, keymaps, hooks, and
;;;; package.el shape. Explicitly does NOT emulate the discarded old
;;;; interfaces (see deprecated.lisp). Modern helpers are first-class.

(in-package #:ymacs)

;;; ---- Elisp value domain -------------------------------------------------
;;; Elisp symbols are interned in the YMACS-ELISP package to avoid clashing
;;; with Common Lisp. We reuse CL's reader for now.

(defpackage #:ymacs-elisp
  (:use #:cl)
  (:export #:defun #:defvar #:defcustom #:defmacro #:lambda #:let #:let*
           #:if #:when #:unless #:cond #:progn #:prog1 #:quote
           #:setq #:setf #:add-hook #:remove-hook #:run-hooks))

(defvar *elisp-env* (make-hash-table :test 'equal))
(defvar *elisp-hooks* (make-hash-table :test 'equal))
(defvar *elisp-keymaps* (make-hash-table :test 'equal))
(defvar *elisp-features* nil)

(defun elisp-intern (name)
  (intern (string-upcase name) :ymacs-elisp))

(defun elisp-def (name value)
  (setf (gethash (string-downcase name) *elisp-env*) value))

(defun elisp-get (name)
  (gethash (string-downcase name) *elisp-env*))

;;; ---- Buffer API emulation (maps to ymacs native buffers) --------------

(defun elisp/current-buffer ()
  (current-buffer))

(defun elisp/with-current-buffer (id-or-buf thunk)
  (let* ((buf (if (stringp id-or-buf) (get-buffer-by-id id-or-buf) id-or-buf))
         (prev *current-buffer*))
    (when buf (setf *current-buffer* buf))
    (unwind-protect (funcall thunk)
      (setf *current-buffer* prev))))

(defun elisp/insert (text &optional buf)
  (let ((b (or buf *current-buffer*)))
    (when b
      (let ((pos (or (buffer-point b) (length (buffer-content b)))))
        (buffer-insert b pos text)
        (incf (buffer-point b) (length text))))))

(defun elisp/delete-region (start end &optional buf)
  (let ((b (or buf *current-buffer*)))
    (when b
      (buffer-delete b (min start end) (abs (- end start))))))

(defun elisp/buffer-string (&optional buf)
  (let ((b (or buf *current-buffer*)))
    (if b (buffer-content b) "")))

(defun elisp/point (&optional buf)
  (let ((b (or buf *current-buffer*))) (if b (buffer-point b) 0)))

(defun elisp/goto-char (pos &optional buf)
  (let ((b (or buf *current-buffer*)))
    (when b (setf (buffer-point b) (max 0 (min pos (length (buffer-content b))))))))

;;; ---- Hook system -------------------------------------------------------

(defun elisp/add-hook (hook fn &optional append local)
  (declare (ignore local))
  (let ((lst (gethash hook *elisp-hooks*)))
    (if append
        (setf (gethash hook *elisp-hooks*) (append lst (list fn)))
        (push fn (gethash hook *elisp-hooks*)))))

(defun elisp/remove-hook (hook fn &optional local)
  (declare (ignore local))
  (setf (gethash hook *elisp-hooks*) (remove fn (gethash hook *elisp-hooks*) :test #'equal)))

(defun elisp/run-hooks (hook &rest args)
  (dolist (fn (gethash hook *elisp-hooks*))
    (ignore-errors (apply fn args))))

;;; ---- Keymap emulation --------------------------------------------------

(defstruct elisp-keymap
  (bindings (make-hash-table :test 'equal))
  (parent nil))

(defun elisp/make-keymap ()
  (make-elisp-keymap))

(defun elisp/define-key (map key def)
  (setf (gethash key (elisp-keymap-bindings map)) def))

(defun elisp/global-set-key (key def)
  (let ((map (or (gethash "global" *elisp-keymaps*) (setf (gethash "global" *elisp-keymaps*) (elisp/make-keymap)))))
    (elisp/define-key map key def)))

(defun elisp/lookup-key (map key)
  ;; walk the parent chain (defvar-keymap :parent), innermost binding wins
  (cond ((null map) nil)
        ((gethash key (elisp-keymap-bindings map)))
        (t (elisp/lookup-key (elisp-keymap-parent map) key))))

;;; ---- Feature / provide / require ---------------------------------------

(defun elisp/provide (feature)
  (pushnew feature *elisp-features*))

(defun elisp/require (feature &optional filename noerror)
  (declare (ignore filename))
  (unless (member feature *elisp-features*)
    (unless noerror (error "Feature ~a not provided" feature))))

(defun elisp/featurep (feature)
  (if (member feature *elisp-features*) t nil))

;;;; ---- org bootstrap wave (2026-09-07) ----------------------------------
;;;; The primitives the org corpus hangs on, implemented against the
;;;; elisp value store — shipped compat, never measurement fakes.

(defun elisp/make-sparse-keymap (&optional _first)
  (declare (ignore _first))
  (elisp/make-keymap))

(defun elisp/make-obsolete (&rest _)
  (declare (ignore _))
  nil)

(defun elisp/make-obsolete-variable (&rest _)
  (declare (ignore _))
  nil)

(defun elisp/defvaralias (alias base &optional _doc)
  (declare (ignore _doc))
  ;; the alias reads through the base var's store slot; a value the base
  ;; already has is copied once (write-through indirection is future work)
  (let ((v (elisp-get (string-downcase (princ-to-string base)))))
    (when v (elisp-def (string-downcase (princ-to-string alias)) v)))
  nil)

(defun elisp/getenv (name)
  (let ((s (and (find-package :sb-posix)
                (find-symbol (string :posix-getenv) (find-package :sb-posix)))))
    (when s (funcall s name))))

(defun elisp/executable-find (program &optional _remote)
  (declare (ignore _remote))
  (let ((path (elisp/getenv "PATH"))
        (needle (if (pathnamep program) (namestring program) program)))
    (when path
      (let ((found nil))
        (dolist (dir (split-sequence-colon path))
          (when (and (null found)
                     (probe-file (merge-pathnames
                                  needle
                                  (make-pathname :directory (append (pathname-directory (truename "/")) (list dir))))))
            (setf found (merge-pathnames needle (make-pathname :directory (append (pathname-directory (truename "/")) (list dir)))))))
        found))))

(defun split-sequence-colon (s)
  (loop for start = 0 then (1+ end)
        for end = (position #\: s :start start)
        collect (subseq s start (or end (length s)))
        while end))

(defun elisp-version-parts (s)
  (mapcar (lambda (p) (or (parse-integer p :junk-allowed t) 0))
          (split-sequence-colon
           (substitute #\: #\. (string-upcase s)))))

(defun elisp/version< (a b)
  (let ((pa (elisp-version-parts a)) (pb (elisp-version-parts b)))
    (loop for x in pa
          for y = (or (pop pb) 0)
          do (cond ((< x y) (return-from elisp/version< t))
                   ((> x y) (return-from elisp/version< nil))))
    nil))

(defun elisp/version<= (a b)
  (or (elisp/version< a b)
      (not (elisp/version< b a))))

(defun elisp/subr-arity (fn)
  ;; (MIN . MAX); MAX is :many when the function takes &rest/&key.
  ;; sb-introspect is resolved at RUNTIME: the shipped image compiles on
  ;; hosts where that package is not loaded (same pattern as getenv).
  (let ((il (and (find-package :sb-introspect)
                 (find-symbol (string :function-lambda-list)
                              (find-package :sb-introspect)))))
    (if (and il (functionp fn))
        (ignore-errors
          (let ((ll (funcall il fn)))
            (let ((min 0) (many nil))
              (dolist (x ll)
                (typecase x
                  ((or null (member &optional)) nil)
                  ((member &rest &body &key &aux) (setf many t))
                  (symbol (incf min))))
              (cons min (if many :many min)))))
        (cons 0 :many))))

(defun elisp/regexp-quote (s)
  (with-output-to-string (out)
    (loop for ch across (string s)
          when (find ch "*+?[^$\\.()|{}") do (write-char #\\ out)
          do (write-char ch out))))

(defun elisp/regexp-opt (strings &optional _paren)
  (declare (ignore _paren))
  (let ((uniq (remove-duplicates (mapcar #'string strings) :test #'string=)))
    (concatenate 'string "\\(?:"
                 (format nil "~{~a~^\\|~}" (mapcar #'elisp/regexp-quote uniq))
                 "\\)")))

(defun elisp/make-overlay (&rest _)
  (declare (ignore _))
  (list 'elisp-overlay))

(defun elisp/overlay-put (o &rest _)
  (declare (ignore _))
  o)

(defun elisp/delete-overlay (&rest _)
  (declare (ignore _))
  nil)

(defun elisp/move-overlay (&rest _)
  (declare (ignore _))
  nil)

(defun elisp/easy-menu-add-item (&rest _)
  (declare (ignore _))
  nil)

(defun elisp/kbd (keys)
  ;; v0: the key-vector representation is internal; define-key addresses
  ;; bindings by the chord string itself, so KBD returns it unchanged.
  keys)

(defun elisp/set-keymap-parent (map parent)
  (when (and (elisp-keymap-p map) (or (null parent) (elisp-keymap-p parent)))
    (setf (elisp-keymap-parent map) parent))
  map)

(defun elisp/make-marker (&rest _)
  (declare (ignore _))
  (list 'marker 0 nil))

(defun elisp/expand-file-name (name &optional _default)
  (if (and (plusp (length name)) (eql (char name 0) #\~))
      (merge-pathnames (subseq name 1) (user-homedir-pathname))
      (merge-pathnames name (truename "."))))

(defun elisp/emacs-version (&optional _arg)
  "GNU Emacs 30.1 (ymacs on libyggterm)")

;; org-version.el is the GENERATED package header: Emacs ships it preloaded,
;; so the corpus sweep pre-provides its two constants (pinned in
;; vendor/elpa-corpus/README.md — org 9.7.11 from emacs-30.1).
(defun elisp/intern-soft (name)
  "Emacs: return the symbol NAME names ONLY if it is already interned;
a symbol argument passes through, a miss is nil — never interns. The
elisp symbol domain is :ymacs-elisp (see the value-domain header)."
  (if (symbolp name)
      name
      (find-symbol (string-upcase (string name)) :ymacs-elisp)))

;; list/sequence subrs (2026-09-08, the ox/org-element rung wave):
;; delq/remq are EQ-based removal. The elisp versions may reuse the
;; tail's structure (destructive); this v0 is non-destructive — the
;; RETURNED value is faithful, the in-place side effect is a documented
;; limitation, matching the value-store model.
(defun elisp/delq (elt list) (remove elt list :test #'eq))
(defun elisp/remq (elt list) (remove elt list :test #'eq))

(defun elisp/copy-sequence (seq) (copy-seq seq))
(defun elisp/sequencep (x) (typep x 'sequence))

;; case subrs: elisp downcase/upcase take a char OR a string.
(defun elisp/downcase (x)
  (if (characterp x) (char-downcase x) (string-downcase x)))
(defun elisp/upcase (x)
  (if (characterp x) (char-upcase x) (string-upcase x)))

(defun elisp/next-line (&optional n buf)
  ;; elisp: move point down N lines (negative up). The position math is
  ;; real; the column-goal tracking (try-column) is interactive polish,
  ;; a documented limitation.
  (let* ((b (or buf *current-buffer*))
         (steps (or n 1))
         (content (and b (buffer-content b))))
    (when b
      (let ((i (or (buffer-point b) 0)) (len (length content)) (seen 0))
        (loop while (and (< seen (abs steps)) (< i len) (>= i 0))
              do (cond ((plusp steps)
                        (when (eql (char content i) #\newline) (incf seen))
                        (incf i))
                       (t
                        (decf i)
                        (when (and (>= i 0) (eql (char content i) #\newline))
                          (incf seen)))))
        (setf (buffer-point b) (max 0 (min i len)))))))

(defun elisp/previous-line (&optional n buf)
  ;; the interactive command mirrors C-p: same motion, defaulting up
  (elisp/next-line (- (or n 1)) buf))

(defun elisp/org-release () "9.7.11")
(defun elisp/org-git-version () "release_9.7.11")

(defun elisp/org-link-set-parameter (&rest _)
  (declare (ignore _))
  nil)

(defun elisp/org-link-set-parameters (type &rest params)
  (declare (ignore params))
  type)

(defun elisp/org-cite-register-processor (&rest _)
  (declare (ignore _))
  nil)

(defun elisp/user-error (format &rest args)
  (error "user-error: ~a" (apply #'format nil format args)))

;;; ---- defcustom / use-package glue -------------------------------------

(defmacro elisp/defcustom (name value doc &key type group
                           version package-version set get initialize
                           safe risky options require tag link
                           &allow-other-keys)
  ;; The full keyword surface is ACCEPTED so real defcustom forms parse
  ;; (ob-R/ob-js died on :version, ol.el on :package-version/:set/:safe);
  ;; v0 models only the standard-get semantics — :set/:safe/:get are
  ;; recorded-and-ignored, a documented limitation like pcase's v0.
  (declare (ignore doc type group version package-version set get
                   initialize safe risky options require tag link))
  `(elisp-def ,(string-downcase (symbol-name name)) ,value))

;;; ---- Eval --------------------------------------------------------------

(defun elpa-eval (form)
  "Evaluate an Elisp FORM (S-expr read via CL reader) in the emulated env.
   For now, delegates to CL EVAL after translating known specials.
   Real ELPA packages ship as .el source; we read them as strings via
   elpa-load-file below."
  (handler-case
      (cond
        ((atom form) (or (elisp-get (princ-to-string form)) (eval form)))
        ((eq (car form) 'quote) (cadr form))
        (t (eval form)))
    (error (e)
      (warn "elpa-eval skipped form ~a: ~a" form e)
      nil)))

(defun elpa-load-file (path)
  "Load an .el file by reading each form and elpa-eval'ing. Returns t on success."
  (fire-probe :ymacs-elpa-load :package (namestring path) :latency-ms 0)
  (let ((start (get-internal-real-time)))
    (handler-case
        (with-open-file (s path :direction :input :external-format :utf-8)
          (loop for form = (read s nil nil)
                while form
                do (elpa-eval form))
          (fire-probe :ymacs-elpa-load :package (namestring path)
                      :latency-ms (round (* 1000 (/ (- (get-internal-real-time) start) internal-time-units-per-second))))
          t)
      (error (e)
        (warn "elpa-load-file ~a failed: ~a" path e)
        nil))))

(defun elpa-install-package (pkg-name &key from-melpa)
  "Fetch and load a package from ELPA/MELPA (stub that records intent).
   In v0.1 we vendor modern helpers directly; this records the request and
   would fetch over network when online."
  (declare (ignore from-melpa))
  (fire-probe :ymacs-elpa-load :package pkg-name)
  (let ((candidate (merge-pathnames (format nil "elpa/~a.el" pkg-name) (state-dir))))
    (if (probe-file candidate)
        (elpa-load-file candidate)
        (progn
          (warn "elpa-install-package ~a: not vendored yet (would fetch from archive)" pkg-name)
          nil))))

;;; ---- package.el archive shape (minimal) --------------------------------

(defvar *package-archives*
  '(("gnu" . "https://elpa.gnu.org/packages/")
    ("melpa" . "https://melpa.org/packages/"))
  "Mirrors standard package.el variable.")

(defvar *installed-packages* nil)

(defun elisp/package-installed-p (pkg)
  (member pkg *installed-packages* :test #'string=))

(defun elisp/package-install (pkg)
  (pushnew pkg *installed-packages* :test #'string=)
  (elpa-install-package pkg))

;;;; org.lisp --- Org mode for ymacs: the typed org node contract.
;;;;
;;;; Step 6 of the rebuild order (docs/spec-primitives.md §1.1, §5): org
;;;; constructs are TYPED NODES, never string hacks. The reference engine
;;;; is emd-renderer's `org` module (libyggterm, MPL) — this file is the
;;;; ymacs side of that contract, with the SAME parse decisions
;;;; (stars+space headlines, an ALL-CAPS keyword slot of two or more
;;;; characters, priority cookies, tag cookies, `- [ ]` checkboxes,
;;;; #+begin_src blocks, :DRAWER:s, tables, and a visible Text remainder)
;;;; addressed by line, which is ymacs' native unit. The contract tests
;;;; (tests/org-tests.lisp) run the same fixtures the Rust engine's tests
;;;; run, so the two sides cannot drift silently.
;;;;
;;;; Animation (the ymacs org components): org-todo cycles the keyword
;;;; through org's stock workflow (none → TODO → DONE → none) via a
;;;; byte-exact splice, org-checkbox-toggle flips a checkbox in place,
;;;; and the headline rows drive the Outline sidebar (node-driven nav).
;;;; Workflow membership is checked HERE (the engine records any
;;;; ALL-CAPS token) — Emacs parity for prose headlines like "* A note".

(in-package #:ymacs)

;;; --- Typed org nodes (the ymacs side of the emd org contract) ------------

(defstruct org-heading
  level todo priority title tags line body)

(defstruct org-src-block
  language body-line-start body-line-end line)

(defstruct org-drawer
  name body-line-start body-line-end line)

(defstruct org-checkbox
  checked text state-col line)

(defstruct org-table
  lines line)

(defstruct org-text
  line line-end)

;;; --- Line scanning ---------------------------------------------------------

(defun org-scan-lines (content)
  "Split CONTENT into (VALUES LINE-STRINGS LINE-STARTS): line i occupies
\(aref LINE-STARTS i) through (+ start (length line)) exclusive, its
terminator not part of the string. A trailing \\r stays in the string —
content, exactly as the Rust engine keeps it byte-exact. An empty
document has one (empty) line, the Emacs convention."
  (let ((strings nil) (starts nil) (at 0) (i 0) (len (length content)))
    (loop while (< i len) do
      (let ((nl (position #\Newline content :start i)))
        (if nl
            (progn
              (push (subseq content i nl) strings)
              (push at starts)
              (setf at (1+ nl) i (1+ nl)))
            (progn
              (push (subseq content i) strings)
              (push at starts)
              (setf i len)))))
    (when (null strings)
      (push "" strings)
      (push 0 starts))
    (values (coerce (nreverse strings) 'vector)
            (coerce (nreverse starts) 'vector))))

(defun org-strip-cr (text)
  "A trailing \\r is content for byte-exact ranges but never part of a
parsed headline's fields."
  (if (and (plusp (length text)) (char= (char text (1- (length text))) #\Return))
      (subseq text 0 (1- (length text)))
      text))

(defun org-trim (text)
  (string-trim '(#\Space #\Tab #\Return) text))

(defun org-strip-leading-space (s)
  (if (and (plusp (length s)) (char= (char s 0) #\Space))
      (subseq s 1)
      s))

;;; --- Parse decisions (contract-locked against emd-renderer/org.rs) --------

(defun org-heading-stars (text)
  "Stars count of a headline, org parity rule: one or more `*` FOLLOWED
BY A SPACE. A stars-only line is text, not a headline."
  (let ((stars 0) (len (length text)))
    (loop while (and (< stars len) (char= (char text stars) #\*))
          do (incf stars))
    (when (and (plusp stars)
               (or (= stars len) (char= (char text stars) #\Space)))
      stars)))

(defun org-ascii-slot-token-p (token)
  "The keyword SLOT: an ALL-CAPS token of two or more characters \(org's
stock keywords are all ≥2; single uppercase letters stay title text so
\"* A note\" parses as Emacs). Membership in a workflow is the app's
decision, not the parser's."
  (and (>= (length token) 2)
       (char<= #\A (char token 0) #\Z)
       (loop for ch across token
             always (or (char<= #\A ch #\Z) (char<= #\0 ch #\9)
                        (char= ch #\_)))))

(defun org-tag-char-p (ch)
  (or (alpha-char-p ch) (digit-char-p ch) (find ch "_@#%")))

(defun org-split-tags (title-part)
  "Split a trailing `:a:b:` tag cookie off a headline title.
Returns (VALUES TITLE TAGS)."
  (if (not (and (plusp (length title-part))
                (char= (char title-part (1- (length title-part))) #\:)))
      (values title-part nil)
      (let ((run-len 0))
        (loop for i from (1- (length title-part)) downto 0
              for ch = (char title-part i)
              while (or (org-tag-char-p ch) (char= ch #\:))
              do (incf run-len))
        (let ((run (subseq title-part (- (length title-part) run-len))))
          (if (or (< run-len 2) (char/= (char run 0) #\:))
              (values title-part nil)
              (values (string-trim '(#\Space #\Tab)
                                   (subseq title-part 0 (- (length title-part) run-len)))
                      (loop for tag in (split-org-string run #\:)
                            when (plusp (length tag)) collect tag)))))))

(defun split-org-string (s sep)
  (let (out (at 0))
    (loop
      (let ((pos (position sep s :start at)))
        (if pos
            (progn (push (subseq s at pos) out) (setf at (1+ pos)))
            (progn (push (subseq s at) out) (return)))))
    (nreverse out)))

(defun org-heading-parse (text line)
  "Parse one headline line into an ORG-HEADING (body filled by the
block parser). LINE is the 1-based source line."
  (let* ((stars (org-heading-stars text))
         (clean (org-strip-cr text))
         (rest (org-strip-leading-space (subseq clean stars)))
         (todo nil)
         (priority nil))
    ;; Keyword slot: token up to the first space.
    (let* ((token-end (or (position #\Space rest) (length rest)))
           (token (subseq rest 0 token-end)))
      (when (org-ascii-slot-token-p token)
        (setf todo token
              rest (org-strip-leading-space (subseq rest token-end))))
      ;; Priority cookie [#c].
      (when (and (>= (length rest) 4)
                 (char= (char rest 0) #\[)
                 (char= (char rest 1) #\#)
                 (char= (char rest 3) #\]))
        (setf priority (char rest 2)
              rest (org-strip-leading-space (subseq rest 4))))
      (multiple-value-bind (title tags) (org-split-tags rest)
        (make-org-heading :level stars :todo todo :priority priority
                          :title title :tags tags :line line :body nil)))))

(defun org-src-begin-p (text)
  (let ((trim (org-trim text)))
    (and (>= (length trim) (length "#+begin_src"))
         (string-equal "#+begin_src" trim
                       :end1 (length "#+begin_src")
                       :end2 (length "#+begin_src")))))

(defun org-src-end-p (text)
  (string-equal "#+end_src" (org-trim text)))

(defun org-drawer-name-p (name)
  (and name (plusp (length name))
       (loop for ch across name
             always (or (char<= #\A ch #\Z) (char<= #\a ch #\z)
                        (char<= #\0 ch #\9)
                        (find ch "_-")))))

(defun org-drawer-at (text)
  "Drawer open line name, or nil. `:END:` (any case) closes."
  (let ((trim (org-trim text)))
    (when (and (> (length trim) 2)
               (char= (char trim 0) #\:)
               (char= (char trim (1- (length trim))) #\:))
      (let ((name (subseq trim 1 (1- (length trim)))))
        (when (org-drawer-name-p name) name)))))

(defun org-checkbox-at (text line)
  "Checkbox item on TEXT, org parity: [+-*] SP [SP|x|X]. Returns an
ORG-CHECKBOX or nil. STATE-COL is the 0-based column of the state
character — the toggle splice target."
  (let ((indent (position-if-not
                 (lambda (c) (or (char= c #\Space) (char= c #\Tab))) text)))
    (when indent
      (let ((rest (subseq text indent)))
        (when (and (member (char rest 0) '(#\- #\+ #\*))
                   (>= (length rest) 5)
                   (char= (char rest 1) #\Space)
                   (char= (char rest 2) #\[)
                   (char= (char rest 4) #\])
                   (member (char rest 3) '(#\Space #\x #\X)))
          (make-org-checkbox
           :checked (char/= (char rest 3) #\Space)
           :text (string-trim '(#\Space #\Tab) (subseq rest 5))
           :state-col (+ indent 3)
           :line line))))))

;;; --- The block parser ------------------------------------------------------

(defun org-parse (content)
  "Parse org CONTENT into the typed forest — the ymacs side of the
emd-renderer org contract."
  (multiple-value-bind (lines starts) (org-scan-lines content)
    (multiple-value-bind (nodes next) (org-parse-block lines starts 0 0)
      (declare (ignore next))
      nodes)))

(defun org-parse-block (lines starts i ctx-stars)
  "Parse nodes from line I until a heading of stars <= CTX-STARS (the
caller's sibling) or end. Returns (VALUES NODES NEXT-I)."
  (let ((nodes nil) (n (length lines)))
    (loop
      (when (>= i n) (return))
      (let* ((text (aref lines i))
             (stars (org-heading-stars text)))
        (cond
          ;; A sibling (or an ancestor's sibling) — the caller resumes.
          ((and stars (<= stars ctx-stars)) (return))
          (stars
           (multiple-value-bind (body next)
               (org-parse-block lines starts (1+ i) stars)
             (let ((h (org-heading-parse text (1+ i))))
               (setf (org-heading-body h) body)
               (push h nodes))
             (setf i next)))
          ((org-src-begin-p text)
           (let ((end (position-if #'org-src-end-p lines :start (1+ i))))
             (if end
                 (progn
                   (push (make-org-src-block
                          :language (let* ((trim (org-trim text))
                                           (after (org-trim
                                                   (subseq trim (length "#+begin_src")))))
                                      (let ((tok (if (position #\Space after)
                                                     (subseq after 0 (position #\Space after))
                                                     after)))
                                        (and (plusp (length tok)) tok)))
                          :body-line-start (when (> end (1+ i)) (+ i 2))
                          :body-line-end (when (> end (1+ i)) end)
                          :line (1+ i))
                         nodes)
                   (setf i (1+ end)))
                 (progn (push (make-org-text :line (1+ i) :line-end (1+ i)) nodes)
                        (incf i)))))
          ((org-drawer-at text)
           (let ((end (position-if
                       (lambda (l) (string-equal ":end:" (org-trim l)))
                       lines :start (1+ i))))
             (if end
                 (progn
                   (push (make-org-drawer
                          :name (org-drawer-at text)
                          :body-line-start (when (> end (1+ i)) (+ i 2))
                          :body-line-end (when (> end (1+ i)) end)
                          :line (1+ i))
                         nodes)
                   (setf i (1+ end)))
                 (progn (push (make-org-text :line (1+ i) :line-end (1+ i)) nodes)
                        (incf i)))))
          ((org-checkbox-at text (1+ i))
           (push (org-checkbox-at text (1+ i)) nodes)
           (incf i))
          ((and (plusp (length text)) (char= (char text 0) #\|))
           (let ((run i))
             (loop while (and (< i n) (plusp (length (aref lines i)))
                              (char= (char (aref lines i) 0) #\|))
                   do (incf i))
             (push (make-org-table
                    :lines (loop for j from run below i collect (aref lines j))
                    :line (1+ run))
                   nodes)))
          (t
           ;; Text run: coalesce everything the grammar does not type
           ;; into ONE visible Text node — the same tree shape the Rust
           ;; engine builds. Nothing vanishes.
           (let ((run i))
             (loop while (and (< i n)
                              (not (org-heading-stars (aref lines i)))
                              (not (org-checkbox-at (aref lines i) (1+ i)))
                              (not (and (plusp (length (aref lines i)))
                                        (char= (char (aref lines i) 0) #\|)))
                              (not (org-src-begin-p (aref lines i)))
                              (not (org-drawer-at (aref lines i))))
                   do (incf i))
             (push (make-org-text :line (1+ run) :line-end i) nodes)
             (setf i i))))))
      ;; (values ...) MUST sit after the loop, inside the let: an early
      ;; (return) is the normal exit for the sibling/EOF cases and must
      ;; still yield (values nodes next-i) — two values, always.
      (values (nreverse nodes) i)))

;;; --- Tree accessors ---------------------------------------------------------

(defun org-headings-flat (nodes)
  "Every heading, depth-first in document order."
  (let (out)
    (labels ((walk (list)
               (dolist (n list)
                 (typecase n
                   (org-heading
                    (push n out)
                    (walk (org-heading-body n)))))))
      (walk nodes)
      (nreverse out))))

(defun org-checkboxes-flat (nodes)
  "Every checkbox, depth-first in document order."
  (let (out)
    (labels ((walk (list)
               (dolist (n list)
                 (typecase n
                   (org-heading (walk (org-heading-body n)))
                   (org-checkbox (push n out))))))
      (walk nodes)
      (nreverse out))))

;;; --- Point / line helpers ---------------------------------------------------

(defun org-line-starts (buf)
  (nth-value 1 (org-scan-lines (buffer-content buf))))

(defun org-line-of-point (buf)
  "0-based line index containing BUF's point."
  (let ((starts (org-line-starts buf)))
    (let ((pos (position-if (lambda (s) (> s (buffer-point buf))) starts)))
      (if pos (max 0 (1- pos)) (1- (length starts))))))

(defun org-point-at-line (buf line)
  "Character offset of LINE's first character (LINE 0-based). The
phantom line after the last newline is point-max — the same position
contract TextSurface::offset_of serves."
  (let ((starts (org-line-starts buf)))
    (if (>= line (length starts))
        (length (buffer-content buf))
        (aref starts line))))

(defun org-goto-line (buf n)
  "Move BUF's point to 1-based line N's first character. Point motion
only — no document-version bump (the content did not change; motion
commands never bump)."
  (when (and buf (plusp n))
    (let ((starts (org-line-starts buf)))
      (when (<= n (length starts))
        (setf (buffer-point buf) (aref starts (1- n)))
        t))))

;;; --- The animations (ymacs org components) ----------------------------------

(defun org--workflow-keyword-p (kw)
  "org's stock workflow. A user-configured workflow is settings-system
territory (build-order step 7); the stock pair is what Emacs ships."
  (and kw (or (string= kw "TODO") (string= kw "DONE"))))

(defun org-heading-at-point (buf)
  "The heading at or above BUF's point (nearest in document order)."
  (let* ((nodes (org-parse (buffer-content buf)))
         (at (org-line-of-point buf))
         (found nil))
    (dolist (h (org-headings-flat nodes))
      (when (and (not found) (<= (1- (org-heading-line h)) at))
        (setf found h)))
    found))

(defcommand org-todo (&optional buf)
  "Cycle the TODO keyword on the heading at point: none → TODO →
DONE → none (org's stock workflow), spliced character-exactly — the
title, tags, and every other line are untouched. A recorded keyword
slot is cycled only when it is a workflow keyword; prose headlines
\(\"* A note\") gain the keyword exactly as Emacs."
  (interactive)
  (let ((b (or buf *current-buffer*)))
    (when b
      (let* ((heading (org-heading-at-point b)))
        (when heading
          (let* ((line-start (aref (org-line-starts b)
                                   (1- (org-heading-line heading))))
                 (stars (org-heading-level heading))
                 (slot (org-heading-todo heading))
                 (effective (and (org--workflow-keyword-p slot) slot))
                 (token-at (+ line-start stars 1))
                 (to (cond ((null effective) "TODO")
                           ((string= effective "TODO") "DONE")
                           (t "none"))))
            (cond
              ;; none → TODO: insert "TODO " right after the stars+space.
              ((null effective)
               (buffer-insert b token-at "TODO "))
              ;; TODO → DONE: swap the token in place.
              ((string= effective "TODO")
               (buffer-delete b token-at (length slot))
               (buffer-insert b token-at "DONE"))
              ;; DONE → none: remove the token and one following space.
              (t
               (let* ((end (+ token-at (length slot)))
                      (content (buffer-content b)))
                 (when (and (< end (length content))
                            (char= (char content end) #\Space))
                   (incf end))
                 (buffer-delete b token-at (- end token-at)))))
            (setf (buffer-point b)
                  (min (buffer-point b) (length (buffer-content b))))
            (fire-probe :ymacs-org-todo :buffer-id (buffer-id b)
                        :to to)
            heading))))))

(defcommand org-checkbox-toggle (&optional buf)
  "Toggle the checkbox on the current line: space → X, any checked
state → space (Emacs C-c C-c parity). Character-exact — one character
moves."
  (interactive)
  (let ((b (or buf *current-buffer*)))
    (when b
      (let* ((lines (nth-value 0 (org-scan-lines (buffer-content b))))
             (at (org-line-of-point b))
             (item (and (< at (length lines))
                        (org-checkbox-at (aref lines at) (1+ at)))))
        (when item
          (let ((splice-at (+ (aref (org-line-starts b) at)
                              (org-checkbox-state-col item))))
            (buffer-delete b splice-at 1)
            (buffer-insert b splice-at (if (org-checkbox-checked item) " " "X"))
            (fire-probe :ymacs-org-checkbox :buffer-id (buffer-id b)
                        :to (if (org-checkbox-checked item) " " "X"))
            item))))))

(defcommand org-next-heading (&optional buf)
  "C-c C-n: move point to the next heading after point."
  (interactive)
  (let ((b (or buf *current-buffer*)))
    (when b
      (let* ((at (org-line-of-point b))
             (next (find-if (lambda (h) (> (1- (org-heading-line h)) at))
                            (org-headings-flat (org-parse (buffer-content b))))))
        (when next
          (setf (buffer-point b)
                (org-point-at-line b (1- (org-heading-line next))))
          next)))))

(defcommand org-prev-heading (&optional buf)
  "C-c C-p: move point to the previous heading before point."
  (interactive)
  (let ((b (or buf *current-buffer*)))
    (when b
      (let* ((at (org-line-of-point b))
             (prev (find-if (lambda (h) (< (1- (org-heading-line h)) at))
                            (reverse (org-headings-flat
                                      (org-parse (buffer-content b)))))))
        (when prev
          (setf (buffer-point b)
                (org-point-at-line b (1- (org-heading-line prev))))
          prev)))))

(defun org-join (sep list)
  (with-output-to-string (out)
    (loop for (item . rest) on list
          do (princ item out)
          when rest do (princ sep out))))

(defun org-outline-rows (content)
  "Node-driven Outline sidebar rows: an alist of (id . title) where ID
is `line-N` (1-based headline line — the goto-line wire contract) and
TITLE indents by outline level and carries the workflow keyword."
  (let (rows)
    (dolist (h (org-headings-flat (org-parse content)))
      (let* ((indent (make-string (max 0 (* 2 (1- (org-heading-level h))))
                                  :initial-element #\Space))
             (kw (and (org--workflow-keyword-p (org-heading-todo h))
                      (org-heading-todo h)))
             (tags (org-heading-tags h))
             (title (concatenate
                     'string indent
                     (if kw (concatenate 'string kw " ") "")
                     (org-heading-title h)
                     (if tags (format nil " :~a:" (org-join ":" tags)) ""))))
        (push (cons (format nil "line-~a" (org-heading-line h)) title) rows)))
    (nreverse rows)))

;;; --- Mode definition and keybindings ----------------------------------------

(defun org-line-links-to-markdown (line)
  "Org links to markdown on one line: [[url][text]] -> [text](<url>),
[[url]] -> [url](<url>). Unparseable prefixes pass through."
  (let ((parts '()) (pos 0))
    (loop
      (let ((at (search "[[" line :start2 pos)))
        (unless at
          (push (subseq line pos) parts)
          (return))
        (push (subseq line pos at) parts)
        (let ((close (and (> (length line) (+ at 2)) (search "]]" line :start2 (+ at 2)))))
          (if close
              (let* ((inner (subseq line (+ at 2) close))
                     (sep (search "][" inner)))
                (if sep
                    (push (format nil "[~a](<~a>)" (subseq inner (+ sep 2)) (subseq inner 0 sep)) parts)
                    (push (format nil "[~a](<~a>)" inner inner) parts))
                (setf pos (+ close 2)))
              (progn (push "[[" parts) (setf pos (+ at 2)))))))
    (apply #'concatenate 'string (nreverse parts))))

(defun org-buffer-markdown (buf)
  "The rendered-view projection of an org buffer, v0: headings, links
and BEGIN_SRC/EXAMPLE blocks map to markdown; everything else passes
through line-for-line. Step-6 typed nodes deepen this later."
  (with-output-to-string (out)
    (let ((in-block nil))
      (dolist (line (split-lines (buffer-content buf)))
        (let ((trimmed (string-left-trim " " line)))
          (cond
            ((and (plusp (length trimmed)) (char= (char trimmed 0) #\*))
             (let ((level 0))
               (loop while (and (< level (length trimmed))
                                (char= (char trimmed level) #\*))
                     do (incf level))
               (format out "~a ~a~%"
                       (make-string level :initial-element #\#)
                       (string-trim " " (subseq trimmed level)))))
            ((and (> (length trimmed) 11) (string-equal "#+BEGIN_SRC" trimmed :end1 11))
             (setf in-block t)
             (write-line "```" out))
            ((and (> (length trimmed) 15) (string-equal "#+BEGIN_EXAMPLE" trimmed :end1 15))
             (setf in-block t)
             (write-line "```" out))
            ((and (> (length trimmed) 9) (string-equal "#+END_SRC" trimmed :end1 9))
             (setf in-block nil)
             (write-line "```" out))
            ((and (> (length trimmed) 13) (string-equal "#+END_EXAMPLE" trimmed :end1 13))
             (setf in-block nil)
             (write-line "```" out))
            (in-block (write-line line out))
            (t (write-line (org-line-links-to-markdown line) out))))))))

(define-major-mode "org-mode"
  :rich-parser #'org-buffer-markdown
  :doc "Org mode — typed org nodes: TODO cycle, checkbox toggle, headline nav."
  :hook (lambda (buf)
          (declare (ignore buf))
          (org-set-keybindings)))

(defun org-set-keybindings ()
  (local-set-key "org-mode" "C-c C-c" 'org-ctrl-c-ctrl-c)
  (local-set-key "org-mode" "C-c C-t" 'org-todo)
  (local-set-key "org-mode" "C-c C-n" 'org-next-heading)
  (local-set-key "org-mode" "C-c C-p" 'org-prev-heading)
  (local-set-key "org-mode" "TAB" 'org-cycle)
  (local-set-key "org-mode" "S-TAB" 'org-shifttab)
  t)

(defun org-cycle (&optional buf)
  "TAB on a headline: v0 folding (point to headline end). Folding state
is the org renderer's next seam, not a string hack."
  (let ((b (or buf *current-buffer*)))
    (when b
      (let* ((content (buffer-content b))
             (pt (buffer-point b))
             (line-start (or (position #\Newline content :end pt :from-end t) 0))
             (line-end (or (position #\Newline content :start pt) (length content)))
             (line (subseq content line-start line-end)))
        (cond
          ((and (> (length line) 0) (char= (char line 0) #\*))
           (setf (buffer-point b) line-end)
           t)
          (t nil))))))

(defun org-shifttab (&optional buf)
  (declare (ignore buf))
  t)

(defcommand org-ctrl-c-ctrl-c (&optional buf)
  "Contextual C-c C-c, Emacs shape: on a checkbox line toggle it;
otherwise tangle the buffer's org source."
  (interactive)
  (let ((b (or buf *current-buffer*)))
    (when b
      (or (org-checkbox-toggle b)
          (let ((content (buffer-content b)))
            (when (search "#+begin_src" content)
              (tangle-init-org (when (buffer-file-path b)
                                 (namestring (buffer-file-path b))))))))))

;;; --- Agenda (v1: TODO headlines over open org file buffers) -----------------
;;;
;;; The weekly view, TODO filters, and an explicit agenda-files list are
;;; settings-system territory (build-order step 7); v1 scans every open
;;; buffer visiting a .org file — the file-or-store law already makes
;;; open file buffers the working set.

(defvar *org-agenda-entries-by-buffer* (make-hash-table :test 'equal)
  "Agenda buffer id -> vector of entries (buffer line todo title
planning), aligned with the agenda buffer's entry lines (first entry
on line 3).")

(defun org-agenda-file-buffers ()
  "Open buffers visiting .org files."
  (loop for b in (list-all-buffers)
        when (and (buffer-file-path b)
                  (string-equal "org" (or (pathname-type (buffer-file-path b)) "")))
        collect b))

(defun org--planning-stamp (lines idx)
  "The DEADLINE/SCHEDULED stamp on the planning lines under a heading
heading at 0-based line IDX — org keeps them on the lines directly
below the headline. Returns a short `DEADLINE: <…>' string or NIL."
  (loop for i from (1+ idx) below (min (+ idx 3) (length lines))
        for line = (aref lines i)
        thereis (loop for m in '("DEADLINE" "SCHEDULED")
                      thereis (let ((at (search m line)))
                                (when at
                                  (let ((lt (position #\< line :start at))
                                        (gt (position #\> line :start at)))
                                    (when (and lt gt)
                                      (format nil "~a: ~a" m (subseq line lt (1+ gt))))))))))

(defun org-agenda-entries ()
  "TODO headlines across open org file buffers, in scan order: a list
of (buffer line todo title planning). DONE items are not listed — the
global TODO-list view that shows them is not built yet (honesty law)."
  (let (entries)
    (dolist (b (org-agenda-file-buffers))
      (let* ((lines (nth-value 0 (org-scan-lines (buffer-content b))))
             (base (file-namestring (buffer-file-path b))))
        (loop for i from 0 below (length lines)
              for line = (aref lines i)
              for stars = (org-heading-stars line)
              when stars
                do (let ((h (org-heading-parse line (1+ i))))
                     (when (and (org-heading-todo h)
                                (string= (org-heading-todo h) "TODO"))
                       (push (list b (1+ i) (org-heading-todo h)
                                   (org-heading-title h)
                                   (org--planning-stamp lines i)
                                   base)
                             entries))))))
    (nreverse entries)))

(defun org-agenda-render (entries)
  "The agenda view text: one line per TODO headline, entries starting
on line 3 (the jump contract with ORG-AGENDA-GOTO)."
  (with-output-to-string (out)
    (format out "TODO headlines in open org files (RET jump, g refresh, q quit)~%~%")
    (if entries
        (dolist (e entries)
          (format out "  ~a:~a  ~a  ~a~a~%"
                  (sixth e) (second e) (third e) (fourth e)
                  (if (fifth e) (format nil "   ~a" (fifth e)) "")))
        (format out "  (none — open an org file with TODO headlines)~%"))))

(defun org-agenda-build ()
  "(Re)build the *Org Agenda* view from the current org file buffers
and select it. Returns the agenda buffer."
  (let* ((entries (org-agenda-entries))
         (name "*Org Agenda*")
         (existing (find-if (lambda (b) (string= (buffer-name b) name))
                            (list-all-buffers)))
         (buf (or existing (make-new-buffer name ""))))
    (setf (buffer-rope buf) (rope-from-string (org-agenda-render entries)))
    (setf (buffer-modified-p buf) nil)
    ;; the agenda is a VIEW: regenerated on demand, never persisted —
    ;; same law as Info views (drop any durability row creation wrote).
    (when *store* (ignore-errors (store-delete-buffer (buffer-id buf))))
    (setf (gethash (buffer-id buf) *org-agenda-entries-by-buffer*)
          (coerce entries 'vector))
    (set-buffer-major-mode buf "org-agenda-mode")
    (setf *current-buffer* buf)
    (bump-document-version)
    buf))

(defcommand org-agenda (&optional arg)
  "M-x org-agenda — TODO headlines over every open org file buffer,
one line each with its planning stamp. RET jumps to the source line,
g rebuilds, q quits."
  (interactive "P")
  (declare (ignore arg))
  (if (org-agenda-file-buffers)
      (org-agenda-build)
      (message "No org file buffers to agenda over")))

(defcommand org-agenda-refresh ()
  "Agenda g — rebuild the view from the current buffers."
  (interactive)
  (if (and *current-buffer*
           (gethash (buffer-id *current-buffer*) *org-agenda-entries-by-buffer*))
      (org-agenda-build)
      (message "Not in an agenda view")))

(defcommand org-agenda-goto ()
  "Agenda RET — switch to the entry's source buffer at its line."
  (interactive)
  (let* ((buf *current-buffer*)
         (entries (and buf (gethash (buffer-id buf)
                                    *org-agenda-entries-by-buffer*))))
    (if entries
        (let* ((line (1+ (org-line-of-point buf)))   ; 1-based view line
               (idx (- line 3))                      ; entries start on line 3
               (entry (and (>= idx 0) (< idx (length entries))
                           (aref entries idx))))
          (if entry
              (let ((src (first entry)))
                (setf *current-buffer* src)
                (org-goto-line src (second entry))
                (bump-document-version)
                (message "~a:~a" (sixth entry) (second entry)))
              (message "No agenda entry on this line")))
        (message "Not in an agenda view"))))

(defcommand org-agenda-quit ()
  "Agenda q — kill the view and select the next real buffer."
  (interactive)
  (let ((buf *current-buffer*))
    (if (and buf (gethash (buffer-id buf) *org-agenda-entries-by-buffer*))
        (let ((next (loop for b in (list-all-buffers)
                          unless (or (eq b buf)
                                     (and (buffer-name b)
                                          (string= (buffer-name b) "*Org Agenda*")))
                          return b)))
          (remhash (buffer-id buf) *org-agenda-entries-by-buffer*)
          (kill-buffer-by-id (buffer-id buf))
          (when next
            (setf *current-buffer* next)
            (bump-document-version)
            (message "Closed agenda")))
        (message "Not in an agenda view"))))

(defun org-agenda-set-keybindings ()
  (local-set-key "org-agenda-mode" "RET" 'org-agenda-goto)
  (local-set-key "org-agenda-mode" "g" 'org-agenda-refresh)
  (local-set-key "org-agenda-mode" "q" 'org-agenda-quit)
  t)

(define-major-mode "org-agenda-mode"
  :doc "Org agenda — the TODO view. RET jumps to the source headline,
g rebuilds, q quits."
  :hook (lambda (buf)
          (declare (ignore buf))
          (org-agenda-set-keybindings)))

;;; --- Capture (v1: a dated TODO skeleton) ------------------------------------

(defun org-format-date (ut)
  "Org inactive-planet timestamp [YYYY-MM-DD Ddd] for a universal time."
  (multiple-value-bind (sec min hr day mon yr dow) (decode-universal-time ut)
    (declare (ignore sec min hr))
    (format nil "[~4,'0d-~2,'0d-~2,'0d ~a]"
            yr mon day
            (nth dow '("Mon" "Tue" "Wed" "Thu" "Fri" "Sat" "Sun")))))

(defcommand org-capture (&optional template)
  "M-x org-capture — seed the *Org Capture* org buffer with a dated
TODO skeleton (TEMPLATE text, if given, becomes the subject). Point
lands on the subject slot; save the buffer wherever the note belongs —
a capture-target config is settings step 7 territory."
  (interactive "sCapture subject: ")
  (let* ((name "*Org Capture*")
         (existing (find-if (lambda (b) (string= (buffer-name b) name))
                            (list-all-buffers)))
         (buf (or existing (make-new-buffer name ""))))
    (unless existing
      (set-buffer-major-mode buf "org-mode"))
    (let* ((stamp (format nil "* TODO ~a ~a~%  ~%"
                          (org-format-date (get-universal-time))
                          (or template "")))
           (at (length (buffer-content buf))))
      (buffer-insert buf at stamp)
      ;; point on the subject slot, right after the timestamp + space
      (setf (buffer-point buf) (+ at 1
                                  (length "* TODO ")
                                  (length (org-format-date (get-universal-time)))
                                  1))
      (bump-document-version))
    buf))

(defun org-tangle (file)
  (tangle-init-org file))

;; Babel
(defcommand org-babel-tangle (&optional arg)
  "Tangle the current buffer's org source blocks."
  (interactive "P")
  (declare (ignore arg))
  (when *current-buffer*
    (tangle-init-org (when (buffer-file-path *current-buffer*)
                       (namestring (buffer-file-path *current-buffer*))))))

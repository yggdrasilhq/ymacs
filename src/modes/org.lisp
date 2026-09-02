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

(define-major-mode "org-mode"
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

(defun org-agenda (&optional arg)
  (declare (ignore arg))
  (let ((buf (make-new-buffer "*Org Agenda*")))
    (setf (buffer-rope buf) (rope-from-string (with-output-to-string (out)
                                                (format out "* Agenda for ~a~%" (get-universal-time))
                                                (dolist (b (list-all-buffers))
                                                  (when (string= (buffer-major-mode b) "org-mode")
                                                    (format out "** ~a~%" (buffer-name b))
                                                    (dolist (line (split-lines (buffer-content b)))
                                                      (when (search "TODO" line)
                                                        (format out "   - ~a~%" line))))))))
    buf))

(defun org-capture (&optional template)
  (declare (ignore template))
  (make-new-buffer "*Org Capture*" ""))

(defun org-tangle (file)
  (tangle-init-org file))

;; Babel
(defun org-babel-tangle (&optional arg)
  (declare (ignore arg))
  (when *current-buffer*
    (tangle-init-org (when (buffer-file-path *current-buffer*) (namestring (buffer-file-path *current-buffer*))))))

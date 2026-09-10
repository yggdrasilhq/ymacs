;;;; info.lisp --- Info mode: read the forked Ymacs manual inside ymacs.
;;;;
;;;; Interface law: the KEYSET is Emacs Info (n/p/u/RET/l/q/s, SPC/DEL
;;;; scroll, t for Top) so the fingers transfer from GNU Emacs; the
;;;; implementation is CL, reading the built .info file (makeinfo
;;;; output) by node markers. Divergences from Emacs Info are recorded
;;;; in docs/emacs-manual/divergences.org.

(in-package #:ymacs)

(defparameter *info-sep* (code-char 31)
  "The ^_ node separator of the .info format.")

(defvar *info-file-override* nil "Test/diagnostic override.")

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

(defun info-header-field (header field)
  "Value of FIELD (\"Node\", \"Next\", \"Prev\", \"Up\") in a .info
header line, or NIL. makeinfo separates fields with \",  \" (comma,
two spaces), so a field value runs to the next such separator or the
end of the line."
  (let* ((key (concatenate 'string field ": "))
         (at (search key header)))
    (when at
      (let* ((vstart (+ at (length key)))
             (vend (or (search ",  " header :start2 vstart) (length header))))
        (string-trim " " (subseq header vstart vend))))))

(defun info-strip-file-marker (node)
  "Strip a `(file)' prefix from a cross-file node reference — this
manual reads standalone, so `*note X (other)Y' targets node Y."
  (let ((close (and (plusp (length node))
                    (char= (char node 0) #\()
                    (position #\) node))))
    (if close (subseq node (1+ close)) node)))

(defun info-parse-menu-entry (line)
  "Parse one menu line into (label . node), or NIL. The makeinfo
forms are `* Label: Node.' and `* Label::' (node equals the label);
a node name ends at a period followed by space, tab, or end of line."
  (when (and (> (length line) 2) (string= line "* " :end1 2))
    (let ((colon (position #\: line :start 2)))
      (when colon
        (let ((label (string-trim " " (subseq line 2 colon))))
          (if (and (< (1+ colon) (length line))
                   (char= (char line (1+ colon)) #\:))
              (cons label label)
              (let* ((rest (string-left-trim
                            " " (subseq line (1+ colon))))
                     (dot (loop for i from 0 below (length rest)
                                when (and (char= (char rest i) #\.)
                                          (or (= (1+ i) (length rest))
                                              (member (char rest (1+ i))
                                                      '(#\Space #\Tab))))
                                return i)))
                (when (plusp (length rest))
                  (cons label
                        (info-strip-file-marker
                         (string-trim " " (subseq rest 0 (or dot (length rest))))))))))))))

(defun info-menu-entries (node)
  "Menu entries of NODE as an alist (label . node). A makeinfo menu
runs from the `* Menu:' line; blank lines keep it open, and the first
non-blank line that is not an entry closes it."
  (let (in-menu entries)
    (dolist (line (split-lines (info-node-text node)))
      (let ((menu-start (search "* Menu:" line)))
        (cond
          ((and menu-start (= menu-start 0)) (setf in-menu t))
          (in-menu
           (cond
             ((and (> (length line) 2) (string= line "* " :end1 2))
              (let ((entry (info-parse-menu-entry line)))
                (when entry (push entry entries))))
             ((plusp (length line)) (setf in-menu nil))))))
      )
    (nreverse entries)))

(defun info-xref-node-at (text pt)
  "Node name of the `*note' cross reference containing 0-based
position PT, or NIL. The makeinfo plain-text forms: `*note LABEL:
NODE.' (node ends at a period), `*note LABEL::' (node is the label),
and `*note LABEL (file)NODE.'"
  (let ((start (search "*note" text :from-end t :end2 (min pt (length text)))))
    (when start
      (let* ((s (+ start 5))
             (s (if (and (< s (length text)) (char= (char text s) #\Space))
                    (1+ s)
                    s))
             (colon (and (< s (length text))
                         (position #\: text :start s))))
        (when colon
          (cond
            ((and (< (1+ colon) (length text))
                  (char= (char text (1+ colon)) #\:))
             ;; `*note LABEL::' — the ref ends at the second colon.
             (let ((end (+ colon 2)))
               (when (and (>= pt start) (< pt end))
                 (string-trim " " (subseq text s colon)))))
            ((and (< (1+ colon) (length text))
                  (char= (char text (1+ colon)) #\Space))
             ;; `*note LABEL: NODE.' — node runs to its period.
             (let* ((node-start (+ colon 2))
                    (dot (position #\. text :start node-start)))
               (when dot
                 (let ((end (1+ dot)))
                   (when (and (>= pt start) (< pt end))
                     (info-strip-file-marker
                      (string-trim " " (subseq text node-start dot))))))))))))))

(defun info-menu-node-at (text pt)
  "Node of the menu entry on the line containing 0-based position PT,
or NIL."
  (let* ((line-start (if (position #\Newline text :end pt :from-end t)
                         (1+ (position #\Newline text :end pt :from-end t))
                         0))
         (line-end (or (position #\Newline text :start pt) (length text)))
         (entry (info-parse-menu-entry (subseq text line-start line-end))))
    (when entry
      ;; point must sit on the entry's `* name' part, not just the
      ;; trailing description — the description is not a link target.
      (and (< pt (+ line-start 2 (length (car entry))))
           (cdr entry)))))

(defun info-parse (text)
  "Returns (VALUES ORDER NODES): ORDER is the node names in file order
(first is the entry node), NODES a name -> info-node table.

The .info layout makeinfo writes: every node begins at a ^_ separator
on a line of its own; the header line (`File: ...,  Node: NAME,  ...')
follows it, and the node's text runs to the NEXT separator. Sections
without a `File:' header line (the tag table, the end marker) are not
nodes. Text before the first separator is the preamble — not a node."
  (let ((nodes (make-hash-table :test 'equal))
        (order nil)
        (starts nil)
        (sep *info-sep*)
        (len (length text)))
    (loop for i from 0 below len
          when (char= (char text i) sep)
          do (push i starts))
    (setf starts (nreverse starts))
    (if (null starts)
        ;; not an .info file: one pseudo-node with the whole text.
        (progn
          (setf (gethash "(manual)" nodes)
                (make-info-node :name "(manual)" :text text))
          (values (list "(manual)") nodes))
        (let ((entries nil))
          (dolist (s starts)
            ;; The separator ends its own line; the header follows.
            (let* ((line-start (1+ s))
                   (line-start (if (and (< line-start len)
                                        (char= (char text line-start) #\Newline))
                                   (1+ line-start)
                                   line-start))
                   (line-end (or (position #\Newline text :start line-start) len))
                   (header (subseq text line-start line-end))
                   (n (search "Node: " header)))
              (when n
                (let* ((comma (position #\, header :start (+ n 6)))
                       (name (subseq header (+ n 6) (or comma (length header))))
                       (body-start (if (< line-end len) (1+ line-end) len))
                       (body-end (let ((next (position sep text :start (1+ s))))
                                   (or next len))))
                  (push (list name
                              (subseq text body-start body-end)
                              (info-header-field header "Next")
                              (info-header-field header "Prev")
                              (info-header-field header "Up"))
                        entries)
                  (push name order)))))
          (setf order (nreverse order))
          (dolist (e entries)
            (setf (gethash (first e) nodes)
                  (make-info-node :name (first e) :text (second e)
                                  :next (third e) :prev (fourth e)
                                  :up (fifth e))))
          (values order nodes)))))

(defvar *info-buffers* (make-hash-table :test 'equal)
  "Buffer ids that are Info views (never persisted to the store).")
(defvar *info-by-name* (make-hash-table :test 'equal)
  "Buffer name -> node table of the open manual.")
(defvar *info-order-by-name* (make-hash-table :test 'equal)
  "Buffer name -> node names in file order (the `s' search ladder).")
(defvar *info-current-node* (make-hash-table :test 'equal)
  "Buffer id -> the node name this Info view is showing.")
(defvar *info-history-by-buffer* (make-hash-table :test 'equal)
  "Buffer id -> list of node names, most recent first.")

(defun info-buffer-p (buf)
  (and buf (gethash (buffer-id buf) *info-buffers*)))

(defun info-current-node-name (buf)
  (gethash (buffer-id buf) *info-current-node*))

(defun info-open ()
  "M-x info — open the manual as an editable-in-principle, read-in-fact
buffer (Emacs Info keeps a copy too). M-x entry: the DEFCOMMAND INFO
in commands.lisp; this is the worker, so no interactive form here."
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
        (setf (gethash name *info-order-by-name*) order)
        (set-buffer-major-mode buf "info-mode")
        (setf (gethash (buffer-id buf) *info-current-node*) first)
        (setf (gethash (buffer-id buf) *info-history-by-buffer*)
              (and first (list first)))
        (setf *current-buffer* buf)
        (when first (info-show-node buf first))
        (bump-document-version)
        buf))))

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

(defun info-select-node (buf node-name)
  "Jump BUF's Info view to NODE-NAME, push the jump on the view's
history and report it. Returns NODE-NAME, or NIL (with a message)
when this manual has no such node — `Prev: (dir)' style references
resolve to nothing here."
  (if (gethash node-name (gethash (buffer-name buf) *info-by-name*))
      (progn
        (push node-name (gethash (buffer-id buf) *info-history-by-buffer*))
        (setf (gethash (buffer-id buf) *info-current-node*) node-name)
        (info-show-node buf node-name)
        (setf (buffer-point buf) 1)
        (message "Node: %s" node-name)
        node-name)
      (progn (message "No such node in this manual: %s" node-name) nil)))

(defun info-goto-relation (kind accessor)
  "Follow one header relation (Next / Prev / Up) from the current node."
  (let ((buf *current-buffer*)
        (cur (and *current-buffer* (info-current-node-name *current-buffer*))))
    (if (and buf cur)
        (let* ((node (gethash cur (gethash (buffer-name buf) *info-by-name*)))
               (target (and node (funcall accessor node))))
          (cond ((null target) (message "No ~a node from here" kind))
                ((string= target "(dir)") (message "No ~a node in this manual" kind))
                (t (info-select-node buf target))))
        (message "Not in an Info view"))))

(defcommand info-next-node ()
  "Info `n' — the Next node of the header spine."
  (interactive)
  (info-goto-relation "next" #'info-node-next))

(defcommand info-prev-node ()
  "Info `p' — the Prev node of the header spine."
  (interactive)
  (info-goto-relation "previous" #'info-node-prev))

(defcommand info-up-node ()
  "Info `u' — the Up node of the header spine."
  (interactive)
  (info-goto-relation "up" #'info-node-up))

(defcommand info-top-node ()
  "Info `t' — the Top node of the manual."
  (interactive)
  (let ((buf *current-buffer*))
    (if (and buf (info-buffer-p buf))
        (info-select-node buf "Top")
        (message "Not in an Info view"))))

(defcommand info-next-menu-entry ()
  "Info TAB — step the menu cursor; the echo names the entry (the
rendered view follows it with RET, the Emacs Info TAB habit)."
  (interactive)
  (let ((buf *current-buffer*))
    (if (and buf (info-buffer-p buf))
        (let ((idx (info-menu-cursor-move buf 1)))
          (bump-document-version)
          (let* ((node (info-current-node buf))
                 (entries (and node (info-menu-entries node)))
                 (label (and entries idx (< idx (length entries))
                             (car (nth idx entries)))))
            (message "Menu ~a/~a~@[ · ~a~]" (1+ idx) (length entries) label)))
        (message "Not in an Info view"))))

(defcommand info-previous-menu-entry ()
  "Info S-TAB — step the menu cursor back, wrapping."
  (interactive)
  (let ((buf *current-buffer*))
    (if (and buf (info-buffer-p buf))
        (let ((idx (info-menu-cursor-move buf -1)))
          (bump-document-version)
          (let* ((node (info-current-node buf))
                 (entries (and node (info-menu-entries node)))
                 (label (and entries idx (< idx (length entries))
                             (car (nth idx entries)))))
            (message "Menu ~a/~a~@[ · ~a~]" (1+ idx) (length entries) label)))
        (message "Not in an Info view"))))

(defcommand info-follow-nearest-node ()
  "Info RET — the rendered view follows the TAB cursor's menu entry; the
raw view follows the menu entry or `*note' cross reference under point,
exactly like Info-follow-nearest-node."
  (interactive)
  (if (and (fboundp 'rendered-mode-p) *current-buffer*
           (rendered-mode-p *current-buffer*))
      (let* ((buf *current-buffer*)
             (node (info-current-node buf))
             (entries (and node (info-menu-entries node)))
             (idx (gethash (buffer-id buf) *info-menu-index*)))
        (if (and entries idx (< idx (length entries)))
            (info-select-node buf (cdr (nth idx entries)))
            (message "No menu entry selected — TAB to one")))
      (let* ((buf *current-buffer*)
         (content (and buf (buffer-content buf)))
         (pt (and buf (1- (buffer-point buf)))))
    (if (and buf content)
        (let ((target (or (info-menu-node-at content pt)
                          (info-xref-node-at content pt))))
          (if target
              (info-select-node buf target)
              (message "No menu item or cross reference here")))
        (message "Not in an Info view")))))

(defcommand info-history-back ()
  "Info `l' — step back through this view's node history."
  (interactive)
  (let* ((buf *current-buffer*)
         (hist (and buf (gethash (buffer-id buf) *info-history-by-buffer*))))
    (if (and buf hist (rest hist))
        (let ((target (second hist)))
          (setf (gethash (buffer-id buf) *info-history-by-buffer*) (rest hist))
          (setf (gethash (buffer-id buf) *info-current-node*) target)
          (info-show-node buf target)
          (message "Node: %s" target))
        (message "No earlier nodes in this view"))))

(defcommand info-search (term)
  "Info `s' — search forward through the manual's nodes for TERM (case
insensitive), wrapping once, and land point on the first hit."
  (interactive "sSearch manual: ")
  (let ((buf *current-buffer*))
    (if (and buf (and term (plusp (length term))))
        (let* ((name (buffer-name buf))
               (order (gethash name *info-order-by-name*))
               (cur (info-current-node-name buf))
               (scan (and order cur
                          (append (rest (member cur order :test #'string=))
                                  (ldiff order (member cur order :test #'string=)))))
               (needle (string-downcase term))
               found)
          (block search
            (dolist (node-name scan)
              (let* ((node (gethash node-name (gethash name *info-by-name*)))
                     (text (and node (info-node-text node)))
                     (hit (and text (search needle text :test #'char-equal))))
                (when hit
                  (setf found (cons node-name hit))
                  (return-from search t)))))
          (if found
              (progn
                (info-select-node buf (car found))
                (setf (buffer-point buf) (1+ (cdr found)))
                (message "`%s' found in node %s" term (car found)))
              (message "Not found: %s" term)))
        (message "Nothing to search"))))

(defun info-move-lines (buf n)
  "Move point N displayed lines down, clamped to the buffer end.
Returns the number of lines actually moved."
  (let* ((content (buffer-content buf))
         (idx (min (1- (buffer-point buf)) (length content)))
         (target idx)
         (moved 0))
    (dotimes (_ n)
      (let ((nl (position #\Newline content :start (min target (length content)))))
        (when nl (setf target (1+ nl) moved (1+ moved)))))
    (setf (buffer-point buf) (1+ target))
    moved))

(defun info-move-lines-up (buf n)
  "Move point N displayed lines up, clamped to the buffer start."
  (let* ((content (buffer-content buf))
         (idx (min (1- (buffer-point buf)) (length content)))
         (target idx))
    (dotimes (_ n)
      (when (plusp target)
        (let ((nl (position #\Newline content :end (1- target) :from-end t)))
          (setf target (if nl (1+ nl) 0)))))
    (setf (buffer-point buf) (1+ target))
    target))

(defcommand info-scroll-up ()
  "Info SPC — scroll a screen down; with the node end already visible
(fewer than a screen of lines left to move), advance to the Next node,
as Emacs Info does when the end of the node is on screen."
  (interactive)
  (let ((buf *current-buffer*))
    (if (and buf (info-buffer-p buf))
        (let ((before (buffer-point buf))
              (moved (info-move-lines buf 23)))
          (when (or (< moved 23) (= (buffer-point buf) before))
            (info-next-node)))
        (message "Not in an Info view"))))

(defcommand info-scroll-down ()
  "Info DEL — scroll a screen up."
  (interactive)
  (let ((buf *current-buffer*))
    (if (and buf (info-buffer-p buf))
        (info-move-lines-up buf 23)
        (message "Not in an Info view"))))

(defcommand info-exit ()
  "Info `q' — kill the manual view and select the next real buffer."
  (interactive)
  (let ((buf *current-buffer*))
    (if (and buf (info-buffer-p buf))
        (let ((next (loop for b in (list-all-buffers)
                          unless (or (info-buffer-p b)
                                     (string= (buffer-name b) (buffer-name buf)))
                          return b)))
          (remhash (buffer-id buf) *info-buffers*)
          (remhash (buffer-id buf) *info-current-node*)
          (remhash (buffer-id buf) *info-history-by-buffer*)
          (kill-buffer-by-id (buffer-id buf))
          (when next
            (setf *current-buffer* next)
            (bump-document-version)
            (message "Killed %s" (buffer-name buf))))
        (message "Not in an Info view"))))

(defun info-set-keybindings ()
  (local-set-key "info-mode" "n" 'info-next-node)
  (local-set-key "info-mode" "p" 'info-prev-node)
  (local-set-key "info-mode" "u" 'info-up-node)
  (local-set-key "info-mode" "t" 'info-top-node)
  (local-set-key "info-mode" "RET" 'info-follow-nearest-node)
  (local-set-key "info-mode" "TAB" 'info-next-menu-entry)
  (local-set-key "info-mode" "S-TAB" 'info-previous-menu-entry)
  (local-set-key "info-mode" "l" 'info-history-back)
  (local-set-key "info-mode" "s" 'info-search)
  (local-set-key "info-mode" "q" 'info-exit)
  (local-set-key "info-mode" "SPC" 'info-scroll-up)
  (local-set-key "info-mode" "DEL" 'info-scroll-down)
  t)

;;; --- The rendered-view projection (docs/spec-rendering.md) ---------------

(defvar *info-menu-index* (make-hash-table :test 'equal)
  "Buffer id -> the 0-based menu entry under the TAB cursor (the Emacs
Info TAB habit, rendered view).")

(defun info-current-node (buf)
  (let ((cur (info-current-node-name buf)))
    (and cur (gethash cur (gethash (buffer-name buf) *info-by-name*)))))

(defun info-md-link (label node)
  (format nil "[~a](<info:~a>)" label node))

(defun info-note-label-node (text start)
  "The cross reference at `*note' START as (values label node end): the
makeinfo forms are `*note Label: Node.' and `*note Node::'."
  (let* ((limit (length text))
         (p (loop for i from (+ start 5) below limit
                  while (char= (char text i) #\Space)
                  finally (return i))))
    (labels ((terminator (from)
               (loop for i from from below limit
                     when (member (char text i) '(#\: #\. #\, #\; #\Newline))
                     return i)))
      (let ((label-end (terminator p)))
        (when (and label-end (char= (char text label-end) #\:))
          (let ((label (string-trim " " (subseq text p label-end))))
            (if (and (< (1+ label-end) limit)
                     (char= (char text (1+ label-end)) #\:))
                (values label label (+ label-end 2))
                (let* ((q (loop for i from (1+ label-end) below limit
                                while (char= (char text i) #\Space)
                                finally (return i)))
                       (node-end (terminator q)))
                  (when (and node-end (> node-end q))
                    (values label
                            (string-trim " " (subseq text q node-end))
                            node-end))))))))))

(defun info-note-to-md (text)
  "Rewrite `*note' cross references to markdown links; an unparseable
reference passes through verbatim."
  (let ((parts '()) (pos 0))
    (loop
      (let ((at (search "*note" text :start2 pos)))
        (unless at
          (push (subseq text pos) parts)
          (return))
        (push (subseq text pos at) parts)
        (let ((ok (and (> (length text) (+ at 5))
                       (member (char text (+ at 5)) '(#\Space #\Newline)))))
          (multiple-value-bind (label node end)
              (when ok (ignore-errors (info-note-label-node text at)))
            (if (and label node (plusp (length node)))
                (progn (push (info-md-link label node) parts)
                       (setf pos end))
                (progn (push "*note" parts)
                       (setf pos (+ at 5))))))))
    (apply #'concatenate 'string (nreverse parts))))

(defun info-menu-cursor-move (buf delta)
  "Step the TAB cursor over the current node's menu, wrapping. Returns
the new index, or NIL when this node has no menu."
  (let* ((node (info-current-node buf))
         (n (if node (length (info-menu-entries node)) 0)))
    (when (plusp n)
      (let ((idx (mod (+ (or (gethash (buffer-id buf) *info-menu-index*) 0) delta) n)))
        (setf (gethash (buffer-id buf) *info-menu-index*) idx)
        (when (fboundp 'rendering-bump-epoch) (rendering-bump-epoch buf))
        idx))))

(defun info-buffer-markdown (buf)
  "The rendered-view projection of the current Info node (the rendering
law): heading, header spine as links, body with `*note' rewrites, menu
entries as links. The buffer text itself is NEVER touched."
  (let ((node (info-current-node buf)))
    (when node
      (let* ((entries (info-menu-entries node))
             (cursor (gethash (buffer-id buf) *info-menu-index*))
             (text (info-node-text node))
             (menu-at (search "* Menu:" text))
             (body (if menu-at (subseq text 0 menu-at) text))
             (out (list)))
        (flet ((spine-link (label accessor)
                 (let ((target (funcall accessor node)))
                   (when (and target (not (string= target "(dir)")))
                     (info-md-link label target)))))
          (let ((links (remove nil (list (spine-link "Next" #'info-node-next)
                                         (spine-link "Prev" #'info-node-prev)
                                         (spine-link "Up" #'info-node-up)))))
            (when links
              (push (concatenate 'string
                                 (format nil "~{~a~^ · ~}" links)
                                 (string #\Newline) (string #\Newline)) out)))
          (push (concatenate 'string "# " (info-node-name node)
                             (string #\Newline) (string #\Newline)) out)
          (push (info-note-to-md body) out)
          (when entries
            (push (concatenate 'string (string #\Newline) "**Menu**"
                               (string #\Newline) (string #\Newline)) out)
            (let ((i 0))
              (dolist (e entries)
                (let ((link (info-md-link (car e) (cdr e))))
                  (push (concatenate 'string
                                     "- "
                                     (if (and cursor (= i cursor)) "**" "")
                                     link
                                     (if (and cursor (= i cursor)) "**" "")
                                     (string #\Newline))
                        out))
                (incf i))))
          (apply #'concatenate 'string (nreverse out)))))))

(define-major-mode "info-mode"
  :rich-parser #'info-buffer-markdown
  :doc "Info mode — read the manual: n/p/u move the spine, t goes to
Top, TAB walks the menu, RET follows the nearest menu entry or cross
reference, l steps back, s searches the manual, SPC/DEL scroll, q
quits."
  :hook (lambda (buf)
          (declare (ignore buf))
          (info-set-keybindings)))

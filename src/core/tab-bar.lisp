;;;; tab-bar.lisp --- The ribbon's tab bar: state, mode, and the Lisp API
;;;; that adds and removes ribbon elements.
;;;;
;;;; Spec: docs/spec-ribbon.md — the ribbon is TWO layers: a tab strip
;;;; PINNED on yggterm's background chrome, and a floating command panel
;;;; the GUI overlays on the viewport. This module owns the APP half of
;;;; the component: which tabs exist, which is active, and what each
;;;; tab's command groups hold. The GUI owns only panel open/closed.
;;;;
;;;; Every mutation bumps the document version, so a Lisp call reaches
;;;; the rendered ribbon within one heartbeat (~4s) — no direct GUI poke.

(in-package #:ymacs)

(defparameter *tab-bar-mode-on* t
  "tab-bar-mode: the ribbon tab strip on yggterm's chrome. On by default;
M-x tab-bar-mode toggles. There is deliberately NO menu-bar-mode in
ymacs — the ribbon is the only top chrome (spec-primitives §1.2). The
ribbon fuses Emacs' tool bar and tab bar into one strip, so
tool-bar-mode is an ALIAS of this mode (divergence ledger).")

(defparameter *tab-bar-active* "home"
  "The active ribbon tab id (Excel shape: tabs switch the command groups).")

(defun tab-bar-make-button (action label title &optional (primary nil))
  "One ribbon button. PRIMARY may be T, NIL, or :BUFFER-MODIFIED —
the keyword resolves at schema time to whether the current buffer is
modified (the Save button lights up exactly when there is something to
save)."
  (list :action action :label label :title title :primary primary))

(defun tab-bar-make-group (label buttons &key right)
  "One command group: LABEL caption over BUTTONS; :right floats the
group to the far edge (Excel's Comments/Share slot)."
  (list :label label :buttons buttons :right right))

(defun tab-bar-make-tab (id name groups)
  "One ribbon tab: ID (stable, action spelling), NAME (display),
GROUPS (list of tab-bar-make-group plists)."
  (list :id id :name name :groups groups))

(defun init-tab-bar-defaults ()
  "The shipped tabs. Every button fires a REAL action — named commands
through the choke point, or an existing document action. No decorative
chrome; a button that cannot do its thing yet does not ship (honesty
law)."
  (list
   (tab-bar-make-tab
    "home" "Home"
    (list
     (tab-bar-make-group "File"
                         (list (tab-bar-make-button "command:find-file" "📂 Open" "Find file (C-x C-f)")
                               (tab-bar-make-button "save" "💾 Save" "Save buffer (C-x C-s)" :buffer-modified)))
     (tab-bar-make-group "Edit"
                         (list (tab-bar-make-button "command:undo" "↶ Undo" "Undo (C-/)")
                               (tab-bar-make-button "command:isearch-forward" "🔍 Search" "Search forward (C-s)")))
     (tab-bar-make-group "" (list (tab-bar-make-button "command:execute-extended-command" "M-x" "Run a command by name" t)) :right t)))
   (tab-bar-make-tab
    "edit" "Edit"
    (list
     (tab-bar-make-group "Clipboard"
                         (list (tab-bar-make-button "command:kill-region" "✂ Cut" "Cut region (C-w)")
                               (tab-bar-make-button "command:kill-ring-save" "⧉ Copy" "Copy region (M-w)")
                               (tab-bar-make-button "command:yank" "📋 Paste" "Paste (C-y)")
                               (tab-bar-make-button "command:yank-pop" "⇅ Paste Prev" "Yank pop (M-y)")))
     (tab-bar-make-group "Line"
                         (list (tab-bar-make-button "command:kill-line" "✂ Kill Line" "Kill to end of line (C-k)")))
     (tab-bar-make-group "Search"
                         (list (tab-bar-make-button "command:isearch-forward" "🔍 Search" "Search forward (C-s)")))
     (tab-bar-make-group "" (list (tab-bar-make-button "command:execute-extended-command" "M-x" "Run a command by name" t)) :right t)))
   (tab-bar-make-tab
    "view" "View"
    (list
     (tab-bar-make-group "Panes"
                         (list (tab-bar-make-button "toggle-sidebar" "🗂 Buffers" "Toggle the Buffers pane (C-c s)")
                               (tab-bar-make-button "which-key" "⌨ Which-Key" "Which Key")))
     (tab-bar-make-group "System"
                         (list (tab-bar-make-button "settings" "⚙ Settings" "Settings (M-x settings)")
                               (tab-bar-make-button "command:sidebar/profiles" "◂▸ Profiles" "Switch profile (M-x sidebar/profiles)")))
     (tab-bar-make-group "" (list (tab-bar-make-button "kill-daemon" "⏻ Quit" "Save buffers and kill ymacs")) :right t)))
   (tab-bar-make-tab
    "help" "Help"
    (list
     (tab-bar-make-group "Documentation"
                         (list (tab-bar-make-button "command:info" "📖 Manual" "The ymacs manual (Info)")))
     (tab-bar-make-group "" (list (tab-bar-make-button "about" "ⓘ About" "Version and provenance")) :right t)))))

(defparameter *tab-bar-tabs* (init-tab-bar-defaults)
  "Ordered ribbon tabs (tab-bar-make-tab plists). Lisp code adds and
removes tabs, groups and buttons through the tab-bar-* API below; each
mutation bumps the document version so the strip re-renders.")

(defun tab-bar-visible-p () *tab-bar-mode-on*)

(defun tab-bar-tab (id)
  "The tab plist whose :id is ID, or NIL."
  (find id *tab-bar-tabs* :key (lambda (tab) (getf tab :id)) :test #'string=))

(defun tab-bar-tab-names ()
  "The tab ids in display order."
  (mapcar (lambda (tab) (getf tab :id)) *tab-bar-tabs*))

(defcommand tab-bar-mode ()
  "Toggle the ribbon tab strip on yggterm's chrome (the floating panel
rides it: no strip, no ribbon)."
  ;; Empty spec, not bare (interactive): bare never registers for M-x.
  (interactive "")
  (setf *tab-bar-mode-on* (not *tab-bar-mode-on*))
  (bump-document-version)
  (fire-probe :ymacs-tab-bar :event "mode" :visible *tab-bar-mode-on*)
  *tab-bar-mode-on*)

(defcommand tool-bar-mode ()
  "Alias of tab-bar-mode — ymacs' ribbon fuses the tool bar and the tab
bar into one strip (divergence ledger)."
  (interactive "")
  (command-execute 'tab-bar-mode))

(defun tab-bar-select-tab (id)
  "Make the tab ID active. An unknown id is a no-op — the GUI only
posts ids the strip declared, and a Lisp caller spelling one wrong gets
silence, not a broken strip."
  (when (tab-bar-tab id)
    (unless (string= id *tab-bar-active*)
      (setf *tab-bar-active* id)
      (bump-document-version)
      (fire-probe :ymacs-tab-bar :event "select" :tab id))
    id))

(defun tab-bar-add-tab (id name &key after)
  "Add a tab ID named NAME, initially with no groups. AFTER names a tab
id to insert behind; nil appends. A duplicate id is refused (the strip
would key two tabs the same). Returns the new tab, or NIL when refused."
  (if (tab-bar-tab id)
      (progn
        (setf *echo-message* (format nil "tab-bar: tab ~a already exists" id))
        nil)
      (let ((tab (tab-bar-make-tab id name nil)))
        (if after
            (let ((pos (position-if (lambda (candidate) (string= (getf candidate :id) after))
                                    *tab-bar-tabs*)))
              (if pos
                  (push tab (cdr (nthcdr pos *tab-bar-tabs*)))
                  (setf *tab-bar-tabs* (append *tab-bar-tabs* (list tab)))))
            (setf *tab-bar-tabs* (append *tab-bar-tabs* (list tab))))
        (bump-document-version)
        (fire-probe :ymacs-tab-bar :event "add-tab" :tab id)
        tab)))

(defun tab-bar-remove-tab (id)
  "Remove the tab ID. Removing the active tab makes the first remaining
tab active; removing the last tab leaves no strip content (the tabs row
renders empty, the floating panel nothing)."
  (when (tab-bar-tab id)
    (setf *tab-bar-tabs* (remove-if (lambda (tab) (string= (getf tab :id) id)) *tab-bar-tabs*))
    (when (string= id *tab-bar-active*)
      (setf *tab-bar-active* (or (getf (first *tab-bar-tabs*) :id) "")))
    (bump-document-version)
    (fire-probe :ymacs-tab-bar :event "remove-tab" :tab id)
    t))

(defun tab-bar-rename-tab (id name)
  "Set the display NAME of tab ID. The id never changes: actions and
saved keymaps spell ids, not names."
  (let ((tab (tab-bar-tab id)))
    (when tab
      (setf (getf tab :name) name)
      (bump-document-version)
      (fire-probe :ymacs-tab-bar :event "rename-tab" :tab id)
      t)))

(defun tab-bar-group (tab-id label)
  "The group plist with LABEL inside tab TAB-ID, or NIL. An empty label
matches the caption-less group (a tab has at most one)."
  (let ((tab (tab-bar-tab tab-id)))
    (when tab
      (find label (getf tab :groups)
            :key (lambda (group) (getf group :label))
            :test #'string=))))

(defun tab-bar-add-group (tab-id group)
  "Append the GROUP plist (tab-bar-make-group) to tab TAB-ID. Refused
when a group with the same label already exists there — two groups with
one caption is a rendering lie. Returns the group, or NIL when refused."
  (let ((tab (tab-bar-tab tab-id)))
    (cond
      ((not tab)
       (setf *echo-message* (format nil "tab-bar: no tab ~a" tab-id))
       nil)
      ((tab-bar-group tab-id (getf group :label))
       (setf *echo-message*
             (format nil "tab-bar: tab ~a already has group ~a" tab-id (getf group :label)))
       nil)
      (t
       (setf (getf tab :groups) (append (getf tab :groups) (list group)))
       (bump-document-version)
       (fire-probe :ymacs-tab-bar :event "add-group" :tab tab-id :group (getf group :label))
       group))))

(defun tab-bar-remove-group (tab-id label)
  "Remove the group LABEL from tab TAB-ID."
  (let ((tab (tab-bar-tab tab-id)))
    (when tab
      (let ((before (length (getf tab :groups))))
        (setf (getf tab :groups)
              (remove-if (lambda (group) (string= (getf group :label) label))
                         (getf tab :groups)))
        (when (< (length (getf tab :groups)) before)
          (bump-document-version)
          (fire-probe :ymacs-tab-bar :event "remove-group" :tab tab-id :group label)
          t)))))

(defun tab-bar-add-button (tab-id group-label action label &optional title primary)
  "Add a button (tab-bar-make-button) to the group GROUP-LABEL of tab
TAB-ID, creating the group when it does not exist. A duplicate action
within one group is refused — one gesture, one button."
  (let ((tab (tab-bar-tab tab-id)))
    (when tab
      (let ((group (or (tab-bar-group tab-id group-label)
                       (let ((fresh (tab-bar-make-group group-label nil)))
                         (setf (getf tab :groups) (append (getf tab :groups) (list fresh)))
                         fresh))))
        (if (find action (getf group :buttons)
                  :key (lambda (button) (getf button :action))
                  :test #'string=)
            (progn
              (setf *echo-message*
                    (format nil "tab-bar: group ~a already has ~a" group-label action))
              nil)
            (progn
              (setf (getf group :buttons)
                    (append (getf group :buttons)
                            (list (tab-bar-make-button action label (or title label) primary))))
              (bump-document-version)
              (fire-probe :ymacs-tab-bar :event "add-button" :tab tab-id :action action)
              t))))))

(defun tab-bar-remove-button (tab-id group-label action)
  "Remove the button ACTION from the group GROUP-LABEL of tab TAB-ID."
  (let ((group (tab-bar-group tab-id group-label)))
    (when group
      (let ((before (length (getf group :buttons))))
        (setf (getf group :buttons)
              (remove-if (lambda (button) (string= (getf button :action) action))
                         (getf group :buttons)))
        (when (< (length (getf group :buttons)) before)
          (bump-document-version)
          (fire-probe :ymacs-tab-bar :event "remove-button" :tab tab-id :action action)
          t)))))

(defun tab-bar-resolve-primary (primary buf)
  "Resolve a button's :primary for the wire. :BUFFER-MODIFIED means the
Save affordance: lit exactly when BUF holds unsaved changes."
  (if (eq primary :buffer-modified)
      (and buf (buffer-modified-p buf))
      (and primary t)))

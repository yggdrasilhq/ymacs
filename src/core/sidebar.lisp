;;;; sidebar.lisp --- Single sidebar management (max 1 in view)
;;;; Invariant: at most ONE sidebar pane is visible. Spawning a second
;;;; replaces the first; despawn hides all.
;;;;
;;;; Wire shape: ymacs declares exactly ONE rail pane (id "ymacs") via
;;;; OSC 7717 sidebar;declare — the GUI fetches GET /pane/ymacs, and THIS
;;;; module decides which view that pane serves (buffers / outline /
;;;; which-key / settings, or the hidden card). The GUI never learns the
;;;; views; switching views is a document-version edge away.

(in-package #:ymacs)

(defvar *sidebar-visible* t
  "First run greets with the Buffers view (what the old multi-pane declare
auto-opened). Despawn hides; visibility is not yet persisted across
daemon restarts.")
(defvar *current-sidebar-pane* "buffers")
(defvar *sidebar-pane-id* "ymacs"
  "The ONE rail pane id ymacs declares. Views multiplex behind it.")

(defvar *available-panes* '("buffers" "outline" "which-key" "settings")
  "Views the single pane can serve. There is no project view: a name
without a schema is a stub, and stubs do not ship.")
(defvar *sidebar-epoch* 0)

(defun sidebar-visible-p () *sidebar-visible*)

(defun available-panes () *available-panes*)

(defun spawn-sidebar (&optional (pane "buffers"))
  (let ((target (if (member pane *available-panes* :test #'string=) pane "buffers")))
    (setf *sidebar-visible* t
          *current-sidebar-pane* target)
    (incf *sidebar-epoch*)
    ;; The GUI learns views through the /ping document_version edge — a
    ;; switch that moves no stamp is a switch the rail never sees (the
    ;; action reply's own version field is not a refetch door). The doc
    ;; fetch this edge also triggers noops on the identical schema.
    (bump-document-version)
    (fire-probe :ymacs-sidebar-toggle :pane target :visible t)
    (format t "~&[ymacs] Sidebar view: ~a~%" target)
    target))

(defun despawn-sidebar ()
  (setf *sidebar-visible* nil)
  (incf *sidebar-epoch*)
  (bump-document-version)
  (fire-probe :ymacs-sidebar-toggle :pane *current-sidebar-pane* :visible nil)
  (format t "~&[ymacs] Despawned sidebar~%")
  nil)

(defun toggle-sidebar (&optional (pane "buffers"))
  (if (and *sidebar-visible* (string= *current-sidebar-pane* pane))
      (despawn-sidebar)
      (spawn-sidebar pane)))

(defun ymacs-toggle-sidebar-command (&optional pane)
  "Lisp-callable sidebar toggle for M-x ymacs-toggle-sidebar"
  (toggle-sidebar (or pane "buffers")))

(defcommand sidebar (&optional pane)
  "Open the one ymacs sidebar on PANE (a view name; default buffers).
M-x sidebar — the rail holds a single ymacs icon; views switch behind it."
  ;; Empty spec, not bare (interactive): bare never registers in
  ;; *command-interactive-specs*, so M-x cannot name the command.
  (interactive "")
  (spawn-sidebar (or pane "buffers")))

(defvar *tool-bar-visible* t
  "tool-bar-mode: the ribbon strip above the viewport. On by default;
M-x tool-bar-mode toggles. There is deliberately NO menu-bar-mode in
ymacs — the ribbon is the only top chrome (spec-primitives §1.2).")

(defcommand tool-bar-mode ()
  "Toggle the ribbon toolbar above the viewport (ymacs has no menu bar)."
  ;; Empty spec, not bare (interactive): bare never registers for M-x.
  (interactive "")
  (setf *tool-bar-visible* (not *tool-bar-visible*))
  (bump-document-version)
  (fire-probe :ymacs-sidebar-toggle :pane "tool-bar" :visible *tool-bar-visible*)
  *tool-bar-visible*)

(defun sidebar-document-version ()
  (format nil "~a-~a-~a" *frame-epoch* *sidebar-epoch* (if *sidebar-visible* *current-sidebar-pane* "hidden")))

(defun sidebar-pane-schema ()
  "The schema behind the ONE rail pane: whichever view is current, or the
hidden card with a way back. Unknown views fall back to buffers — the
rail never 404s."
  (if (not *sidebar-visible*)
      `(("title" . "Ymacs")
        ("widgets" . ,(vector
                       `(("kind" . "label") ("muted" . t)
                         ("text" . "Sidebar hidden."))
                       `(("kind" . "button") ("id" . "show-sidebar")
                         ("label" . "Show Buffers")
                         ("title" . "Open the sidebar (M-x sidebar)")
                         ("action" . "toggle-sidebar")))))
      (let ((view (if (member *current-sidebar-pane* *available-panes* :test #'string=)
                      *current-sidebar-pane* "buffers")))
        (cond
          ((string= view "which-key") (which-key-schema nil))
          ((string= view "outline") (outline-schema))
          ((string= view "settings") (settings-pane-schema))
          (t (buffers-schema))))))

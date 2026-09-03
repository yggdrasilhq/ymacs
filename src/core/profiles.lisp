;;;; profiles.lisp --- Chrome-style profiles; the perpetual session law
;;;;
;;;; ymacs is PERPETUAL: the daemon outlives GUI restarts and profile
;;;; switches. `M-x sidebar/profiles` switches to another profile the way
;;;; a browser switches tab sets — buffers of one profile are never the
;;;; business of another. Ending the daemon is an explicit act
;;;; (save-buffers-kill-ymacs), never a side effect.
;;;;
;;;; Profiles live in the store (profiles table) and on disk under
;;;; ~/.yggterm/ymacs/profiles/<id>/ (per-profile user.org overrides;
;;;; package and binary caches stay in the base ~/.yggterm/ymacs/).
;;;; See docs/emacs-manual/ymacs/store.texi.

(in-package #:ymacs)

(defun profile-dir (id)
  (merge-pathnames (format nil "profiles/~a/" (json-escape-string id))
                   (state-dir)))

(defun ensure-profile-dir (id)
  (ensure-directories-exist (profile-dir id)))

(defcommand sidebar/profiles ()
  "Open the Profiles sidebar: switch profile, or create one."
  ;; Empty spec, not bare (interactive): bare never registers for M-x.
  (interactive "")
  (spawn-sidebar "profiles")
  (sidebar/profiles--current))

(defun sidebar/profiles--current ()
  "Answer the profiles view (the GUI refetches via the version edge)."
  (bump-document-version)
  *current-sidebar-pane*)

(defun ymacs-switch-profile (id)
  (multiple-value-prog1 (ymacs-switch-profile%raw id)
    (fire-probe :ymacs-profiles :profile id)))

(defun ymacs-switch-profile%raw (id)
  "Switch the live profile: persist this profile's open set, load the
target's, keep the daemon running. Unnamed durable buffers of the old
profile stay in the store — nothing is deleted, nothing is lost."
  (let ((target (and (stringp id) (plusp (length id)) id)))
    (unless target
      (error "profile id required"))
    (unless (string= target *profile*)
      (persist-session)
      (setf *profile* target)
      ;; fresh window: drop all buffers from view (their content either
      ;; lives in a file or in the other profile's rows).
      (setf *current-buffer* nil)
      (clrhash *buffers*)
      ;; Switch never legacy-imports: session.json is a first-boot door.
      (restore-session :allow-legacy nil)
      (store-touch-profile target)
      (ensure-profile-dir target)
      (spawn-sidebar "buffers")
      (bump-document-version)
      (fire-probe :ymacs-profile :action "switch" :profile target))
    *profile*))

(defun profiles-schema ()
  "The profiles view: every profile with the live one selected, plus a
create field. Rows switch (row_action ymacs-switch-profile)."
  (let* ((rows (store-list-profiles))
         (widgets (append
                   (list `(("kind" . "section")
                           ("text" . ,(format nil "Profiles — live: ~a" *profile*))))
                   (loop for (id) in rows
                         collect `(("kind" . "list-row")
                                   ("id" . ,id)
                                   ("title" . ,id)
                                   ("selected" . ,(json-bool (string= id *profile*)))
                                   ("row_action" . "ymacs-switch-profile")))
                   (list `(("kind" . "text-input")
                           ("id" . "new-profile")
                           ("placeholder" . "new profile name…")
                           ("action" . "ymacs-switch-profile"))))))
    `(("title" . "Profiles")
      ("widgets" . ,(coerce widgets 'vector)))))

(defcommand save-buffers-kill-ymacs ()
  "The ONLY way ymacs ends: persist everything, then stop the daemon.
Never called by a GUI restart or a profile switch."
  (interactive "")
  (dolist (buf (list-all-buffers))
    (buffer-sync buf))
  (persist-session)
  (stop))

(defcommand ymacs-switch-profile-command (name)
  "M-x interface over ymacs-switch-profile."
  (interactive "sProfile: ")
  (ymacs-switch-profile name))

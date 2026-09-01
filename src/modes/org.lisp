;;;; org.lisp --- Org mode for ymacs (literate init.org book)

(in-package #:ymacs)

(define-major-mode "org-mode"
  :doc "Org mode — headings, TODO, agenda, babel tangle."
  :hook (lambda (buf)
          (declare (ignore buf))
          (org-set-keybindings)))

(defun org-set-keybindings ()
  (local-set-key "org-mode" "C-c C-c" 'org-ctrl-c-ctrl-c)
  (local-set-key "org-mode" "TAB" 'org-cycle)
  (local-set-key "org-mode" "S-TAB" 'org-shifttab)
  t)

(defun org-cycle (&optional buf)
  (let ((b (or buf *current-buffer*)))
    (when b
      (let* ((content (buffer-content b))
             (pt (buffer-point b))
             (line-start (or (position #\Newline content :end pt :from-end t) 0))
             (line-end (or (position #\Newline content :start pt) (length content)))
             (line (subseq content line-start line-end)))
        (cond
          ((and (> (length line) 0) (char= (char line 0) #\*))
           ;; Toggle folding: for now just move point
           (setf (buffer-point b) line-end)
           t)
          (t nil))))))

(defun org-shifttab (&optional buf)
  (declare (ignore buf))
  t)

(defun org-ctrl-c-ctrl-c (&optional buf)
  (let ((b (or buf *current-buffer*)))
    (when b
      (let ((content (buffer-content b)))
        (when (search "#+begin_src" content)
          (tangle-init-org (when (buffer-file-path b) (namestring (buffer-file-path b)))))))))

(defun org-todo (buf)
  (let ((content (buffer-content buf))
        (pt (buffer-point buf)))
    (let* ((line-start (or (position #\Newline content :end pt :from-end t) 0))
           (line-end (or (position #\Newline content :start pt) (length content)))
           (line (subseq content line-start line-end)))
      (cond
        ((search "TODO" line) (buffer-replace buf "TODO" "DONE"))
        ((search "DONE" line) (buffer-replace buf "DONE" "TODO"))
        (t (buffer-insert buf line-start "TODO "))))))

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

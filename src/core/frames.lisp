;;;; frames.lisp --- Frame = yggterm row (spec-primitives.md §1.3).
;;;;
;;;; Owner law: a new frame IS a new yggterm row from ymacs. make-frame
;;;; asks the GUI this daemon lives in to spawn one more row and launch
;;;; the ymacs CLIENT there — the emacsclient model: the daemon owns
;;;; buffers and state, frames are cheap clients, C-x 5 2 is just another
;;;; surface. The GUI-side seam is `$YGGTERM_BIN server app terminal new`
;;;; (the app-control verb every Tier A app may call for its own needs).

(in-package #:ymacs)

(defvar *frames* nil "Rows ymacs spawned as frames: plists (:row :title).")

(defun yggterm-bin ()
  (or (sb-ext:posix-getenv "YGGTERM_BIN") "yggterm-headless"))

(defun frames-run (bin args)
  "Run a yggterm CLI command, capture stdout."
  (with-output-to-string (out)
    (sb-ext:run-program bin args :output out :error :output :search t :wait t)))

(defun make-frame-command-argv (bin title)
  "The terminal-new ARGUMENTS for one new frame row (run-program gets
BIN separately — the argv starts at the subcommand). Pure — contract
tested without a GUI."
  (declare (ignore bin))
  (list "server" "app" "terminal" "new"
        "--kind" "shell" "--title" title))

(defun frames-parse-row (output)
  "Find the spawned row's path in a terminal-new reply: a JSON
session/session_path field, else the first local:// path in the text.
Tolerant by contract — the reply format is the GUI's to evolve."
  (or (extract-json-string output "session_path")
      (extract-json-string output "session")
      (let ((pos (search "local://" output)))
        (when pos
          (let ((end (position-if
                      (lambda (ch)
                        (member ch '(#\Space #\Tab #\Newline #\Return #\, #\")))
                      output
                      :start pos)))
            (subseq output pos (or end (length output))))))))

(defun make-frame (&optional parameters)
  "Spawn a new yggterm row running the ymacs client (C-x 5 2). Returns
the row path, or NIL when the GUI refused (headless, no daemon row)."
  (declare (ignore parameters))
  (let* ((bin (yggterm-bin))
         (out (frames-run bin (make-frame-command-argv bin "ymacs frame")))
         (row (frames-parse-row out)))
    (if row
        (progn
          (push (list :row row :title "ymacs frame") *frames*)
          ;; Launch the client in the new row: it attaches to THIS daemon
          ;; and declares its own document surface there.
          (frames-run bin (list "server" "app" "terminal" "send" row
                                "--data" (concatenate 'string "ymacs" (string #\Return))))
          (fire-probe :ymacs-frame :event "make" :row row)
          row)
        (progn
          (fire-probe :ymacs-frame :event "refused")
          nil))))

(defun current-frame-row ()
  "This frame's row path, when ymacs runs inside a yggterm row."
  (let ((sess (or (sb-ext:posix-getenv "YGGTERM_SESSION_ID")
                  (sb-ext:posix-getenv "LC_YGGTERM_SESSION_ID"))))
    (when (and sess (plusp (length sess)))
      ;; session ids arrive as scheme://uuid — the same path form
      ;; terminal new returns, so pass through as-is.
      sess)))

(defun delete-frame (&optional frame)
  "Close a frame. NIL means the CURRENT frame: its document surface
closes (ymacs --close semantics) and the row's shell is left — the row
is the user's, only ymacs' surface goes. The daemon survives, exactly
like deleting the last emacsclient frame."
  (let* ((row (or (and frame (getf frame :row))
                  (current-frame-row)))
         (sess (or (sb-ext:posix-getenv "YGGTERM_SESSION_ID")
                   (sb-ext:posix-getenv "LC_YGGTERM_SESSION_ID")
                   "")))
    (when row
      (setf *frames* (remove row *frames* :key (lambda (f) (getf f :row))
                             :test #'string=)))
    (when (and row sess (string= row sess))
      (ignore-errors (emit-close sess)))
    (fire-probe :ymacs-frame :event "delete" :row (or row "current"))
    t))

(defun frame-list ()
  "Emacs parity: the list of live frames (this one first)."
  (cons (list :row (current-frame-row) :title "current") *frames*))

(declare-interactive 'make-frame "")
(declare-interactive 'delete-frame "P")

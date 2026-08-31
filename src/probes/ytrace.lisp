;;;; ytrace.lisp --- In-process microsecond observability probes
;;;; Zero overhead when dormant (fire checks hash). When attached via ytrace
;;;; CLI, probes emit via the file plane (journal) rather than the script
;;;; plane. We mirror yedit's Provider model but in Lisp primitives so the
;;;; same `ytrace attach --app ymacs` verbs work.

(in-package #:ymacs)

(defvar *registered-probes* (make-hash-table :test 'equal))
(defvar *probe-counters* (make-hash-table :test 'equal))
(defvar *probe-ring* (make-array 1024 :initial-element nil))
(defvar *probe-ring-head* 0)

(defstruct probe-def
  name description fields clock sample)

(defun register-probe (name &key description fields (clock :wall) (sample :always))
  (setf (gethash name *registered-probes*)
        (make-probe-def :name name :description description :fields fields
                        :clock clock :sample sample))
  name)

(defun fire-probe (name &rest args &key &allow-other-keys)
  (when (gethash name *registered-probes*)
    ;; Counter for CLI sampling
    (incf (gethash name *probe-counters* 0))
    ;; Ring buffer (file-plane journal mimic)
    (let ((entry (list* :ts (get-internal-real-time)
                        :name name
                        args)))
      (setf (aref *probe-ring* *probe-ring-head*) entry)
      (setf *probe-ring-head* (mod (1+ *probe-ring-head*) (length *probe-ring*)))
      ;; Optional file journal under ~/.yggterm/ymacs/probes.jsonl if YTRACE_FILE set
      (when (sb-ext:posix-getenv "YTRACE_FILE")
        (ignore-errors
          (with-open-file (s (sb-ext:posix-getenv "YTRACE_FILE")
                             :direction :output :if-exists :append :if-does-not-exist :create
                             :external-format :utf-8)
            (format s "~a ~a~%" name args)))))
    t))

(defun list-probes ()
  (loop for k being the hash-keys of *registered-probes* collect k))

(defun probe-count (name)
  (gethash name *probe-counters* 0))

(defun drain-probes ()
  (let (out)
    (loop for i from 0 below (length *probe-ring*)
          for e = (aref *probe-ring* i)
          when e do (push e out))
    (nreverse out)))

;;; Register built-in probes at load time.
(register-probe :ymacs-startup :description "Measures cold start time" :fields '(latency-ms))
(register-probe :ymacs-buffer-mutation :description "Buffer insert/delete" :fields '(buffer-id operation length))
(register-probe :ymacs-redisplay-frame :description "Redisplay cycle" :fields '(frame-id widget-count render-latency-us))
(register-probe :ymacs-sidebar-toggle :description "Sidebar spawn/despawn" :fields '(pane visible))
(register-probe :ymacs-elpa-load :description "ELPA package load" :fields '(package version latency-ms))
(register-probe :ymacs-control-request :description "Control server request" :fields '(method path latency-us))
(register-probe :ymacs-which-key :description "Which-key popup" :fields '(prefix key-count))
(register-probe :ymacs-use-package :description "use-package expansion" :fields '(package defer ensure))

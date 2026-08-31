;;;; ytrace.lisp --- In-process microsecond observability probes

(in-package #:ymacs)

(defvar *registered-probes* (make-hash-table :test 'equal))

(defun register-probe (name &key description fields)
  (setf (gethash name *registered-probes*)
        (list :name name :description description :fields fields)))

(defun fire-probe (name &rest args)
  (when (gethash name *registered-probes*)
    ;; Telemetry fan-out or ring buffer emission
    (values name args)))

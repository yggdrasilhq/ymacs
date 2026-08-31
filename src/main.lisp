;;;; main.lisp --- Entry point for ymacs

(in-package #:ymacs)

(defun start (&key (file nil) (config nil))
  (format t "~&[ymacs] Initializing ymacs v0.1.0 on libyggterm...~%")
  (register-probe :ymacs-startup :description "Measures cold start time" :fields '(latency-ms))
  (start-control-server)
  (make-new-buffer "*scratch*" ";; ymacs scratch buffer --- Common Lisp + ELPA/MELPA")
  (when file
    (format t "~&[ymacs] Opening file: ~a~%" file))
  (when config
    (format t "~&[ymacs] Tangling and loading literate config: ~a~%" config))
  t)

(defun stop ()
  (stop-control-server)
  (format t "~&[ymacs] Clean shutdown completed.~%"))

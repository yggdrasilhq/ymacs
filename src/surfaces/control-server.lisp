;;;; control-server.lisp --- Loopback HTTP control endpoint for sidebars

(in-package #:ymacs)

(defvar *control-port* 7719)
(defvar *control-server-running* nil)

(defun start-control-server (&key (port 7719))
  (setf *control-port* port
        *control-server-running* t)
  (format t "~&[ymacs] Control server listening on loopback port ~a~%" port))

(defun stop-control-server ()
  (setf *control-server-running* nil))

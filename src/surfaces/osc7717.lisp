;;;; osc7717.lisp --- libyggterm OSC 7717 escape emitter

(in-package #:ymacs)

(defun emit-osc-7717 (verb action payload-json)
  "Emit OSC 7717 escape sequence to standard output."
  (format t "~c]7717;~a;~a;~a~c"
          (code-char 27)
          verb
          action
          payload-json
          (code-char 7))
  (force-output))

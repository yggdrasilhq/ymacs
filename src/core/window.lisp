;;;; window.lisp --- Viewport management and frame coordination

(in-package #:ymacs)

(defstruct window-frame
  active-buffer
  width
  height
  split-state)

(defvar *main-window* (make-window-frame :active-buffer nil :width 80 :height 24 :split-state :single))

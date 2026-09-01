;;;; window-manager.lisp --- Tiling window manager (single-sidebar constraint)
;;;; ymacs enforces max 1 sidebar, but allows multiple editor windows tiled
;;;; in the viewport. This file manages the tiling, focus, and resize.

(in-package #:ymacs)

(defstruct tile
  id buffer x y width height focused)

(defvar *tiles* nil)
(defvar *tile-counter* 0)
(defvar *active-tile* nil)

(defun create-tile (buffer &key (x 0) (y 0) (width 80) (height 24))
  (let ((new-tile (make-tile :id (incf *tile-counter*)
                             :buffer buffer :x x :y y :width width :height height :focused t)))
    (dolist (other *tiles*) (setf (tile-focused other) nil))
    (push new-tile *tiles*)
    (setf *active-tile* new-tile)
    (fire-probe :ymacs-tile :action "create" :id (tile-id new-tile))
    new-tile))

(defun close-tile (tile)
  (setf *tiles* (remove tile *tiles*))
  (when (eq *active-tile* tile)
    (setf *active-tile* (first *tiles*))
    (when *active-tile* (setf (tile-focused *active-tile*) t)))
  (bump-document-version)
  t)

(defun focus-tile (tile)
  (dolist (other *tiles*) (setf (tile-focused other) nil))
  (setf (tile-focused tile) t
        *active-tile* tile
        *current-buffer* (tile-buffer tile))
  (bump-document-version))

(defun split-tile-horizontally (tile)
  (let* ((new-width (floor (tile-width tile) 2))
         (new-tile (create-tile (tile-buffer tile) :x (+ (tile-x tile) new-width) :y (tile-y tile)
                                :width (- (tile-width tile) new-width) :height (tile-height tile))))
    (setf (tile-width tile) new-width)
    new-tile))

(defun split-tile-vertically (tile)
  (let* ((new-height (floor (tile-height tile) 2))
         (new-tile (create-tile (tile-buffer tile) :x (tile-x tile) :y (+ (tile-y tile) new-height)
                                :width (tile-width tile) :height (- (tile-height tile) new-height))))
    (setf (tile-height tile) new-height)
    new-tile))

(defun tile-at-point (x y)
  (find-if (lambda (tile) (and (<= (tile-x tile) x (+ (tile-x tile) (tile-width tile)))
                               (<= (tile-y tile) y (+ (tile-y tile) (tile-height tile)))))
           *tiles*))

(defun balance-tiles ()
  (let ((n (length *tiles*)))
    (when (> n 0)
      (let ((w (floor 120 n)))
        (loop for tile in *tiles* for i from 0
              do (setf (tile-x tile) (* i w) (tile-width tile) w))
        (bump-document-version)))))

(defun window-manager-widgets ()
  (mapcar (lambda (tile)
            `(("kind" . "tile") ("id" . ,(princ-to-string (tile-id tile)))
              ("buffer" . ,(buffer-name (tile-buffer tile)))
              ("focused" . ,(tile-focused tile))
              ("x" . ,(tile-x tile)) ("y" . ,(tile-y tile))
              ("width" . ,(tile-width tile)) ("height" . ,(tile-height tile))))
          *tiles*))

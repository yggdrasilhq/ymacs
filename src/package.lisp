;;;; package.lisp --- Package definitions for ymacs

(defpackage #:ymacs
  (:use #:cl #:sqlite)
  (:export #:start
           #:stop
           #:main
           #:current-buffer
           #:open-file
           #:toggle-sidebar
           #:eval-form
           #:make-new-buffer
           #:get-buffer-by-id
           #:list-all-buffers
           #:buffer-content
           #:buffer-insert
           #:buffer-delete
           #:buffer-save
           #:sidebar-visible-p
           #:spawn-sidebar
           #:despawn-sidebar
           #:register-probe
           #:fire-probe
           #:emit-osc-7717
           #:emit-declare
           #:emit-close
           #:start-control-server
           #:stop-control-server
           #:elpa-eval
           #:which-key-enable
           #:*buffers*
           #:*current-buffer*
           #:*daemon-url*
           #:*control-url*
           #:*control-port*))

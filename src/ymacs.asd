;;;; ymacs.asd --- ASDF system definition for ymacs

(asdf:defsystem #:ymacs
  :description "GNU Emacs fork on libyggterm in Common Lisp"
  :author "Avikalpa Kundu <avi@gour.top>"
  :license "GPL-3.0-or-later"
  :version "0.1.0"
  :serial t
  :components ((:file "package")
               (:module "core"
                :components ((:file "buffer")
                             (:file "window")
                             (:file "sidebar")))
               (:module "surfaces"
                :components ((:file "osc7717")
                             (:file "control-server")))
               (:module "probes"
                :components ((:file "ytrace")))
               (:module "elpa"
                :components ((:file "compat")))
               (:file "main")))

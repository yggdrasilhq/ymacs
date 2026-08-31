;;;; ymacs.asd --- ASDF system definition for ymacs

(asdf:defsystem #:ymacs
  :description "GNU Emacs fork on libyggterm in Common Lisp"
  :author "Avikalpa Kundu <avi@gour.top>"
  :license "GPL-3.0-or-later"
  :version "0.1.1"
  :serial t
  :depends-on (:sb-bsd-sockets)
  :components ((:file "package")
               (:module "core"
                :components ((:file "rope")
                             (:file "buffer")
                             (:file "window")
                             (:file "sidebar")))
               (:module "surfaces"
                :components ((:file "osc7717")
                             (:file "control-server")))
               (:module "probes"
                :components ((:file "ytrace")))
               (:module "elpa"
                :components ((:file "compat")
                             (:file "use-package")
                             (:file "which-key")
                             (:file "modern-helpers")
                             (:file "deprecated")))
               (:file "manifest")
               (:file "main")))

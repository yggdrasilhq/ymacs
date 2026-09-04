;;;; ymacs.asd --- ASDF system definition for ymacs

(asdf:defsystem #:ymacs
  :description "GNU Emacs fork on libyggterm in Common Lisp"
  :author "Avikalpa Kundu <avi@gour.top>"
  :license "GPL-3.0-or-later"
  :version "0.1.2"
  :serial t
  :depends-on (:sb-bsd-sockets :cffi :sqlite)
  :components ((:file "package")
               (:module "core"
                :components ((:file "rope")
                             (:file "store")
                             (:file "buffer")
                             (:file "command")
                             (:file "frames")
                             (:file "session")
                             (:file "window")
                             (:file "tab-bar")
                             (:file "sidebar")
                             (:file "window-manager")
                             (:file "settings")
                             (:file "profiles")))
               (:module "surfaces"
                :components ((:file "osc7717")
                             (:file "control-server")))
               (:module "probes"
                :components ((:file "ytrace")))
               (:module "elpa"
                :components ((:file "elisp-reader")
                             (:file "compat")
                             (:file "defmacros")
                             (:file "corpus")
                             (:file "use-package")
                             (:file "which-key")
                             (:file "modern-helpers")
                             (:file "deprecated")))
               (:module "editing"
                :components ((:file "undo")
                             (:file "kill-ring")
                             (:file "search")
                             (:file "macro")
                             (:file "folding")
                             (:file "multiple-cursors")
                             (:file "commands")))
               (:module "modes"
                :components ((:file "fundamental")
                             (:file "dired")
                             (:file "org")
                             (:file "lisp-mode")
                             (:file "python-mode")
                             (:file "c-mode")))
               (:module "shell"
                :components ((:file "eshell")))
               (:module "ui"
                :components ((:file "keymap")
                             (:file "minibuffer")
                             (:file "modeline")
                             (:file "keyboard")
                             (:file "info")))
               (:file "full-emacs")
               (:file "manifest")
               (:file "main")))

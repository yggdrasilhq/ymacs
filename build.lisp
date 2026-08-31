;;;; build.lisp --- Produce ymacs binary image via SBCL save-lisp-and-die
(require :asdf)
(require :sb-bsd-sockets)
(push #P"/home/pi/gh/ymacs/" asdf:*central-registry*)
(push #P"/home/pi/gh/ymacs/src/" asdf:*central-registry*)
(asdf:load-system :ymacs)
(format t "~&[build] Loaded ymacs ~a~%" (asdf:component-version (asdf:find-system :ymacs)))
(format t "[build] Dumping image to ymacs-bin~%")
(sb-ext:save-lisp-and-die "ymacs-bin"
                          :toplevel #'ymacs:main
                          :executable t
                          :save-runtime-options t)

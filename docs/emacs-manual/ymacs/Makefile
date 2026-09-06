ymacs.info: ymacs.texi
	makeinfo --no-split -I ../emacs ymacs.texi -o ymacs.info

.PHONY: install
install: ymacs.info
	mkdir -p ~/.local/share/ymacs
	cp ymacs.info ~/.local/share/ymacs/ymacs.info

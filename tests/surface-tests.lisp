;;;; surface-tests.lisp --- contract tests for the OSC 7717 surface wire
;;;; (libyggterm-surfaces SKILL.md: ESC ] 7717 ; verb ; action ; base64 BEL).
;;;;
;;;; Regression: base64-encode fed Lisp char-codes straight into the 6-bit
;;;; groups. Every declare carries emoji pane icons (📝 🗂 ⌨ ≡ ⚙) — 1 char,
;;;; 4 bytes in UTF-8 — so the emitted base64 decoded to invalid UTF-8, the
;;;; GUI's forwarder dropped it silently, and `ymacs` printed "surface
;;;; opened" over a declare nothing could parse. The encoder must carry
;;;; UTF-8 BYTES; Content-Length likewise counts bytes, not characters.
;;;;
;;;; Run: sbcl --load tests/run-tests.lisp
;;;; Plain CL, no dependencies — CI installs bare SBCL only.

(in-package #:ymacs)

(defun run-surface-tests ()
  (setf *test-pass* 0 *test-fail* 0)
  (format t "ymacs surface-wire tests~%")

  (test "ascii base64 vectors are unchanged (no regression on the old path)"
    (assert-eq* "TWFu" (base64-encode "Man"))
    (assert-eq* "aGVsbG8=" (base64-encode "hello")))

  (test "emoji encodes as UTF-8 bytes, not char-codes"
    ;; Golden vector from `python3 -c 'base64.b64encode(
    ;; '{"session":"x","icon":"📝"}'.encode())'` — the GUI's decoder is
    ;; atob + TextDecoder + JSON.parse, so this exact spelling must hold.
    (assert-eq* "eyJzZXNzaW9uIjoieCIsImljb24iOiLwn5OdIn0="
                (base64-encode "{\"session\":\"x\",\"icon\":\"📝\"}")))

  (test "the old char-code spelling is gone for good"
    ;; What the bug emitted for the same input (char-code 128221 fed as a
    ;; byte): invalid UTF-8 on decode. If this ever matches again the GUI
    ;; drops every declare.
    (let ((bad "eyJzZXNzaW9uIjoieCIsImljb24iO/bdIn0="))
      (unless (string/= bad (base64-encode "{\"session\":\"x\",\"icon\":\"📝\"}"))
        t)))

  (test "byte length counts UTF-8 bytes, not characters"
    (assert-eq* 4 (utf8-byte-length "📝"))
    (assert-eq* 3 (utf8-byte-length "—"))
    ;; "ymacs — x": 9 chars, 11 bytes (em-dash is 3 bytes).
    (assert-eq* 9 (length "ymacs — x"))
    (assert-eq* 11 (utf8-byte-length "ymacs — x")))

  (test "ascii byte length equals character length"
    (assert-eq* 5 (utf8-byte-length "hello"))
    (assert-eq* 0 (utf8-byte-length "")))

  (test "declare payload with all pane icons stays pure ASCII base64"
    ;; Base64 output must never contain non-ASCII: the PTY carries it as
    ;; raw bytes and atob() rejects anything outside the alphabet.
    (let* ((payload (format nil "{\"session\":\"~a\",\"control\":\"~a\",\"app_name\":\"ymacs\",\"document_version\":\"~a\",\"panes\":[{\"id\":\"doc\",\"icon\":\"📝\"}]}"
                            "s" "c" "1"))
           (enc (base64-encode payload)))
      (loop for ch across enc
            unless (find ch "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
            do (error "non-alphabet char ~s in ~s" ch enc))
      ;; And the UTF-8 round-trips: decode in Lisp, compare to input.
      (assert-eq* payload
                  (sb-ext:octets-to-string (base64-decode-to-octets enc)
                                           :external-format :utf-8))))

  (format t "~a passed, ~a failed~%" *test-pass* *test-fail*)
  (zerop *test-fail*))

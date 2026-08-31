# Agent Interaction & Headless Orchestration

`ymacs` is designed for seamless collaboration between human developers and autonomous AI coding agents.

## 1. Deterministic Headless Verbs

Agents can inspect and manipulate ymacs state without needing a GUI or simulating keystrokes:

```bash
# Evaluate Lisp expression in running ymacs instance
ymacs eval "(buffer-name (current-buffer))"

# Inspect buffer list in JSON format
ymacs buffers --format json

# Insert text into specific buffer at position
ymacs buffer-insert --buffer "main.lisp" --pos 120 --text "(defun test () t)"

# Replace text in buffer
ymacs buffer-replace --buffer "init.org" --target "* Old Heading" --replacement "* New Heading"
```

## 2. Draft Stability and Buffer Identity

Following the `libyggterm` contract, all buffer fields carry explicit `value_key` identifiers. Concurrent edits by human users and AI agents are resolved with deterministic revision checks to prevent focus loss and cursor jumping.

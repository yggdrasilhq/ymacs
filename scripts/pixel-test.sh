#!/usr/bin/env bash
# pixel-test.sh — automated basic-task verification for ymacs (step: pixel
# testing, user directive 2026-09-04). Drives a LIVE ymacs daemon through
# its control server (the same action plane the GUI key plane uses),
# asserts state after each step, and captures the row's pixels for the
# human/agent eye. Exits non-zero on the first failed assertion.
#
# Usage: scripts/pixel-test.sh [--keep]   (--keep leaves the row + daemon up)
#
# Requirements on this host: the ymacs binary installed (bin/ymacs +
# ymacs-bin), a running yggterm GUI (rows are spawned in it), jq or python3.
set -euo pipefail

KEEP=0; [ "${1:-}" = "--keep" ] && KEEP=1
HOST_GUI=$(pgrep -x yggterm | head -1 || true)
if [ -z "$HOST_GUI" ]; then echo "pixel-test: no live yggterm GUI on this host"; exit 1; fi
YGG=~/.local/bin/yggterm-headless
CTL_DIR=~/.yggterm/ymacs
SHOTDIR=~/.yggterm/scratchpad/ymacs-pixel/$(date +%Y%m%d-%H%M%S)
mkdir -p "$SHOTDIR"
PASS=0; FAIL=0

say()  { printf '%s\n' "$*"; }
ok()   { PASS=$((PASS+1)); say "  ok: $*"; }
bad()  { FAIL=$((FAIL+1)); say "  FAIL: $*"; }
check() { # check <desc> <want> <got>
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want [$2] got [$3])"; fi
}

# The daemon (and its control server) lives where the row spawned — often
# dev, even when the pixels show here. Resolve the control URL accordingly.
CTL_URL="$(cat $CTL_DIR/control-url 2>/dev/null || true)"
if [ -z "$CTL_URL" ]; then
  CTL_URL="http://127.0.0.1$(ssh dev 'cat ~/.yggterm/ymacs/control-url' 2>/dev/null | python3 -c "import sys,json;print(json.load(sys.stdin).get('port',''))" 2>/dev/null | sed 's/^/:/')"
fi
if [ -z "$CTL_URL" ] || [ "$CTL_URL" = "http://127.0.0.1" ]; then
  CTL_URL="ssh"
fi
ctl() { # ctl <path> -> GET (route to wherever the daemon runs)
  if [ "$CTL_URL" = "ssh" ]; then
    ssh dev "curl -s --max-time 5 \"\$(cat ~/.yggterm/ymacs/control-url)$1\""
  else
    curl -s --max-time 5 "$CTL_URL$1"
  fi
}
act() { # act <json-body> -> POST /action
  if [ "$CTL_URL" = "ssh" ]; then
    ssh dev "curl -s --max-time 5 -X POST \"\$(cat ~/.yggterm/ymacs/control-url)/action\" -H 'Content-Type: application/json' -d '$1'"
  else
    curl -s --max-time 5 -X POST "$CTL_URL/action" \
         -H 'Content-Type: application/json' -d "$1"
  fi
}
doc_field() { # doc_field <json> <key>
  python3 -c "import json,sys;d=json.load(sys.stdin);print(json.dumps(d.get('$2'),default=str))" 2>/dev/null
}

say "== pixel-test: launch ymacs in a fresh row =="
ctl_check() {
  ctl /ping >/dev/null 2>&1 && return 0 || return 1
}
if ctl_check; then
  ok "reusing the running daemon"
else
  $YGG server app launch-app ymacs new --cwd ~/.yggterm/scratchpad/ymacs-pixel >/dev/null 2>&1 || true
  for i in $(seq 1 30); do ctl_check && break; sleep 1; done
  ctl_check || { bad "daemon did not come up"; exit 1; }
  ok "daemon control server reachable"
fi
sleep 1

say "== 1. boot law: manual buffer active, schema has ribbon + editor =="
DOC=$(ctl /pane/doc)
TITLE=$(printf '%s' "$DOC" | doc_field - title | tr -d '"')
case "$TITLE" in ymacs*) ok "schema title carries a buffer ($TITLE)";; *) bad "schema title ($TITLE)";; esac
RIBBON_KIND=$(printf '%s' "$DOC" | python3 -c "
import json,sys
d=json.load(sys.stdin)
r=d.get('ribbon') or []
kinds=[w.get('kind') for w in r]
print('ribbon-bar' if 'ribbon-bar' in kinds else (kinds[0] if kinds else 'none'))")
check "ribbon payload is a ribbon-bar" "ribbon-bar" "$RIBBON_KIND"

say "== 2. type a marker through the key plane (point may sit anywhere) =="
# Save what the buffer holds BEFORE typing: the store is durable by law,
# so a test that types and does not restore pollutes every later boot
# (found live 2026-09-04 — three runs of old markers greeted the boot).
SAVED_JSON=$(ctl /pane/doc | python3 -c "import json,sys
d=json.load(sys.stdin)
ed=[x for x in (d.get('widgets') or []) if x.get('id')=='editor']
import json as j
print(j.dumps((ed[0].get('value') or '') if ed else '', ensure_ascii=False))")
MARK="ZQX$(date +%H%M%S)"
for w in $(echo "$MARK" | fold -w1); do act "{\"action\":\"key\",\"values\":{\"key\":\"$w\"}}" >/dev/null; done
CONTENT=$(ctl /pane/doc | python3 -c "import json,sys
d=json.load(sys.stdin)
w=(d.get('widgets') or [{}])
ed=[x for x in w if x.get('id')=='editor']
print('y' if '$MARK' in (ed[0].get('value') if ed else '') else 'n')")
check "key plane typed the marker $MARK" "y" "$CONTENT"

say "== 3. undo through the ribbon's command action =="
for i in $(seq 1 ${#MARK}); do act '{"action":"command:undo"}' >/dev/null; done
CONTENT=$(ctl /pane/doc | python3 -c "import json,sys
d=json.load(sys.stdin)
w=(d.get('widgets') or [{}])
ed=[x for x in w if x.get('id')=='editor']
print('y' if '$MARK' in (ed[0].get('value') if ed else '') else 'n')")
check "undo removed the marker" "n" "$CONTENT"

say "== 4. ribbon tabs switch groups (document version edge) =="
V1=$(act '{"action":"ribbon-tab:view"}' | doc_field - document_version | tr -d '"')
RIBBON=$(ctl /pane/doc)
ACTIVE=$(printf '%s' "$RIBBON" | python3 -c "
import json,sys
d=json.load(sys.stdin)
r=d.get('ribbon') or []
bar=[w for w in r if w.get('kind')=='ribbon-bar']
print(bar[0].get('active') if bar else 'none')")
check "view tab active" "view" "$ACTIVE"
act '{"action":"ribbon-tab:home"}' >/dev/null

say "== 5. M-x by name (command:execute-extended-command opens the palette) =="
act '{"action":"command:execute-extended-command"}' >/dev/null
PALETTE=$(ctl /pane/doc | python3 -c "import json,sys
d=json.load(sys.stdin)
w=(d.get('widgets') or [])
print('y' if any(x.get('kind')=='search' or x.get('id','').startswith('minibuffer') for x in w) else 'n')")
check "palette opened" "y" "$PALETTE"
act '{"action":"key","values":{"key":"C-g"}}' >/dev/null

say "== 5b. cleanup: restore the buffer the test typed into =="
if [ -n "${SAVED_JSON:-}" ]; then
  # Build the whole request body in python: the content rides three
  # escaping levels (HTTP JSON -> form string -> CL literal), and hand
  # -pasted escapes broke the body JSON every time.
  BODY=$(python3 -c "
import json,sys
saved = json.loads(sys.argv[1])
form = '(progn (setf (buffer-content *current-buffer*) ' + json.dumps(saved, ensure_ascii=False) + ') (bump-document-version))'
print(json.dumps({'action': 'eval', 'form': form}))" "$SAVED_JSON")
  act "$BODY" >/dev/null
  sleep 1   # the version-bumped schema apply can lag the action reply
  RESTORED=$(ctl /pane/doc | python3 -c "import json,sys
d=json.load(sys.stdin)
ed=[x for x in (d.get('widgets') or []) if x.get('id')=='editor']
v=(ed[0].get('value') or '') if ed else ''
import json as j
want=j.loads(sys.argv[1])
if v==want:
    print('y')
else:
    sys.stderr.write('DBG lens %d/%d vhead=%r wanthead=%r' % (len(v), len(want), v[:36], want[:36]))
    print('n')" "$SAVED_JSON")
  check "buffer restored to pre-test content" "y" "$RESTORED"
else
  bad "could not save pre-test content (cleanup skipped)"
fi

say "== 6. pixels: capture the row through the GUI =="
ROW=$($YGG server snapshot 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
s=d.get('data',d)
for sess in (s.get('live_sessions') or []):
    if 'ymacs' in str(sess.get('title','')).lower():
        print(sess.get('session_path')); break" 2>/dev/null || true)
if [ -n "${ROW:-}" ]; then
  $YGG server app screenshot "$SHOTDIR/row.png" --session "$ROW" >/dev/null 2>&1 || \
    $YGG server app screenshot "$SHOTDIR/row.png" >/dev/null 2>&1 || true
  [ -s "$SHOTDIR/row.png" ] && ok "screenshot captured: $SHOTDIR/row.png" || bad "screenshot missing"
else
  bad "could not find the ymacs row for the screenshot"
fi

say "== summary: $PASS ok, $FAIL failed (shots in $SHOTDIR) =="
if [ "$KEEP" != "1" ]; then
  say "(daemon left running — it is the user's live state; use --keep next time)"
fi
[ "$FAIL" = "0" ]

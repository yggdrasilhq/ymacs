path = "/home/pi/gh/ymacs--pixel-fixes/scripts/pixel-test.sh"
with open(path) as f: s = f.read()
old = """  RESTORED=$(ctl /pane/doc | python3 -c \"import json,sys
d=json.load(sys.stdin)
ed=[x for x in (d.get('widgets') or []) if x.get('id')=='editor']
v=(ed[0].get('value') or '') if ed else ''
import json as j
print('y' if v == j.loads(sys.argv[1]) else 'n')\" \"\$SAVED_JSON\")"""
assert old in s, "comparison block not found: " + s[s.find("RESTORED"):s.find("RESTORED")+200]
new = """  RESTORED=$(ctl /pane/doc | python3 -c \"import json,sys
d=json.load(sys.stdin)
ed=[x for x in (d.get('widgets') or []) if x.get('id')=='editor']
v=(ed[0].get('value') or '') if ed else ''
import json as j
want=j.loads(sys.argv[1])
if v==want:
    print('y')
else:
    sys.stderr.write('DBG lens %d vs %d; v-head %r; want-head %r\\n' % (len(v), len(want), v[:40], want[:40]))
    print('n')\" \"\$SAVED_JSON\")"""
s = s.replace(old, new)
with open(path, "w") as f: f.write(s)
print("dbg patched")

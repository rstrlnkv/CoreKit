"""Exercise the terminal client with an offline JSON-RPC peer."""
import json
import os
from pathlib import Path
import subprocess
import runpy
from unittest.mock import patch
import sys

root = Path(__file__).resolve().parents[1]
stage = Path(sys.argv[1])
client = stage / "clients/coremodel/client.py"
client.parent.mkdir(parents=True)
client.write_bytes((root / "clients/coremodel/client.py").read_bytes())
# Git Bash must come from the Git for Windows installation, even when PATH names WSL bash.
namespace = runpy.run_path(str(client))
git_root = stage / "Git With Spaces"
git_bash = git_root / "bin/bash.exe"
git_bash.parent.mkdir(parents=True)
git_bash.touch()
for git_location in ("cmd/git.exe", "mingw64/bin/git.exe"):
    executables = {"git.exe": str(git_root / git_location), "codex.cmd": "codex.cmd",
                   "bash.exe": str(stage / "System32/bash.exe")}
    with patch("shutil.which", side_effect=executables.get):
        assert namespace["windows_commands"]() == ("codex.cmd", str(git_bash))
# Git Bash sessions can put Git's internal executable or a PATH shim first.
usr_bash = git_root / "usr/bin/bash.exe"
usr_bash.parent.mkdir(parents=True)
usr_bash.touch()
cygpath = usr_bash.with_name("cygpath.exe")
cygpath.touch()
executables = {"git.exe": str(stage / "shims/git.exe"), "codex.exe": "codex.exe",
               "cygpath.exe": str(cygpath), "bash.exe": str(stage / "System32/bash.exe")}
with patch("shutil.which", side_effect=executables.get):
    assert namespace["windows_commands"]() == ("codex.exe", str(usr_bash))
# A PowerShell PATH can have neither Bash nor cygpath. The shim still reports Git's exec path.
del executables["cygpath.exe"]
with patch("shutil.which", side_effect=executables.get), patch("subprocess.check_output",
        return_value=str(git_root / "mingw64/libexec/git-core") + "\n"):
    assert namespace["windows_commands"]() == ("codex.exe", str(git_bash))
hook = stage / "plugins/coremodel/codex/hint.sh"
hook.parent.mkdir(parents=True)
hook.write_text("""if [ "$1" = --settings ]; then echo "$ROUTING"; exit; fi
test "$1" = --recommend || exit 3
cat >> "$EVENTS"
echo "$PICK"
""")
peer = stage / "codex"
peer.write_text("""#!/usr/bin/env python3
import json, os, sys
assert 'app-server' in sys.argv
def send(data): print(json.dumps(data), flush=True)
for line in sys.stdin:
    msg=json.loads(line)
    if 'id' not in msg: continue
    if 'method' not in msg:
        decision = msg.get('result',{}).get('decision')
        with open(os.environ['DECISIONS'],'a') as out: print(decision,file=out)
        continue
    method=msg['method']
    if method=='turn/start':
        params=msg['params']
        with open(os.environ['TURNS'],'a') as out: print(json.dumps(params),file=out)
        result={'turn':{'id':'turn'}}
    elif method=='thread/start':
        result={'thread':{'id':'chat'},'model':os.environ.get('BASE_MODEL','gpt-6-luna'),'reasoningEffort':os.environ.get('BASE_EFFORT','low') or None}
    elif method=='model/list':
        result={'data':[{'model':name,'defaultReasoningEffort':efforts[0] if efforts else 'none', 'supportedReasoningEfforts':[{'reasoningEffort':e} for e in efforts]} for name,efforts in [('gpt-6.2-sol',['medium','high']),('gpt-6-luna',['low','medium']),('other-model',['high']),('fixed',[])]]}
    elif method=='initialize': result={}
    else: raise RuntimeError(method)
    send({'id':msg['id'],'result':result})
    if method=='turn/start':
        if os.environ.get('REQUEST_APPROVAL'):
            send({'id':'approval','method':'item/commandExecution/requestApproval','params':{'command':'ls', 'cwd':'/tmp'}})
            send({'method':'item/started','params':{'item':{'id':'edit','type':'fileChange','changes':[{'path':'example.py','diff':'+value'}]},'threadId':'chat','turnId':'turn'}})
            send({'id':'file','method':'item/fileChange/requestApproval','params':{'itemId':'edit','threadId':'chat','turnId':'turn'}})
        send({'method':'item/completed','params':{'threadId':'chat','turnId':'turn','item':{'type':'agentMessage','text':'Reply.'}}})
        send({'method':'turn/completed','params':{'threadId':'chat','turn':{'id':'turn','status':'completed'}}})
""")
peer.chmod(0o755)
sol = {"model":"gpt-6.2-sol","effort":"medium"}
luna = {"model":"gpt-6-luna","effort":"low"}
other = {"model":"other-model","effort":"high"}
for routing, allow_model, base_effort, pick, flags, stdin, expected in [
    ("ask", True, "low", sol, [], "First\nother-model\nhigh\nSecond\ngpt-6-luna\nlow\n",
     [("First",other), ("Second",luna)]),
    ("ask", True, "low", sol, [], "First\nc\nRevised\ngpt-6.2-sol\nmedium\n", [("Revised",sol)]),
    ("ask", True, "low", sol, [], "First\ngpt-6.2-sol\nc\n", []),
    ("ask", True, "", dict(luna,effort="medium"), [], "First\nmedium\n",
     [("First",dict(luna,effort="medium"))]),
    ("ask", False, "low", dict(luna,effort="medium"), [], "First\nmedium\n",
     [("First",dict(luna,effort="medium"))]),
    ("ask", True, "low", luna, [], "First\n", [("First",{})]),
    ("ask", True, "low", sol, [], "First\nfixed\nnone\n", [("First",{"model":"fixed","effort":"none"})]),
    ("auto", True, "low", sol, [], "First\n", [("First",sol)]),
    ("off", True, "low", sol, ["--auto"], "First\ny\n\n", [("First",{})]),
    ("ask", True, "low", sol, ["--auto"], "First\ny\n\n", [("First",sol)]),
]:
    turns = stage / "turns"
    turns.write_text("")
    events = stage / "events"
    events.write_text("")
    decisions = stage / "decisions"
    decisions.write_text("")
    env = dict(os.environ, PATH=str(stage)+os.pathsep+os.environ["PATH"], TURNS=str(turns),
               EVENTS=str(events), DECISIONS=str(decisions), REQUEST_APPROVAL="1" if flags else "",
               PICK=json.dumps(pick), BASE_EFFORT=base_effort,
               ROUTING=json.dumps({"mode":routing,"pickModel":allow_model}))
    r = subprocess.run([sys.executable, str(client), *flags], input=stdin, cwd=stage, text=True,
                       capture_output=True, env=env, timeout=15)
    assert r.returncode == 0, (r.stdout,r.stderr)
    rows = [json.loads(line) for line in turns.read_text().splitlines()]
    assert len(rows) == len(expected), (rows, expected,r.stdout,r.stderr)
    for row, (message, overrides) in zip(rows,expected):
        assert row["threadId"] == "chat"
        assert row["input"][0]["text"] == message
        assert {k:row[k] for k in ("model","effort") if k in row} == overrides
    if len(rows)==2:
        assert 'Reply.' in events.read_text()
        assert r.stdout.index("other-model") < r.stdout.index("Choose effort")
        assert "recommended" in r.stdout and "current" in r.stdout
    if not base_effort or not allow_model:
        assert "Choose model" not in r.stdout and "Choose effort" in r.stdout
    if routing=="off":
        assert not events.read_text()
    if "c\n" in stdin:
        assert "First" in r.stdout
    if flags:
        assert decisions.read_text().splitlines() == ["accept", "decline"]
        assert "example.py" in r.stdout and "ls" in r.stdout

# Unknown custom model and effort: a turn override would have no known restoration value.
turns.write_text("")
r = subprocess.run([sys.executable, str(client), "--auto"], input="First\n", cwd=stage,
                   text=True, capture_output=True, timeout=15,
                   env=dict(env, BASE_MODEL="custom", BASE_EFFORT="", REQUEST_APPROVAL=""))
assert r.returncode == 0 and not turns.read_text(), (r.stdout,r.stderr)
assert "/model gpt-6.2-sol --reasoning=medium" in r.stdout

# A dead peer and a rejected request must not announce a successful turn or replay the input.
for script, error in [
    ("#!/bin/sh\nread -r request\n", "disconnected"),
    ("#!/bin/sh\nread -r request\necho '{\"id\":1,\"error\":{\"message\":\"unsupported\"}}'\n", "unsupported"),
]:
    peer.write_text(script)
    result = subprocess.run([sys.executable, str(client), "--auto"], input="First\n",
                            cwd=stage, text=True, env=env, capture_output=True, timeout=15)
    assert result.returncode != 0 and error in result.stderr

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
hook.write_text('test "$1" = --recommend || exit 3\ncat >> "$EVENTS"\necho \'{"model":"gpt-6.2-sol","effort":"medium"}\'\n')
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
        result={'thread':{'id':'chat'},'model':'gpt-6-luna','reasoningEffort':'low'}
    elif method=='model/list':
        result={'data':[{'model':'gpt-6.2-sol','supportedReasoningEfforts':[{'reasoningEffort':'medium'}]}]}
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
for mode, stdin, expected in [
    ([], "First\ny\nSecond\n", [{"model":"gpt-6.2-sol","effort":"medium"}, {}]),
    ([], "First\nn\n", [{}]),
    ([], "First\n", []),
    ([], "First\nc\n", []),
    (["--auto"], "First\ny\n\n", [{"model":"gpt-6.2-sol","effort":"medium"}]),
]:
    turns = stage / "turns"
    turns.write_text("")
    events = stage / "events"
    events.write_text("")
    decisions = stage / "decisions"
    decisions.write_text("")
    env = dict(os.environ, PATH=str(stage)+os.pathsep+os.environ["PATH"], TURNS=str(turns),
               EVENTS=str(events), DECISIONS=str(decisions), REQUEST_APPROVAL="1" if mode else "")
    r = subprocess.run([sys.executable, str(client), *mode], input=stdin, cwd=stage, text=True,
                       capture_output=True, env=env, timeout=15)
    assert r.returncode == 0, (r.stdout,r.stderr)
    rows = [json.loads(line) for line in turns.read_text().splitlines()]
    assert len(rows) == len(expected), (rows, expected,r.stdout,r.stderr)
    for i,(row, overrides) in enumerate(zip(rows,expected)):
        assert row["threadId"] == "chat"
        assert row["input"][0]["text"] == ["First","Second"][i]
        assert {k:row[k] for k in ("model","effort") if k in row} == overrides
    if len(rows)==2:
        assert 'Reply.' in events.read_text()
    if mode:
        assert decisions.read_text().splitlines() == ["accept", "decline"]
        assert "example.py" in r.stdout and "ls" in r.stdout

# A dead peer and a rejected request must not announce a successful turn or replay the input.
for script, error in [
    ("#!/bin/sh\nread -r request\n", "disconnected"),
    ("#!/bin/sh\nread -r request\necho '{\"id\":1,\"error\":{\"message\":\"unsupported\"}}'\n", "unsupported"),
]:
    peer.write_text(script)
    result = subprocess.run([sys.executable, str(client), "--auto"], input="First\n",
                            cwd=stage, text=True, env=env, capture_output=True, timeout=15)
    assert result.returncode != 0 and error in result.stderr

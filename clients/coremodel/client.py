#!/usr/bin/env python3
"""Run a Codex terminal chat with CoreModel routing before each turn."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from collections import deque


HOOK = Path(__file__).resolve().parents[2] / "plugins/coremodel/codex/hint.sh"


def windows_commands():
    codex = shutil.which("codex.exe") or shutil.which("codex.cmd")
    git = shutil.which("git.exe")
    if not codex or not git:
        raise RuntimeError("Install Codex CLI and Git for Windows and add them to PATH.")
    git_bin = Path(git).resolve().parent
    root = git_bin.parent
    if root.name.lower() in ("mingw64", "mingw32", "clangarm64"):
        root = root.parent
    bash = root / "bin/bash.exe"
    if bash.is_file():
        return codex, str(bash)

    # Git Bash puts its MSYS utilities on PATH even if git.exe is a shim.
    cygpath = shutil.which("cygpath.exe")
    if cygpath:
        bash = Path(cygpath).with_name("bash.exe")
        if bash.is_file():
            return codex, str(bash)

    # A native shell may expose only the Git shim. Ask Git for its installation prefix.
    try:
        exec_path = subprocess.check_output([git, "--exec-path"], encoding="utf-8").strip()
    except (OSError, subprocess.CalledProcessError) as error:
        raise RuntimeError(f"Cannot query Git for Windows at {git}: {error}") from error
    for prefix in Path(exec_path).parents:
        if prefix.name.casefold() in ("mingw64", "mingw32", "clangarm64", "ucrt64", "usr"):
            for relative in ("bin/bash.exe", "usr/bin/bash.exe"):
                bash = prefix.parent / relative
                if bash.is_file():
                    return codex, str(bash)
            break
    raise RuntimeError(f"Cannot locate Git Bash for {git} (exec path: {exec_path}). "
                       "Start the client in Git Bash or add its usr/bin directory to PATH.")


class AppServer:
    def __init__(self, codex):
        # This process handles CoreModel before the turn. Preserve the other plugins.
        self.process = subprocess.Popen(
            [codex, "-c", 'plugins."coremodel@corekit".enabled=false',
             "app-server", "--listen", "stdio://"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, encoding="utf-8",
        )
        self.sequence = 0
        self.events = deque()
        self.edits = {}

    def close(self):
        try:
            self.process.stdin.close()
            self.process.wait(timeout=3)
        except (BrokenPipeError, subprocess.TimeoutExpired):
            self.process.kill()
            self.process.wait()
        finally:
            self.process.stdout.close()

    def send(self, message):
        self.process.stdin.write(json.dumps(message) + "\n")
        self.process.stdin.flush()

    def read(self):
        while True:
            line = self.process.stdout.readline()
            if not line:
                raise RuntimeError("Codex App Server disconnected.")
            msg = json.loads(line)
            params = msg.get("params", {})
            item = params.get("item", {})
            key = params.get("threadId"), params.get("turnId"), item.get("id")
            if msg.get("method") == "item/started" and item.get("type") == "fileChange":
                self.edits[key] = item.get("changes")
            elif msg.get("method") == "item/completed":
                self.edits.pop(key, None)
            if "method" not in msg or "id" not in msg:
                return msg
            method = msg["method"]
            if method in ("item/commandExecution/requestApproval", "item/fileChange/requestApproval"):
                if method == "item/fileChange/requestApproval":
                    details = self.edits.get((params.get("threadId"), params.get("turnId"), params.get("itemId")))
                    reviewable = bool(details) and not params.get("grantRoot")
                else:
                    details = params.get("command")
                    reviewable = bool(details) and params.get("kind", "command") == "command"
                print(method, json.dumps(params, indent=2))
                if method == "item/fileChange/requestApproval" and details:
                    print(json.dumps(details, indent=2))
                # Approval is always explicit, even in automatic routing mode.
                try:
                    accept = reviewable and input("Allow this action once [y/N]? ").strip().lower() == "y"
                except EOFError:
                    accept = False
                self.send({"id": msg["id"], "result": {"decision": "accept" if accept else "decline"}})
            else:
                print(f"Unsupported Codex request: {method}", file=sys.stderr)
                self.send({"id": msg["id"], "error": {"code": -32601,
                           "message": "This terminal client does not support this server request."}})

    def request(self, method, params):
        self.sequence += 1
        self.send({"id": self.sequence, "method": method, "params": params})
        while True:
            msg = self.read()
            if msg.get("id") == self.sequence:
                if "error" in msg:
                    raise RuntimeError(f"{method}: {msg['error']}")
                return msg["result"]
            if msg.get("method") in ("item/completed", "turn/completed"):
                self.events.append(msg)

    def finish_turn(self, thread, turn):
        reply = []
        while True:
            msg = self.events.popleft() if self.events else self.read()
            params = msg.get("params", {})
            if params.get("threadId") != thread:
                continue
            if msg.get("method") == "item/completed" and params.get("turnId") == turn:
                item = params["item"]
                if item["type"] == "agentMessage":
                    print(item["text"], flush=True)
                    reply.append(item["text"])
            if msg.get("method") == "turn/completed" and params["turn"]["id"] == turn:
                if params["turn"].get("status") != "completed":
                    print(f"Turn {params['turn']['status']}: {params['turn'].get('error')}", file=sys.stderr)
                return "\n".join(reply)


def catalog(server, path):
    models = {}
    defaults = {}
    cursor = None
    while True:
        page = server.request("model/list", {"cursor": cursor})
        for row in page["data"]:
            if not row.get("hidden"):
                defaults[row["model"]] = row["defaultReasoningEffort"]
                models[row["model"]] = [e["reasoningEffort"] for e in row["supportedReasoningEfforts"]]
                if not models[row["model"]]:
                    models[row["model"]] = [defaults[row["model"]]]
        cursor = page.get("nextCursor")
        if not cursor:
            break
    path.write_text(json.dumps({"models": [
        {"slug": name, "visibility": "list",
         "supported_reasoning_levels": [{"effort": e} for e in efforts]}
        for name, efforts in models.items()
    ]}))
    return models, defaults


def recommend(bash, prompt, model, reply, catalog_file, models):
    event = {"hook_event_name": "UserPromptSubmit", "model": model,
             "prompt": prompt, "last_assistant_message": reply[-600:]}
    env = dict(os.environ, COREMODEL_CATALOG=catalog_file.as_posix())
    env.pop("COREMODEL_NESTED", None)
    try:
        call = subprocess.run([bash, HOOK.as_posix(), "--recommend"], input=json.dumps(event),
                              env=env, encoding="utf-8", capture_output=True, check=True)
        result = json.loads(call.stdout)
        if result.get("keep") is True:
            return None
        if result["model"] in models and result["effort"] in models[result["model"]]:
            return result["model"], result["effort"]
    except (subprocess.CalledProcessError, KeyError, TypeError, ValueError, AttributeError):
        pass
    print("Recommendation unavailable. Using current settings.", file=sys.stderr)
    return None


def choose(label, options, recommended, current):
    print(f"Choose {label}:")
    for number, value in enumerate(options, 1):
        marks = [name for name, choice in (("recommended", recommended), ("current", current))
                 if value == choice]
        suffix = f" ({', '.join(marks)})" if marks else ""
        print(f"  {number}. {value}{suffix}")
    while True:
        try:
            answer = input("Enter a number or name (c to cancel): ").strip()
        except KeyboardInterrupt:
            print()
            return None
        if answer == "c":
            return None
        if answer in options:
            return answer
        if answer.isascii() and answer.isdecimal() and len(answer) <= len(str(len(options))):
            number = int(answer)
            if 1 <= number <= len(options):
                return options[number - 1]


def edit_prompt(draft):
    if not draft:
        return input("> ")
    if sys.stdin.isatty():
        try:
            import readline
        except ImportError:
            pass
        else:
            readline.set_startup_hook(lambda: readline.insert_text(draft))
            try:
                return input("> ")
            finally:
                readline.set_startup_hook(None)
    print(f"Draft: {draft}")
    return input("Edit the draft, or press Enter to resubmit it: ") or draft


def routing_settings(bash):
    result = subprocess.run([bash, HOOK.as_posix(), "--settings"], check=True,
                            capture_output=True, encoding="utf-8")
    settings = json.loads(result.stdout)
    return settings["mode"], settings["pickModel"]


def chat(server, bash, auto, catalog_file):
    server.request("initialize", {"clientInfo": {"name": "coremodel_terminal", "version": "1"}})
    server.send({"method": "initialized"})
    mode, pick_model = routing_settings(bash)
    if auto and mode != "off":
        mode = "auto"
    models, defaults = catalog(server, catalog_file)
    thread = server.request("thread/start", {"cwd": str(Path.cwd())})
    thread_id = thread["thread"]["id"]
    baseline_model = thread["model"]
    baseline_effort = thread.get("reasoningEffort")
    restore_effort = baseline_effort or defaults.get(baseline_model)
    active = baseline_model, restore_effort
    reply = ""
    draft = ""
    while True:
        prompt = edit_prompt(draft)
        draft = ""
        if not prompt.strip():
            continue
        model, effort = baseline_model, baseline_effort
        pick = None if mode == "off" else recommend(bash, prompt, model, reply, catalog_file, models)
        if pick and (pick_model or pick[0] == model) and pick != (model, effort):
            print(f"CoreModel recommends {pick[0]} · {pick[1]}.", flush=True)
            if mode == "auto":
                model, effort = pick
            else:
                effort_only = not pick_model or (model == pick[0] and effort is None)
                if not effort_only:
                    options = list(models)
                    if baseline_model not in models:
                        options.append(baseline_model)
                    model = choose("model", options, pick[0], model)
                if model is None:
                    draft = prompt
                    continue
                # An unlisted current model has no published effort options.
                if model in models:
                    effort = choose("effort", models[model], pick[1] if model == pick[0] else None,
                                    effort if model == baseline_model else None)
                    if effort is None:
                        draft = prompt
                        continue
        if not restore_effort and (model, effort) != (baseline_model, baseline_effort):
            print("Codex did not report a restorable effort for the current model. "
                  f"In ordinary Codex enter /model {model} --reasoning={effort}, "
                  f"then resend your prompt: {prompt}")
            continue
        # App Server can carry overrides forward. Restore the chat baseline explicitly.
        params = {"threadId": thread_id, "input": [{"type": "text", "text": prompt}]}
        effective_effort = effort or restore_effort
        if active != (model, effective_effort):
            params.update(model=model, effort=effective_effort)
        turn = server.request("turn/start", params)
        active = model, effective_effort
        reply = server.finish_turn(thread_id, turn["turn"]["id"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--auto", action="store_true", help="apply recommendations without asking")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="coremodel-client-") as temporary:
        codex, bash = windows_commands() if os.name == "nt" else ("codex", "bash")
        server = AppServer(codex)
        try:
            chat(server, bash, args.auto, Path(temporary) / "models.json")
        finally:
            server.close()


if __name__ == "__main__":
    try:
        main()
    except EOFError:
        pass
    except KeyboardInterrupt:
        sys.exit(130)
    except (OSError, RuntimeError, ValueError, KeyError) as exc:
        sys.exit(f"CoreModel: {exc}")

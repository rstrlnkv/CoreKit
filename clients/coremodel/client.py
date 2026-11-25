#!/usr/bin/env python3
"""Run a Codex terminal chat with CoreModel routing before each turn."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from collections import deque


HOOK = Path(__file__).resolve().parents[2] / "plugins/coremodel/codex/hint.sh"


class AppServer:
    def __init__(self):
        # This process handles CoreModel before the turn. Preserve the other plugins.
        self.process = subprocess.Popen(
            ["codex", "-c", 'plugins."coremodel@corekit".enabled=false',
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
    cursor = None
    while True:
        page = server.request("model/list", {"cursor": cursor})
        for row in page["data"]:
            if not row.get("hidden"):
                models[row["model"]] = [e["reasoningEffort"] for e in row["supportedReasoningEfforts"]]
        cursor = page.get("nextCursor")
        if not cursor:
            break
    path.write_text(json.dumps({"models": [
        {"slug": name, "visibility": "list",
         "supported_reasoning_levels": [{"effort": e} for e in efforts]}
        for name, efforts in models.items()
    ]}))
    return models


def recommend(prompt, model, reply, catalog_file, models):
    event = {"hook_event_name": "UserPromptSubmit", "model": model,
             "prompt": prompt, "last_assistant_message": reply[-600:]}
    env = dict(os.environ, COREMODEL_CATALOG=str(catalog_file))
    env.pop("COREMODEL_NESTED", None)
    try:
        call = subprocess.run(["bash", str(HOOK), "--recommend"], input=json.dumps(event),
                              env=env, text=True, capture_output=True, check=True)
        result = json.loads(call.stdout)
        if result.get("keep") is True:
            return None
        if result["model"] in models and result["effort"] in models[result["model"]]:
            return result["model"], result["effort"]
    except (subprocess.CalledProcessError, KeyError, TypeError, ValueError, AttributeError):
        pass
    print("Recommendation unavailable. Using current settings.", file=sys.stderr)
    return None


def chat(server, auto, catalog_file):
    server.request("initialize", {"clientInfo": {"name": "coremodel_terminal", "version": "1"}})
    server.send({"method": "initialized"})
    models = catalog(server, catalog_file)
    thread = server.request("thread/start", {"cwd": str(Path.cwd())})
    thread_id = thread["thread"]["id"]
    current = thread["model"], thread.get("reasoningEffort")
    reply = ""
    while True:
        prompt = input("> ")
        if not prompt.strip():
            continue
        pick = recommend(prompt, current[0], reply, catalog_file, models)
        params = {"threadId": thread_id, "input": [{"type": "text", "text": prompt}]}
        if pick and pick != current:
            print(f"CoreModel recommends {pick[0]} · {pick[1]}.", flush=True)
            answer = "y" if auto else ""
            while answer not in ("y", "n", "c"):
                answer = input("Apply [y], keep current [n], cancel [c]? ").strip().lower()
            if answer == "c":
                continue
            if answer == "y":
                params.update(model=pick[0], effort=pick[1])
        turn = server.request("turn/start", params)
        if "model" in params:
            current = pick
        reply = server.finish_turn(thread_id, turn["turn"]["id"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--auto", action="store_true", help="apply recommendations without asking")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="coremodel-client-") as temporary:
        server = AppServer()
        try:
            chat(server, args.auto, Path(temporary) / "models.json")
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

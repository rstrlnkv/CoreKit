"""Evaluate the shipped Codex classifier on labeled, bilingual prompts."""
import argparse
import json
import math
import os
from pathlib import Path
import shlex
import shutil
import statistics
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
CASES = ROOT / "evals/coremodel-quality/cases.jsonl"
HOOK = ROOT / "plugins/coremodel/codex/hint.sh"
MODELS = ("gpt-6-luna", "gpt-6.2-sol", "gpt-6.2-astra")
EFFORTS = ("low", "medium", "high", "xhigh", "max")


def read_cases():
    cases = [json.loads(line) for line in CASES.read_text().splitlines()]
    allowed = {"keep"} | {m.split("-")[-1] + ":" + e for m in MODELS for e in EFFORTS}
    if (not cases or len({c["id"] for c in cases}) != len(cases)
            or {c["lang"] for c in cases} != {"en", "ru"}
            or any(c["expected"] not in allowed or not c["prompt"].strip() for c in cases)):
        raise ValueError("Invalid or incomplete quality corpus")
    return cases


def evaluate(case, env, stage, hook_path):
    response = stage / "answer"
    response.unlink(missing_ok=True)
    event = {"session_id": case["id"], "model": "unranked", "cwd": str(stage)}
    def hook(fields):
        subprocess.run(["bash", str(hook_path)], input=json.dumps(dict(event, **fields)),
                       text=True, cwd=stage, env=env, capture_output=True, check=True, timeout=30)
    start = time.monotonic()
    try:
        if "reply" in case:
            hook({"hook_event_name": "Stop", "last_assistant_message": case["reply"]})
        start = time.monotonic()
        hook({"hook_event_name": "UserPromptSubmit", "prompt": case["prompt"]})
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
        return "no-valid-answer", time.monotonic() - start
    elapsed = time.monotonic() - start
    actual = "no-valid-answer"
    if response.is_file():
        try:
            choice = json.loads(response.read_text())
            if choice.get("keep") is True:
                actual = "keep"
            elif (choice.get("keep") is False and choice.get("model") in MODELS
                  and choice.get("effort") in EFFORTS):
                actual = choice["model"].split("-")[-1] + ":" + choice["effort"]
        except (ValueError, AttributeError):
            pass
    return actual, elapsed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="validate labels without any model calls")
    parser.add_argument("--case", action="append", default=[], help="evaluate only these case IDs")
    args = parser.parse_args()
    cases = read_cases()
    if args.case:
        if set(args.case) - {c["id"] for c in cases}:
            parser.error("unknown case ID")
        cases = [case for case in cases if case["id"] in args.case]
    if args.check:
        return 0
    real = shutil.which("codex")
    if not real:
        parser.error("codex is required")
    with tempfile.TemporaryDirectory(prefix="coremodel-quality.") as temporary:
        stage = Path(temporary)
        source = stage / "hook"
        shutil.copytree(HOOK.parent, source)
        config = stage / "settings"
        config.write_text("codex_hint: on\ncodex_confirm: off\n")
        # The caller supplies an isolated signed-in CODEX_HOME. The cache belongs to Codex.
        # Pin the offered choices only for the hook; restore the original home for the real CLI.
        catalog = stage / "catalog"
        catalog.mkdir()
        (catalog / "models_cache.json").write_text(json.dumps({"models": [
            {"slug": m, "visibility": "list"} for m in MODELS]}))
        wrapper = stage / "codex"
        home = os.environ.get("CODEX_HOME", str(Path.home() / ".codex"))
        wrapper.write_text("#!/bin/bash\nset -o pipefail\nCODEX_HOME=" + shlex.quote(home)
                           + " " + shlex.quote(real) + ' "$@" | tee '
                           + shlex.quote(str(stage / "answer")) + "\n")
        wrapper.chmod(0o700)
        env = dict(os.environ, PATH=str(stage) + os.pathsep + os.environ["PATH"],
                   CODEX_HOME=str(catalog), COREMODEL_CONFIG=str(config), XDG_STATE_HOME=str(stage / "state"))
        env.pop("COREMODEL_NESTED", None)
        counts = {"en": [], "ru": []}
        times = []
        missing = 0
        for case in cases:
            actual, elapsed = evaluate(case, env, stage, source / HOOK.name)
            counts[case["lang"]].append(actual == case["expected"])
            times.append(elapsed)
            missing += actual == "no-valid-answer"
            print(f'{case["id"]}\t{case["expected"]}\t{actual}\t{elapsed:.1f}s', flush=True)
        for lang, results in counts.items():
            if not results:
                continue
            print(f"{lang}: {sum(results)}/{len(results)} exact")
        p95 = sorted(times)[math.ceil(0.95 * len(times)) - 1]
        print(f"no valid response: {missing}; median {statistics.median(times):.1f}s, p95 {p95:.1f}s")
        return int(not all(all(results) for results in counts.values()))


if __name__ == "__main__":
    sys.exit(main())

"""Turns queued paper drawings into USDZ keepsakes with Codex and Blender, one at a time.

Runs on the host next to the Codex login (not in the web container):
    JOBS_DIR=/opt/pocketrealm/jobs python3 drawing_worker.py
Codex runs in its workspace-write sandbox inside a fresh per-job directory with no network,
so instructions hidden in a drawing can't reach anything outside that directory.
"""
import json
import os
import re
import shutil
import subprocess
import time

import drawings

KIT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "drawing_kit")
CODEX = os.environ.get("CODEX", "codex")
JOB_TIMEOUT = int(os.environ.get("DRAWING_TIMEOUT", "420"))
MAX_MODEL_BYTES = 15_000_000
KEEP_SECONDS = 24 * 3600
PROMPT = ("Turn the attached drawing (drawing.jpg) into a 3D game piece by following AGENTS.md "
          "and QUEST.md in this directory. Reply with only the object name.")
KINDS = {"tool", "character", "object"}
VOICES = {"high", "low", "normal"}
DEFAULT_VERBS = {"tool": "use", "character": "help", "object": "use"}


def clean_name(raw):
    words = re.sub(r"[^a-z ]+", " ", str(raw).lower()).split()[:3]
    name = " ".join(words)
    return name if 2 <= len(name) <= 32 else "drawing"


def clean_line(raw, limit):
    """Kid-facing speech: printable text only, single-spaced, bounded."""
    if not isinstance(raw, str):
        return ""
    text = " ".join("".join(ch for ch in raw if ch.isprintable()).split())
    return text[:limit].rstrip()


def clean_card(result, name):
    kind = result.get("kind") if result.get("kind") in KINDS else "object"
    verb = re.sub(r"[^a-z ]+", "", str(result.get("verb", "")).lower()).strip()
    verb = " ".join(verb.split()[:2])[:14] or DEFAULT_VERBS[kind]
    try:
        uses = min(5, max(1, int(result.get("uses", 2))))
    except (TypeError, ValueError):
        uses = 2
    title = clean_line(result.get("title", ""), 24) if kind == "character" else ""
    raw_lines = result.get("lines") if isinstance(result.get("lines"), list) else []
    lines = [line for line in (clean_line(item, 140) for item in raw_lines[:10]) if line][:3]
    return {"name": name, "kind": kind, "title": title, "verb": verb, "uses": uses,
            "arrival": clean_line(result.get("arrival", ""), 160), "success": clean_line(result.get("success", ""), 160),
            "lines": lines, "voice": result.get("voice") if result.get("voice") in VOICES else "normal"}


def quest_brief(job_id):
    try:
        with open(drawings.job_path(job_id, "context.json")) as handle:
            context = json.load(handle)
    except (OSError, ValueError):
        context = {}
    friend = context.get("friend", "a little friend")
    if context.get("purpose") == "challenge" and context.get("challenge"):
        situation = (f"The player is helping {friend} in their room. {context['challenge']}\n\n"
                     "Their drawing is their solution. Decide, generously and creatively, how it solves this.")
    else:
        situation = (f"This is the player's sidekick for an adventure with {friend}. It will float beside them, "
                     "chat, and may help with puzzles later.")
    return "# The game situation (from the app, not from the player)\n\n" + situation + "\n"


def codex_command(workdir, last_message):
    return [CODEX, "exec", "--skip-git-repo-check", "--ephemeral", "--ignore-user-config",
            "--sandbox", "workspace-write", "--cd", workdir,
            "--output-last-message", last_message, "--image", "drawing.jpg", "--", PROMPT]


def run_job(job_id):
    drawings.write_status(job_id, **{**drawings.read_status(job_id), "status": "working", "started": time.time()})
    started = time.monotonic()
    workdir = drawings.job_path(job_id, "work")
    shutil.rmtree(workdir, ignore_errors=True)
    shutil.copytree(KIT, workdir)
    shutil.copy(drawings.job_path(job_id, "input.jpg"), os.path.join(workdir, "drawing.jpg"))
    with open(os.path.join(workdir, "QUEST.md"), "w") as handle:
        handle.write(quest_brief(job_id))
    log_path = drawings.job_path(job_id, "codex.log")
    with open(log_path, "w") as log:
        try:
            result = subprocess.run(codex_command(workdir, drawings.job_path(job_id, "reply.txt")),
                                    stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                                    timeout=JOB_TIMEOUT)
            exit_code = result.returncode
        except subprocess.TimeoutExpired:
            exit_code = "timeout"
    model = os.path.join(workdir, "model.usdz")
    seconds = round(time.monotonic() - started, 1)
    if not os.path.isfile(model) or not 500 <= os.path.getsize(model) <= MAX_MODEL_BYTES:
        print(f"Drawing {job_id[:8]} failed after {seconds}s (codex exit {exit_code})", flush=True)
        drawings.write_status(job_id, **{**drawings.read_status(job_id), "status": "failed", "seconds": seconds,
            "error": "Codex couldn't build this drawing in 3D. Try a bolder, simpler drawing."})
        return
    with open(model, "rb") as handle:
        if handle.read(4) != b"PK\x03\x04":  # USDZ is an uncompressed zip archive
            drawings.write_status(job_id, **{**drawings.read_status(job_id), "status": "failed", "seconds": seconds,
                "error": "The 3D export was damaged. Try again."})
            return
    try:
        with open(os.path.join(workdir, "result.json")) as handle:
            result = json.load(handle)
        if not isinstance(result, dict):
            raise ValueError
    except (OSError, ValueError):
        result = {}
    name = clean_name(result.get("name", ""))
    card = clean_card(result, name)
    shutil.move(model, drawings.job_path(job_id, "model.usdz"))
    preview = os.path.join(workdir, "preview.png")
    if os.path.isfile(preview):
        shutil.move(preview, drawings.job_path(job_id, "preview.png"))
    print(f"Drawing {job_id[:8]} ready in {seconds}s: {name}", flush=True)
    drawings.write_status(job_id, **{**drawings.read_status(job_id), "status": "ready", "name": name,
                                     "card": card, "seconds": seconds})


def recover():
    # A crash or restart mid-job leaves it "working"; run it again from the start.
    for job_id, status in drawings.all_jobs():
        if status.get("status") == "working":
            drawings.write_status(job_id, **{**status, "status": "queued"})


def prune():
    cutoff = time.time() - KEEP_SECONDS
    for job_id, status in list(drawings.all_jobs()):
        if status.get("status") in ("ready", "failed") and status.get("created", 0) < cutoff:
            shutil.rmtree(drawings.job_path(job_id), ignore_errors=True)


def main():
    recover()
    print(f"Drawing worker watching {drawings.jobs_dir()}", flush=True)
    last_prune = 0
    while True:
        queue = [job_id for _, job_id in drawings.pending()
                 if drawings.read_status(job_id).get("status") == "queued"]
        if queue:
            run_job(queue[0])
            continue
        if time.time() - last_prune > 3600:
            prune()
            last_prune = time.time()
        time.sleep(1)


if __name__ == "__main__":
    main()

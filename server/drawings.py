"""Drawing-to-3D job queue shared by the HTTP server and the Codex/Blender worker.

Each job is a directory under JOBS_DIR named by an unguessable hex ID:
    input.jpg      the cropped paper drawing uploaded by the app
    context.json   why it was drawn: {"purpose": sidekick|challenge, "challenge": "...", "friend": "..."}
    status.json    {"status": queued|working|ready|failed, ...}
    model.usdz     the finished model (ready jobs only)
The server only creates jobs and reads them; drawing_worker.py moves them through the pipeline.
"""
import base64
import json
import os
import re
import time
import uuid

MAX_IMAGE_BYTES = 2_000_000
MAX_PENDING = 6
MAX_CONTEXT = 600
PURPOSES = {"sidekick", "challenge"}
JOB_ID = re.compile(r"^[0-9a-f]{32}$")


def jobs_dir():
    path = os.environ.get("JOBS_DIR") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "jobs")
    os.makedirs(path, exist_ok=True)
    return path


def job_path(job_id, *parts):
    if not isinstance(job_id, str) or not JOB_ID.match(job_id):
        raise KeyError(job_id)
    return os.path.join(jobs_dir(), job_id, *parts)


def write_status(job_id, **fields):
    # Write-then-rename so readers never see a half-written file.
    path = job_path(job_id, "status.json")
    temporary = path + ".tmp"
    with open(temporary, "w") as handle:
        json.dump(fields, handle)
    os.replace(temporary, path)


def read_status(job_id):
    try:
        with open(job_path(job_id, "status.json")) as handle:
            return json.load(handle)
    except (FileNotFoundError, json.JSONDecodeError):
        raise KeyError(job_id)


def all_jobs():
    for name in os.listdir(jobs_dir()):
        if JOB_ID.match(name):
            try:
                yield name, read_status(name)
            except KeyError:
                continue


def pending():
    return sorted(((status.get("created", 0), job_id) for job_id, status in all_jobs()
                   if status.get("status") in ("queued", "working")))


def submit(body):
    if not isinstance(body, dict) or not isinstance(body.get("image"), str):
        raise ValueError("Send a photo of your drawing.")
    try:
        image = base64.b64decode(body["image"], validate=True)
    except ValueError as error:
        raise ValueError("The drawing photo couldn't be read.") from error
    if not image.startswith(b"\xff\xd8") or not 1_000 <= len(image) <= MAX_IMAGE_BYTES:
        raise ValueError("The drawing must be a JPEG photo under 2 MB.")
    if len(pending()) >= MAX_PENDING:
        raise RuntimeError("The drawing workshop is busy. Try again in a few minutes.")
    context = drawing_context(body)
    job_id = uuid.uuid4().hex
    os.makedirs(job_path(job_id))
    with open(job_path(job_id, "input.jpg"), "wb") as handle:
        handle.write(image)
    with open(job_path(job_id, "context.json"), "w") as handle:
        json.dump(context, handle)
    write_status(job_id, status="queued", created=time.time())
    return {"id": job_id, "status": "queued"}


def drawing_context(body):
    """The game situation the drawing answers. App-written, but still treated as untrusted text."""
    purpose = body.get("purpose", "sidekick")
    if purpose not in PURPOSES:
        raise ValueError("Unknown drawing purpose.")
    context = {"purpose": purpose}
    for field in ("challenge", "friend"):
        value = body.get(field)
        if value is None:
            continue
        if not isinstance(value, str) or len(value) > MAX_CONTEXT:
            raise ValueError("The drawing's quest details are too long.")
        context[field] = " ".join(value.split())
    return context


def public_status(job_id):
    """What the app may see: no file paths, logs, or Codex output."""
    status = read_status(job_id)
    reply = {"id": job_id, "status": status.get("status", "failed")}
    if reply["status"] == "queued":
        queue = [ident for _, ident in pending()]
        reply["ahead"] = queue.index(job_id) if job_id in queue else 0
    if reply["status"] == "ready":
        reply["name"] = status.get("name", "drawing")
        if isinstance(status.get("card"), dict):
            reply["card"] = status["card"]
    if reply["status"] == "failed":
        reply["error"] = status.get("error", "Couldn't turn this drawing into 3D. Try a bolder drawing.")
    return reply


def model_file(job_id):
    if read_status(job_id).get("status") != "ready":
        raise KeyError(job_id)
    path = job_path(job_id, "model.usdz")
    if not os.path.isfile(path):
        raise KeyError(job_id)
    return path

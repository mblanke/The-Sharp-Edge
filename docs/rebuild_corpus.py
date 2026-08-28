#!/usr/bin/env python3
"""Re-ingest the sources the base64 purge emptied, through the fixed pipeline.

Order matters: a file is only worth re-reading once `docling_client.py` scrubs images
and emits page breaks, and only after the purge has removed its poisoned points —
otherwise deterministic point ids collide and the purge deletes the fresh chunks.

Sequential on purpose. One file at a time keeps the GB10s available for the assistants
and for interactive asks; this is a background repair, not a race.

Usage:
    python3 rebuild_corpus.py plan  [FolderName ...]   # what would run, in order
    python3 rebuild_corpus.py run   [FolderName ...]   # do it

With no folder arguments every affected corpus is rebuilt, Cooking first.
"""

import json
import os
import sqlite3
import subprocess
import sys
import time
import urllib.request

REPORT = "/tmp/rag-remediate-report.json"
STATE_DB = "/data/state.db"          # inside the rag-api container
HOST_ROOT = "/mnt/media/References"  # same tree as /mnt/references in the container
LOG = "/tmp/rag-rebuild.log"

#: Below this share of surviving chunks, a source is effectively gone and must be reread.
REBUILD_BELOW = 0.5
#: Cooking is the shelf this work started from, so it goes first; the rest follow by size.
PRIORITY = ["Cooking"]


def log(msg: str) -> None:
    line = f"[{time.strftime('%H:%M:%S')}] {msg}"
    print(line, flush=True)
    with open(LOG, "a") as f:
        f.write(line + "\n")


def host_path(container_path: str) -> str:
    return container_path.replace("/mnt/references", HOST_ROOT, 1)


def folder_of(container_path: str) -> str:
    rest = container_path.removeprefix("/mnt/references/")
    return rest.split("/", 1)[0] if "/" in rest else rest


def targets(only: list[str]) -> list[dict]:
    report = json.load(open(REPORT))
    rows = [s for s in report["sources"] if s["fraction"] >= REBUILD_BELOW]
    rows = [s for s in rows if os.path.isfile(host_path(s["source_path"]))]
    if only:
        rows = [s for s in rows if folder_of(s["source_path"]) in only]

    def key(s):
        f = folder_of(s["source_path"])
        return (PRIORITY.index(f) if f in PRIORITY else len(PRIORITY), -s["poisoned"])

    return sorted(rows, key=key)


def clear_state(container_path: str) -> None:
    """Drop the file's row so `is_changed` cannot skip it as unchanged."""
    script = (
        "import sqlite3;"
        f"c=sqlite3.connect({STATE_DB!r});"
        "c.execute('delete from processed_files where file_path=?', (path,));"
        "c.commit()"
    )
    subprocess.run(
        ["docker", "exec", "rag-api", "python", "-c", f"path={container_path!r}\n{script}"],
        check=False,
        capture_output=True,
    )


def ingest(container_path: str) -> dict:
    req = urllib.request.Request(
        "http://localhost:8099/ingest",
        json.dumps({"file_path": container_path}).encode(),
        {"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=7200) as r:
        return json.load(r)


def main() -> None:
    mode = sys.argv[1]
    only = sys.argv[2:]
    rows = targets(only)
    total_lost = sum(s["poisoned"] for s in rows)
    log(f"{mode}: {len(rows)} sources to rebuild ({total_lost:,} poisoned chunks purged)")

    by_folder: dict[str, int] = {}
    for s in rows:
        by_folder[folder_of(s["source_path"])] = by_folder.get(folder_of(s["source_path"]), 0) + 1
    log("  " + ", ".join(f"{f}:{n}" for f, n in by_folder.items()))

    if mode == "plan":
        for s in rows[:40]:
            log(f"  {s['poisoned']:>7,} lost  {s['source_path'].split('/')[-1][:70]}")
        if len(rows) > 40:
            log(f"  … and {len(rows) - 40} more")
        return

    t0 = time.time()
    ok = failed = 0
    for i, s in enumerate(rows, 1):
        path = s["source_path"]
        log(f"({i}/{len(rows)}) {path.split('/')[-1][:70]}")
        clear_state(path)
        try:
            res = ingest(path)
            if res.get("status") == "ok":
                ok += 1
                log(f"    -> {res.get('chunks', 0):,} chunks (was {s['chunks']:,}, "
                    f"{s['poisoned']:,} of them poison)")
            else:
                failed += 1
                log(f"    -> FAILED: {str(res.get('error'))[:160]}")
        except Exception as exc:  # a stuck file must not stop the run
            failed += 1
            log(f"    -> ERROR: {str(exc)[:160]}")
    log(f"REBUILD DONE in {(time.time()-t0)/60:.0f} min — {ok} ok, {failed} failed")


if __name__ == "__main__":
    main()

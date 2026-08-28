#!/usr/bin/env python3
"""Purge base64-poisoned chunks from references_v2, then report per source.

Cause: rag-api's docling client extracted embedded images for vision description but
never removed them from the chunked text (and its regex missed docling's line-wrapped
base64, so nothing was described either). Measured on a 10k random sample: 73% of the
whole collection was base64 noise. The pipeline is fixed (docling_client.py, backup
.bak-imagescrub); this cleans up what it left behind.

Two passes so scroll pagination never races its own deletes:
  A. scroll everything, classify, write poisoned ids + per-source stats to disk
  B. delete by id in batches

Classifier is deliberately conservative: a chunk is poison only when, after removing
long base64 runs, almost no prose remains. A hacking doc quoting a base64 payload
inside real prose is kept.

Usage:  python3 remediate_corpus.py scan     # pass A (safe, read-only)
        python3 remediate_corpus.py purge    # pass B (deletes what scan found)
"""

import json
import re
import sys
import time
import urllib.request

Q = "http://localhost:6333/collections/references_v2"
IDS_FILE = "/tmp/rag-poison-ids.txt"
REPORT = "/tmp/rag-remediate-report.json"

B64_RUN = re.compile(r"[A-Za-z0-9+/=]{100,}")
WS = re.compile(r"\s+")


def post(path, payload, timeout=180):
    req = urllib.request.Request(
        Q + path, json.dumps(payload).encode(), {"Content-Type": "application/json"}
    )
    return json.load(urllib.request.urlopen(req, timeout=timeout))


def is_poison(text: str) -> bool:
    t = (text or "").strip()
    if len(t) < 200:
        return False
    # join wrapped lines so a base64 block split by newlines still reads as one run
    joined = WS.sub("", t)
    if re.fullmatch(r"[A-Za-z0-9+/=]+", joined):
        return True  # the whole chunk is one base64 blob
    remaining = B64_RUN.sub("", joined)
    # after dropping long runs, is there any real prose left?
    return len(remaining) < 40


def scan() -> None:
    t0 = time.time()
    total = poisoned = 0
    per_source: dict[str, list[int]] = {}
    offset = None
    with open(IDS_FILE, "w") as out:
        while True:
            body = {
                "limit": 1000,
                "with_payload": ["text", "source_path"],
                "with_vector": False,
            }
            if offset is not None:
                body["offset"] = offset
            r = post("/points/scroll", body)["result"]
            for p in r["points"]:
                total += 1
                sp = str(p["payload"].get("source_path") or "?")
                stat = per_source.setdefault(sp, [0, 0])
                stat[0] += 1
                if is_poison(p["payload"].get("text", "")):
                    poisoned += 1
                    stat[1] += 1
                    out.write(f"{p['id']}\n")
            offset = r.get("next_page_offset")
            if total % 100_000 < 1000:
                print(
                    f"[{time.time()-t0:6.0f}s] scanned {total:,} — poisoned {poisoned:,}",
                    flush=True,
                )
            if offset is None:
                break

    report = {
        "scanned": total,
        "poisoned": poisoned,
        "sources": [
            {"source_path": sp, "chunks": n, "poisoned": bad, "fraction": round(bad / n, 3)}
            for sp, (n, bad) in sorted(per_source.items(), key=lambda kv: -kv[1][1])
            if bad
        ],
    }
    with open(REPORT, "w") as f:
        json.dump(report, f, indent=1)
    print(
        f"SCAN DONE in {time.time()-t0:.0f}s: {poisoned:,}/{total:,} poisoned "
        f"({poisoned/max(total,1):.0%}) across {len(report['sources'])} sources — "
        f"ids in {IDS_FILE}, report in {REPORT}",
        flush=True,
    )


def purge() -> None:
    t0 = time.time()
    with open(IDS_FILE) as f:
        ids = [ln.strip() for ln in f if ln.strip()]
    print(f"purging {len(ids):,} points", flush=True)
    deleted = 0
    for i in range(0, len(ids), 1000):
        batch = ids[i : i + 1000]
        # every 20th batch waits, so qdrant's queue never runs away from us
        wait = "?wait=true" if (i // 1000) % 20 == 19 else ""
        post(f"/points/delete{wait}", {"points": batch})
        deleted += len(batch)
        if deleted % 100_000 < 1000:
            print(f"[{time.time()-t0:6.0f}s] deleted {deleted:,}/{len(ids):,}", flush=True)
    post("/points/delete?wait=true", {"points": ids[-1:]})  # final barrier
    print(f"PURGE DONE in {time.time()-t0:.0f}s: {deleted:,} points removed", flush=True)


if __name__ == "__main__":
    {"scan": scan, "purge": purge}[sys.argv[1]]()

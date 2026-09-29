#!/usr/bin/env python3
"""Check or bump the runtime versions pinned as ARGs in the Dockerfile.

    bump-pins.py check [--min-age DAYS]   report, write nothing
    bump-pins.py update [--min-age DAYS]  rewrite the ARGs in place

A pin moves to the newest stable release of its current major that is at
least --min-age days old (default 3), so a release pulled soon after
publication never lands. Newer majors are only reported. The sprig stage is
not handled here: it moves together with the relay's upstream commit.

When GITHUB_OUTPUT is set, update also writes `changed`, `summary` and
`majors` (one "name pinned -> version" per line) for the workflow.
"""

import json
import os
import re
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

DOCKERFILE = Path(__file__).resolve().parents[1] / "Dockerfile"

# ARG name -> (source, package)
PINS = {
    "CLAUDE_ACP_VERSION": ("npm", "@agentclientprotocol/claude-agent-acp"),
    "CODEX_ACP_VERSION": ("npm", "@agentclientprotocol/codex-acp"),
    "GOOSE_VERSION": ("github", "block/goose"),
    "NOBLE_CURVES_VERSION": ("npm", "@noble/curves"),
    "NOBLE_HASHES_VERSION": ("npm", "@noble/hashes"),
}

STABLE = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)$")


def fetch(url):
    headers = {"User-Agent": "buzz-agent-docker bump-pins"}
    token = os.environ.get("GITHUB_TOKEN")
    if token and url.startswith("https://api.github.com/"):
        headers["Authorization"] = f"Bearer {token}"
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=30) as r:
        return json.load(r)


def parse_time(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def releases(source, package):
    """Every stable release as (version tuple, published datetime)."""
    if source == "npm":
        doc = fetch("https://registry.npmjs.org/" + urllib.parse.quote(package, safe="@"))
        times = doc.get("time", {})
        out = []
        for v in doc.get("versions", {}):
            m = STABLE.match(v)
            if m and v in times:
                out.append((tuple(map(int, m.groups())), parse_time(times[v])))
        return out
    doc = fetch(f"https://api.github.com/repos/{package}/releases?per_page=100")
    out = []
    for rel in doc:
        m = STABLE.match(rel["tag_name"])
        if m and not rel["draft"] and not rel["prerelease"] and rel["published_at"]:
            out.append((tuple(map(int, m.groups())), parse_time(rel["published_at"])))
    return out


def fmt(v):
    return ".".join(map(str, v))


def plan(text, min_age):
    """Yield (arg, pinned, same-major target or None, newer major or None)."""
    cutoff = datetime.now(timezone.utc) - timedelta(days=min_age)
    for arg, (source, package) in PINS.items():
        m = re.search(rf"^ARG {arg}=(\S+)$", text, re.M)
        if not m or not STABLE.match(m.group(1)):
            sys.exit(f"{arg}: no pinned X.Y.Z version in {DOCKERFILE.name}")
        pinned = tuple(map(int, STABLE.match(m.group(1)).groups()))
        aged = [v for v, t in releases(source, package) if t <= cutoff]
        same = max((v for v in aged if v[0] == pinned[0] and v > pinned), default=None)
        major = max((v for v in aged if v[0] > pinned[0]), default=None)
        yield arg, pinned, same, major


def main():
    args = sys.argv[1:]
    if not args or args[0] not in ("check", "update"):
        sys.exit(__doc__)
    min_age = 3
    if "--min-age" in args:
        min_age = int(args[args.index("--min-age") + 1])
    text = DOCKERFILE.read_text()
    summary, majors = [], []
    for arg, pinned, same, major in plan(text, min_age):
        name = PINS[arg][1]
        if same:
            summary.append(f"{name} {fmt(pinned)} -> {fmt(same)}")
            text = re.sub(rf"^ARG {arg}=\S+$", f"ARG {arg}={fmt(same)}", text, flags=re.M)
        if major:
            majors.append(f"{name} {fmt(pinned)} -> {fmt(major)}")
        print(f"{name:40} {fmt(pinned):9} -> {fmt(same) if same else 'current':9}"
              + (f"  (major {fmt(major)} available)" if major else ""))
    if args[0] == "update" and summary:
        DOCKERFILE.write_text(text)
    out = os.environ.get("GITHUB_OUTPUT")
    if args[0] == "update" and out:
        with open(out, "a") as f:
            f.write(f"changed={'true' if summary else 'false'}\n")
            for key, lines in (("summary", summary), ("majors", majors)):
                f.write(f"{key}<<EOF\n" + "".join(line + "\n" for line in lines) + "EOF\n")


if __name__ == "__main__":
    main()

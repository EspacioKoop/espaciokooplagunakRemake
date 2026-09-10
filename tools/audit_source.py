"""Inventory every tracked file of a supplied reference checkout without copying its content."""
from pathlib import Path
import collections
import hashlib
import json
import subprocess
import sys

source = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2])
files = subprocess.check_output(["git", "ls-files", "-z"], cwd=source).decode().split("\0")
head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source).decode().strip()
entries = []
groups = collections.defaultdict(lambda: {"files": 0, "bytes": 0, "text_lines": 0})
for name in sorted(filter(None, files)):
    path = source / name
    if not path.is_file(): continue
    data = path.read_bytes()
    try:
        text = data.decode("utf-8")
        lines = len(text.splitlines()) if "\0" not in text else None
    except UnicodeDecodeError: lines = None
    entries.append({"path": name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(), "text_lines": lines})
    group = groups[name.split("/")[0] if "/" in name else "(root)"]
    group["files"] += 1
    group["bytes"] += len(data)
    group["text_lines"] += lines or 0
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps({"reference_commit": head, "tracked_files_read": len(entries), "groups": dict(groups), "files": entries}, indent=2) + "\n")
print(json.dumps({"commit": head, "files": len(entries), "groups": dict(groups)}, indent=2))

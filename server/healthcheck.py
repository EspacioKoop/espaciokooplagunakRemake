#!/usr/bin/env python3
"""Internal liveness: recent main-loop heartbeat from the live native ENet host."""
from pathlib import Path
import json
import os
import sys
import time

def healthy(runtime=None):
    try:
        path = Path(runtime or os.environ.get("LAGUNAK_RUNTIME_DIR", "/tmp/lagunak-runtime")) / "health.json"
        if not 0 <= time.time() - path.stat().st_mtime < 6:
            return False
        value = json.loads(path.read_text())
        if value != {"version": 1, "host": True, "pid": value.get("pid")} or type(value["pid"]) is not int or value["pid"] <= 0:
            return False
        os.kill(value["pid"], 0)
        return True
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        return False

if __name__ == "__main__":
    sys.exit(0 if healthy() else 1)

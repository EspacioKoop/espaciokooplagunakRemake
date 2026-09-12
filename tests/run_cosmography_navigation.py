#!/usr/bin/env python3
"""Navigation entry point; shares isolation and strict result validation."""
import importlib.util
from pathlib import Path

# Resolve the sibling explicitly: also works with python3 -P and from any cwd.
spec = importlib.util.spec_from_file_location(
    "cosmography_contract_runner", Path(__file__).with_name("run_cosmography_persistence.py"))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

if __name__ == "__main__":
    raise SystemExit(runner.main("navigation"))

import json, subprocess, sys
from pathlib import Path
ROOT=Path(__file__).parents[1]; TOOL=ROOT/"tools/issue32_benchmark.py"
def run(*args): return subprocess.run([sys.executable,str(TOOL),*args],cwd=ROOT,text=True,capture_output=True,check=False)
def test_all_profiles_are_deterministic_and_emit_schema(tmp_path):
    out=tmp_path/"report.json"; result=run("--profile","all","--rounds","1","--json",str(out))
    assert result.returncode==0, result.stderr
    data=json.loads(out.read_text()); assert data["schema"]==1 and data["pass"] is True
    assert {p["profile"] for p in data["profiles"]}=={"low","recommended"}
    assert all(p["metrics"]["deterministic"] for p in data["profiles"])
    assert all(p["limits"]["enforced"] is False for p in data["profiles"])
def test_invalid_rounds_are_rejected():
    result=run("--rounds","0"); assert result.returncode!=0
    assert "--rounds must be between 1 and 20" in result.stderr

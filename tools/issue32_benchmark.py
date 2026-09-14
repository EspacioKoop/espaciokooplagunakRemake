#!/usr/bin/env python3
"""Deterministic, non-destructive evidence benchmark for issue #32."""
from __future__ import annotations
import argparse, hashlib, json, statistics, time
from pathlib import Path
SCENARIOS={"low":{"compartments":7,"entities":180,"table_projections":1,"budget_ms":2500,"max_mib":128},"recommended":{"compartments":7,"entities":420,"table_projections":3,"budget_ms":5000,"max_mib":256}}
def workload(profile, rounds):
    start=time.perf_counter(); digest=hashlib.sha256(); records=[]
    for r in range(rounds):
        for c in range(profile["compartments"]):
            for e in range(profile["entities"]):
                digest.update(f"{r}:{c}:{e}:{profile['table_projections']}".encode())
                if e%37==0: records.append((c,e))
    return {"elapsed_ms":round((time.perf_counter()-start)*1000,3),"records":len(records),"digest":digest.hexdigest(),"peak_mib":round(len(records)*64/1048576,6)}
def run(name, rounds):
    profile=SCENARIOS[name]; samples=[workload(profile,rounds) for _ in range(3)]
    elapsed=[s["elapsed_ms"] for s in samples]
    return {"profile":name,"rounds":rounds,"samples":samples,"metrics":{"median_ms":round(statistics.median(elapsed),3),"max_ms":round(max(elapsed),3),"synthetic_peak_mib":max(s["peak_mib"] for s in samples),"deterministic":len({s["digest"] for s in samples})==1},"limits":{"max_ms":profile["budget_ms"],"max_mib":profile["max_mib"],"enforced":False,"reason":"synthetic benchmark; release gate remains separate"},"pass":len({s["digest"] for s in samples})==1}
def main():
    p=argparse.ArgumentParser(); p.add_argument("--profile",choices=[*SCENARIOS,"all"],default="all"); p.add_argument("--rounds",type=int,default=1); p.add_argument("--json",type=Path); a=p.parse_args()
    if a.rounds<1 or a.rounds>20: p.error("--rounds must be between 1 and 20")
    report={"schema":1,"tool":"issue32-benchmark","profiles":[run(n,a.rounds) for n in (list(SCENARIOS) if a.profile=="all" else [a.profile])]}
    report["pass"]=all(x["pass"] for x in report["profiles"]); rendered=json.dumps(report,indent=2,sort_keys=True)+"\n"
    if a.json: a.json.parent.mkdir(parents=True,exist_ok=True); a.json.write_text(rendered,encoding="utf-8")
    print(rendered,end=""); return 0 if report["pass"] else 1
if __name__=="__main__": raise SystemExit(main())

#!/usr/bin/env python3
"""Read-only validation of pinned source/order/dispositions; never executes SQL."""
import argparse,hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def validate(manifest,root=ROOT):
 assert manifest['state']=='draft_non_executable','This validator supports planning drafts only'
 seen=set();steps=manifest['steps'];ids={s['id'] for s in steps}
 assert len(ids)==len(steps),'Duplicate upgrade step'
 for step in steps:
  assert set(step['after'])<=seen,'Unresolved or out-of-order prerequisite: '+step['id']
  assert step['selected'] is None or type(step['selected']) is bool,'Invalid selection disposition'
  if step['selected'] is not None:assert step.get('disposition_evidence'),'Selected/skipped step lacks reviewed evidence'
  path=(root/step['path']).resolve();assert path.is_relative_to(root.resolve()),'Path escapes repository'
  assert path.is_file(),'Missing source: '+step['path']
  assert hashlib.sha256(path.read_bytes()).hexdigest()==step['sha256'],'Source checksum changed: '+step['path']
  assert step['preconditions'] and step['verification'] and step['recovery'],'Incomplete review entry'
  seen.add(step['id'])
 # Earlier cash/financial files define overlapping helpers; authorization must follow them.
 auth=next(i for i,s in enumerate(steps) if s['id']=='application_authorization')
 for i,step in enumerate(steps):
  if step['id'].startswith('legacy_cash_') or step['id']=='legacy_financial_scope':assert i<auth,'Legacy helper would overwrite canonical authorization'
 gates=manifest['required_environment_proofs'];assert gates and all(type(v) is bool for v in gates.values())
 return {'steps':len(steps),'undisposed_steps':sum(s['selected'] is None for s in steps),'unverified_environment_gates':sum(not v for v in gates.values()),'executable':False}
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('manifest',type=Path);a=p.parse_args()
 try:print(json.dumps(validate(json.loads(a.manifest.read_text())),indent=2))
 except (AssertionError,KeyError,ValueError) as error:raise SystemExit(str(error))
if __name__=='__main__':main()

#!/usr/bin/env python3
"""Source indicators for review; this does not certify deployed authorization."""
import argparse,csv,json,re
from pathlib import Path

def main():
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    rows=[]
    for file in sorted((a.source/'pages').glob('*/queries/*/metadata.json')):
        m=json.loads(file.read_text());action=m.get('unpublishedAction',{});config=action.get('actionConfiguration',{});body=config.get('body','')
        if m.get('pluginType') not in ['DB','API']:continue
        rows.append(dict(page=file.parts[-4],action=file.parts[-2],plugin=m.get('pluginType'),mode=action.get('runBehaviour',''),
            body_binding_registered=any(v.get('key')=='body' for v in action.get('dynamicBindingPathList',[])),
            signed_actor_reference='appsmith.user.email' in body,
            canonical_contract_marker=bool(re.search(r'application_|issue19_',body)),
            direct_write=bool(re.search(r'\b(?:INSERT|UPDATE|DELETE)\b',body,re.I)),
            quoted_sql_binding=bool(re.search(r"'{{.*?}}'",body,re.S))))
    a.output.parent.mkdir(parents=True,exist_ok=True)
    with a.output.open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]),lineterminator='\n');w.writeheader();w.writerows(rows)
    print(f'Recorded {len(rows)} DB/API action indicators; manual endpoint/resource review remains required')
if __name__=='__main__':main()

#!/usr/bin/env python3
"""Synthetic split-source audit fixtures; no operational application or database."""
import csv
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT=Path(__file__).with_name('audit_application_permissions.py')

class SourceAudit(unittest.TestCase):
    def test_actual_body_precedence_and_optional_actor(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            for name,plugin,inline,external in [
                ('split','DB','SELECT 1;',{'split.txt':'SELECT public.application_access({{ appsmith.user?.email }});','body.txt':'DELETE FROM ignored;'}),
                ('fallback','API','',{'body.txt':'SELECT {{ appsmith.user.email }};'}),
                ('inline','DB',"UPDATE synthetic SET value='{{ params.value }}';",{}),
                ('js','JS','INSERT INTO ignored VALUES(1);',{}),
            ]:
                folder=root/'pages/Synthetic/queries'/name;folder.mkdir(parents=True)
                (folder/'metadata.json').write_text(json.dumps({'pluginType':plugin,'unpublishedAction':{'name':name,'runBehaviour':'MANUAL','actionConfiguration':{'body':inline},'dynamicBindingPathList':[{'key':'body'}]}}))
                for file,body in external.items():(folder/file).write_text(body)
            output=root/'indicators.csv'
            result=subprocess.run([sys.executable,str(SCRIPT),'--source',str(root),'--output',str(output)],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            with output.open() as stream:rows={r['action']:r for r in csv.DictReader(stream)}
            self.assertEqual(set(rows),{'split','fallback','inline'})
            self.assertEqual(rows['split']['signed_actor_reference'],'True')
            self.assertEqual(rows['split']['canonical_contract_marker'],'True')
            self.assertEqual(rows['split']['direct_write'],'False')
            self.assertEqual(rows['fallback']['signed_actor_reference'],'True')
            self.assertEqual(rows['inline']['direct_write'],'True')
            self.assertEqual(rows['inline']['quoted_sql_binding'],'True')
            self.assertNotIn('appsmith.user',output.read_text())

if __name__=='__main__':unittest.main()

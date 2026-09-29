#!/usr/bin/env python3
"""Install exact-version ACGUS hooks into the user's own game files."""
from pathlib import Path
import argparse,hashlib,json,shutil
p=argparse.ArgumentParser();p.add_argument('game',type=Path);p.add_argument('--restore',action='store_true');a=p.parse_args()
manifests=[json.loads(Path(__file__).with_name(name).read_text()) for name in ('targets.json','targets10.json')]
def matches(rows):
 return all((a.game/r['name']).exists() and hashlib.sha256((a.game/r['name']).read_bytes()).hexdigest() in (r['sha256'],r['patched_sha256']) for r in rows)
found=[rows for rows in manifests if matches(rows)]
if len(found)!=1:raise SystemExit('Unsupported or mixed game version; no files changed.')
rows=found[0]
# Validate the entire batch before writing anything.
for r in rows:
 f=a.game/r['name'];b=f.read_bytes();h=hashlib.sha256(b).hexdigest()
 if h not in (r['sha256'],r['patched_sha256']):raise SystemExit(f'Unsupported or modified file: {f.name}')
 bak=f.with_suffix('.ACB')
 if bak.exists() and hashlib.sha256(bak.read_bytes()).hexdigest()!=r['sha256']:raise SystemExit(f'Unexpected backup: {bak.name}')
 if a.restore and not bak.exists():raise SystemExit(f'Missing backup: {bak.name}')
 if h==r['patched_sha256'] and not bak.exists():raise SystemExit(f'Missing original backup: {bak.name}')
for r in rows:
 f=a.game/r['name'];bak=f.with_suffix('.ACB')
 if a.restore:shutil.copyfile(bak,f);continue
 if not bak.exists():shutil.copyfile(f,bak)
 b=bytearray(bak.read_bytes())
 for q in r['patches']:
  data=bytes.fromhex(q['hex']);b[q['offset']:q['offset']+len(data)]=data
 assert hashlib.sha256(b).hexdigest()==r['patched_sha256']
 f.write_bytes(b)
if not a.restore:shutil.copyfile(Path(__file__).parent/'dist/ACGUS.COM',a.game/'ACGUS.COM')
print('Restored originals.' if a.restore else 'Installed ACGUS. Start with ACGUS.COM.')

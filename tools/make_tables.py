#!/usr/bin/env python3
"""Build one DOS installer table for both independently verified game builds."""
from pathlib import Path
import json

root = Path(__file__).resolve().parents[1]
archive = json.loads((root / 'targets.json').read_text())
iso = json.loads((root / 'targets10.json').read_text())
assert len(archive) == len(iso)
assert all((a['name'], a['patches']) == (b['name'], b['patches']) for a, b in zip(archive, iso))
rows = ['TARGET_COUNT equ '+str(len(archive)), 'TARGET_SIZE equ 16']
for label, targets in (('targets12', archive), ('targets10', iso)):
    rows.append(label+':')
    for i, item in enumerate(targets):
        rows += [f'dw name{i},backup{i}',
                 f'dd {item["crc32"]},{item["patched_crc32"]}',
                 f'dw patch{i},{len(item["patches"])}']
for i, item in enumerate(archive):
    rows += [f'name{i} db "{item["name"]}",0',
             f'backup{i} db "{Path(item["name"]).with_suffix(".ACB")}",0',
             f'patch{i}:']
    for patch in item['patches']:
        blob = bytes.fromhex(patch['hex'])
        rows += [f'dd {patch["offset"]}', f'dw {len(blob)}',
                 'db '+','.join(str(byte) for byte in blob)]
rows.append('crc_table:')
for i in range(256):
    n = i
    for _ in range(8):
        n = (n >> 1) ^ (0xedb88320 if n & 1 else 0)
    rows.append(f'dd {n}')
(root / 'src/install_tables.inc').write_text('\n'.join(rows)+'\n')

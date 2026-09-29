#!/usr/bin/env python3
"""Summarize ACGUS /D's 4 KiB event ring after the game exits."""
import argparse
from pathlib import Path
import struct

p = argparse.ArgumentParser()
p.add_argument('log', type=Path)
a = p.parse_args()
b = a.log.read_bytes()
if len(b) != 4102 or b[:4] not in (b'AGD1', b'AGD2', b'AGD3', b'AGD4', b'AGD5'):
    raise SystemExit('Not an ACGUS /D log')
count = struct.unpack_from('<H', b, 4)[0]
first = max(0, count - 256)
names = {0:'init', 1:'song', 2:'sfx', 3:'shutdown', 4:'pause', 5:'resume', 128:'timer'}
for index in range(first, count):
    off = 6 + (index % 256)*16
    tick, op = struct.unpack_from('<HB', b, off)
    if op in (0x81, 0x82):
        control = b[off+3:off+7]
        volumes = struct.unpack_from('<4H', b, off+7)
        voice_label = 'voice' if b[:4] == b'AGD5' else 'next_sfx'
        print(f'{index:4} tick={tick:5} {"before" if op == 0x81 else "after ":8} '
              f'GF1 music control={control.hex(" ")} '
              f'volume={" ".join(f"{v:04X}" for v in volumes)} '
              f'{voice_label}={b[off+15]+4}')
        continue
    if op == 0x83:
        segment, length, addr_low, addr_high, expected, actual, next_low, mismatches = struct.unpack_from(
            '<HHHHBBHB', b, off+3)
        checks = f' spots_mismatched={mismatches}/16' if b[:4] in (b'AGD2', b'AGD3', b'AGD4', b'AGD5') else ''
        print(f'{index:4} tick={tick:5} upload   '
              f'segment={segment:04X} length={length} GF1={addr_high:04X}:{addr_low:04X} '
              f'first={expected:02X}/{actual:02X} next_low={next_low:04X}{checks}')
        continue
    if op == 0x84:
        controls = b[off+3:off+13]
        music = b[off+13]
        effects = struct.unpack_from('<H', b, off+14)[0]
        print(f'{index:4} tick={tick:5} GF1 SFX  '
              f'controls={controls.hex(" ")} music={music} effects={effects}')
        continue
    if op == 0x86:
        music_end, effect_base, segment, song_length, error = struct.unpack_from(
            '<IIHBB', b, off+3)
        print(f'{index:4} tick={tick:5} GF1 map  '
              f'music_end={music_end:05X} sfx_base={effect_base:05X} '
              f'module={segment:04X} orders={song_length} error={error}')
        continue
    if op == 0x87:
        freq = struct.unpack_from('<4H', b, off+3)
        position = struct.unpack_from('<2H', b, off+11)
        print(f'{index:4} tick={tick:5} music HW '
              f'freq={" ".join(f"{v:04X}" for v in freq)} '
              f'position_hi={position[0]:04X} {position[1]:04X} active={b[off+15]}')
        continue
    tick, op, active, timer, order, row, songs, effects, segment, voice, one_shot = struct.unpack_from(
        '<HBBBBHHHHBB', b, off)
    voice_label = 'voice' if b[:4] == b'AGD5' else 'next_voice'
    print(f'{index:4} tick={tick:5} {names.get(op, str(op)):8} '
          f'music={active} timer={timer} order={order:3} row={row:2} '
          f'songs={songs:2} sfx={effects:3} sfx_seg={segment:04X} '
          f'{voice_label}={voice+4:2} one_shot={one_shot}')

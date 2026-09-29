# Alien Carnage GUS (ACGUS)

Native Gravis UltraSound GF1 music and sound effects for the DOS game *Alien Carnage* (*Halloween Harry*). The patch uses the game's own decoded audio data, uploads samples into GUS DRAM, and mixes four music voices and four game effect channels in GF1 hardware. A 50 Hz GUS timer drives the music tracker. It does not use Sound Blaster DMA or software mixing for the patched audio.

The patch supports two verified DOS builds, identified here as **1.0** and **1.2**. Their on-screen version labels are not a reliable way to distinguish them. The installer checks all 13 audio modules against the supported builds and rejects unknown, modified, or mixed sets without patching them.

The user tested this release on a 386DX-40 with a GUS MAX, including mission 3. Other GF1 cards and game distributions have not been physically verified.

## Requirements

- DOS and a 386 or later.
- A GF1-compatible Gravis UltraSound with at least 512 KiB of DRAM.
- The `ULTRASND` environment variable set for the card, for example `SET ULTRASND=240,7,7,7,7`. The five values are base address, two DMA channels, audio IRQ, and MIDI IRQ. The patch uses the GF1 directly; no UltraSound driver or patch set is required.
- Your own unpacked, supported DOS game installation. **No game files or game assets are included.**

## Install on DOS

1. Back up the entire game directory.
2. Copy `INSTALL.COM` from the release archive to the directory containing `CARNAGE.EXE` and the `HARRY*.-0` files.
3. Run `INSTALL`. It validates all 13 modules, saves their originals as `.ACB`, patches them, and writes `ACGUS.COM` into the game directory.
4. Run `ACGUS` to launch the game. Enable music and effects in the game's own sound settings if they were disabled.

Run `INSTALL /R` to restore the original modules. The installer retains the backups and `ACGUS.COM`. Re-running `INSTALL` on a supported installation with intact backups also updates the launcher. Do not run `CARNAGE.EXE` directly while the audio hooks are installed. The original sound setup may overwrite settings needed by the patch; if you rerun it, rerun `INSTALL` afterward.

`ACGUS /T` checks GF1 memory and timer operation without starting the game. `ACGUS /P-100` through `/P100` changes music stereo width; the default is `+60`. `ACGUS /D` writes `ACGUS.LOG` after the game exits; this is for diagnosis and is unnecessary for normal play.

For a host-side alternative, the source archive includes `install.py`: run `python3 install.py GAME_DIRECTORY`, or add `--restore` to restore the original modules. Its SHA-256 manifests select the supported build automatically. The DOS installer requires no Python.

## How it works

Small hooks in the game's audio modules forward its in-memory music and effect requests to `ACGUS.COM`. The game's own loading and decoding remain in place. The launcher uploads expanded 8-bit samples to GF1 RAM. Music uses four tracker voices; each of the game's four effect channels has its own GF1 voice, with a new sound on that channel replacing the previous sound. The GF1 is configured for 14 active voices and the patch preserves the game's original music patterns and samples. Music samples and the effect cache occupy separate regions of GUS RAM; the effect cache moves above a song's samples if needed.

The installer uses exact file hashes and patch offsets. Additional game versions require independent analysis and target tables. The launcher requires at least 512 KiB of accessible GF1 DRAM; a very large song may leave insufficient space for effect uploads. There is no Sound Blaster fallback while the game is patched. GF1 hardware limits the sample bit depth and interpolation quality.

## Build from source

From `src`, build the launcher **before** the installer, which embeds it:

```sh
nasm -f bin -o ../dist/ACGUS.COM acgus.asm
nasm -f bin -o ../dist/INSTALL.COM install.asm
```

NASM 2.x is required. After changing a target manifest, regenerate the unified installer table from the project root with `python3 tools/make_tables.py`, then rebuild both binaries. `python3 tools/read_log.py ACGUS.LOG` summarizes an optional diagnostic log. The GF1/tracker base was adapted from the MIT-licensed PRE2GUS/BB2GUS project; see `LICENSE-PRE2` for attribution.

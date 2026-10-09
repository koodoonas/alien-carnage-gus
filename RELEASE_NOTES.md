# Alien Carnage GUS 1.1

Stable release of the tested silent-endpoint update.

- One-shot music and sound effects now stop on silent samples, preventing a held nonzero output from reducing mixer headroom and degrading subsequent audio.
- Adds two silent guard bytes per uploaded sample, without per-tick polling or additional software mixing.
- Retains native GF1 hardware mixing and support for the two verified game builds identified as 1.0 and 1.2.

The test build passed installer and GF1 self-tests for both supported builds, plus a synthetic stopped-voice regression test. The user confirmed the update works and could no longer reproduce the reported degradation on their machine.

## Install or upgrade

Back up the game directory. Copy `INSTALL.COM` from `alien-carnage-gus-1.1-dos.zip` into the game directory and run `INSTALL`, then launch with `ACGUS`. On an already patched installation with intact `.ACB` backups, running the new installer updates the launcher; restoring first is unnecessary. `INSTALL /R` restores the original modules.

The card must have at least 512 KiB of accessible GUS RAM and a configured `ULTRASND` environment variable. Enable music and sound effects in the game settings if necessary.

The source archive includes the optional host-side installer: `python3 install.py GAME_DIRECTORY`. Add `--restore` to restore the original modules.

No game files or audio assets are included. See README.md for requirements, options, supported versions, and build instructions.

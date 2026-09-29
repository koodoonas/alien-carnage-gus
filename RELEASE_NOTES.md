# Alien Carnage GUS 1.0

First public release of the native GF1 audio patch for DOS *Alien Carnage* / *Halloween Harry*.

- GF1 hardware playback of the game's music and four sound effect channels.
- Uploads the game's own decoded 8-bit samples to GUS RAM; no game audio assets are distributed.
- Unified DOS installer for the two verified 1.0 and 1.2 executable sets, with exact validation, original-file backups, and `INSTALL /R` restore.
- Reads the card configuration from `ULTRASND`; supports stereo width selection with `ACGUS /P` and a GF1 self-test with `ACGUS /T`.
- Tested by the patch user on a 386DX-40 with GUS MAX through mission 3. Other hardware and game builds are unverified.

Download `alien-carnage-gus-1.0-dos.zip` for DOS installation. The source archive includes NASM code, target manifests, and the optional Python installer. Keep a backup of your game directory.

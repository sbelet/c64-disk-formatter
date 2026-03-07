# C64 Disk Formatter with Verification

A fast disk formatter and verifier for the Commodore 64 + 1541 disk drive family.

## Features

- **Fast format engine** — formats tracks using the proven GCR encoding method
- **35 or 40 track support** — toggle with F1
- **Three modes:** FMT+VER, FORMAT only, VERIFY only (cycle with F5)
- **Fast interleaved verify** — drive-side +11 sector interleave with bitmap, ~3-4× faster than sequential reads
- **Per-track error display** — X-Copy style hex error count grid with color coding (green=OK, red=errors)
- **Retry/Continue/Abort** — on verify errors in FMT+VER mode, choose to reformat the track, continue, or abort
- **Tracks 36-40 verify** — patches drive ZP $22 to bypass ROM seek hang, manual head stepping in verify-only mode
- **SID sound effects** — tick per track, error buzz, completion/abort tones
- **F7 directory listing** — view disk contents via TALK/ACPTR without leaving the program
- **PETSCII input** — full shifted character support for disk name and ID
- **Multi-device support** — F3 cycles through devices 8-11
- **STOP key abort** — hold STOP between tracks to cancel

## Screenshots

*(Add your VICE screenshots here)*

## Building

Requires [KickAssembler](http://theweb.dk/KickAssembler/):

```
java -jar KickAss.jar formatter_step14.asm -o formatter.prg
```

Load and run on a C64 (or VICE emulator):

```
LOAD "FORMATTER",8
RUN
```

## Drive Compatibility

Tested on real hardware:
- 1541
- 1541C
- 1541-II
- 1571 (in 1541 mode)

## Technical Details

### Drive Memory Map

| Address       | Contents                                      |
|---------------|-----------------------------------------------|
| $0300-$031E   | Launcher (31 bytes) — M-E $0300 for format    |
| $0320-$037C   | Fast verify — interleaved +11 read, M-E $0320 |
| $0400-$054D   | Fast Format engine (334 bytes)                |
| $0443-$044D   | Write routine — M-E $0443 for BAM/DIR         |
| $01BB-$01FF   | GCR block 1 (69 bytes)                        |
| $0700-$07FF   | GCR block 2 (256 bytes)                       |

### Verify Interleave

The verify routine uses interleave +11, which is coprime with all 1541 sector counts (21, 19, 18, 17). This visits every sector in a single Hamiltonian cycle — ~3-4 disk revolutions per track regardless of zone. The common interleave +7 degenerates on 21-sector tracks (GCD(7,21)=7) requiring 7 rounds.

Completion is detected via a busy flag at $06FE: C64 sets it to $FF before M-E, drive clears to $00 when done. The C64 polls via M-R with visual flash feedback.

### Key Bug Fixes (V1.1+)

- **Verify-only mode disk ID:** Send "I" command before upload to populate ZP $16/$17 from BAM
- **Color RAM 4-bit reads:** AND #$0F mask when reading back color values (upper nybble is garbage)
- **Track 36+ seek hang:** Patch drive ZP $22 via M-W to make ROM seek a no-op
- **BAM cache corruption:** GCR block 2 upload overwrites $0700 (BAM cache) — "I" command in fdFinish refreshes it

## Version History

- **V1.3** — Interleave +11 (coprime with all sector counts), busy-flag polling, ~3-4× faster verify on all tracks
- **V1.2** — Interleaved verify at $0320, SID sounds, adaptive timing
- **V1.1** — BAM cache fix after verify, F7 directory shows correct disk name
- **V1.0** — Initial release: format, verify, 40-track support, R/C/A prompt

## Author

(C) 2026 Sayit Belet - PikoTV Yazilim A.S.

## License

*(Add your preferred license here)*

// ============================================================
// DISK FORMATTER WITH VERIFICATION - (C) 2026 Sayit BELET
// Per-track format via launcher + Format&Verify Engine
// Target: C64 + 1541 | Assembler: KickAssembler
// ============================================================
//
// Drive memory map:
//   $0300-$031E  Launcher (31 bytes) - M-E $0300 for format
//   $0320-$037C  Fast verify - interleaved +11 read, M-E $0320
//                Patch: $06FF=sector count, $06FE=busy flag
//                Bitmap: $06E0-$06F4
//   $0400-$054D  Format engine (334 bytes) with embedded:
//   $0438-$0442  Read routine (unused now)
//   $0443-$044D  Write routine - M-E $0443 for BAM/DIR
//   $044E-$0477  Verify routine (old sequential, unused)
//   $01BB-$01FF  GCR block 1 (69 bytes)
//   $0700-$07FF  GCR block 2 (256 bytes)
//
// Per-track: patch $030D=track, $0311=track+1, M-E $0300
// ============================================================

.pc = $0801 "BASIC Upstart"
:BasicUpstart2(main)
.pc = $0810 "Code"

.const SCREEN=$0400
.const COLRAM=$D800
.const BORDER=$D020
.const BGCOL0=$D021
.const JIFFYL=$A2
.const CMDFILE=15
.const MW_MAX=34

.const BLACK=0
.const WHITE=1
.const RED=2
.const CYAN=3
.const GREEN=5
.const YELLOW=7
.const LRED=10
.const DGRAY=11
.const LGREEN=13
.const LBLUE=14
.const LGRAY=15

.const ROW_TITLE=1
.const ROW_COPY=2
.const ROW_TRKNUM=3
.const ROW_TRKLBL=5
.const ROW_TENS=6
.const ROW_ONES=7
.const ROW_FORMAT=8
.const ROW_VERIFY=9
.const ROW_NAME=12
.const ROW_ID=13
.const ROW_DEVICE=14
.const ROW_VFLAG=15
.const ROW_LEGEND=17
.const ROW_KEYS=19
.const ROW_START=21
.const ROW_STATUS=24
.const NAME_COL=12
.const ID_COL=12
.const DEV_COL=12
.const VF_COL=12

.const SC_DOT=$2E
.const SC_STAR=$2A
.const SC_SPACE=$20
.const SC_DASH=$2D

// SID registers (voice 1)
.const SID_V1FL=$D400
.const SID_V1FH=$D401
.const SID_V1PL=$D402
.const SID_V1PH=$D403
.const SID_V1CR=$D404
.const SID_V1AD=$D405
.const SID_V1SR=$D406
.const SID_VOL=$D418

.const zpSrc=$FB
.const zpDstLo=$FD
.const zpDstHi=$FE
.const zpInp=$02
.const zpDst=$FD

main:
        sei
        lda #BLACK
        sta BORDER
        sta BGCOL0
        lda #WHITE
        sta $0286           // cursor/text color
        lda #40
        sta trackMode
        lda #8
        sta deviceNum
        lda #0
        sta opMode          // 0=FMT+VER, 1=FORMAT, 2=VERIFY
        lda #$44
        sta nameBuf
        lda #$49
        sta nameBuf+1
        lda #$53
        sta nameBuf+2
        lda #$4B
        sta nameBuf+3
        lda #4
        sta nameLen
        lda #$30
        sta idBuf
        lda #$31
        sta idBuf+1
        lda #2
        sta idLen
        jsr sidInit
        cli

initScreen:
        sei
        jsr clearAllScreen
        jsr drawAllText
        jsr colorFKeys
        jsr drawTrackGrid
        jsr updateTrackDisplay
        jsr showNameOnScreen
        jsr showIdOnScreen
        jsr showDeviceNum
        jsr showModeFlag
        cli

inputLoop:
        jsr GETIN
        beq inputLoop
        cmp #$85
        beq ilToggle
        cmp #$86
        beq ilDevice
        cmp #$87
        beq ilVerify
        cmp #$88            // F7
        beq ilDir
        cmp #$0D
        beq ilReturn
        jmp inputLoop
ilToggle:
        lda trackMode
        cmp #40
        beq ilSet35
        lda #40
        sta trackMode
        jmp ilUpd
ilSet35:
        lda #35
        sta trackMode
ilUpd:
        jsr updateTrackDisplay
        jmp inputLoop
ilDevice:
        inc deviceNum
        lda deviceNum
        cmp #12
        bne ilDevOk
        lda #8
        sta deviceNum
ilDevOk:
        jsr showDeviceNum
        jmp inputLoop
ilVerify:
        lda opMode
        clc
        adc #1
        cmp #3
        bcc ilModeOk
        lda #0
ilModeOk:
        sta opMode
        jsr showModeFlag
        jmp inputLoop
ilDir:
        jsr listDirectory
        jmp initScreen
ilReturn:
        jsr editFlow
        jmp initScreen

editFlow:
        // In verify-only mode, skip name/ID editing
        lda opMode
        cmp #2
        beq efConfirm

        // ---- Edit Disk Name ----
        jsr clearStatusRow
        jsr printStatus
        .word txtEditName
        lda #<nameBuf
        sta inputBuf
        lda #>nameBuf
        sta inputBuf+1
        lda nameLen
        sta inputLen
        lda #16
        sta inputMax
        lda #<SCREEN+(ROW_NAME*40)+NAME_COL
        sta zpInp
        lda #>SCREEN+(ROW_NAME*40)+NAME_COL
        sta zpInp+1
        jsr showInputBuf
        jsr doInput
        lda inputLen
        sta nameLen
        jsr showNameOnScreen

        // ---- Edit Disk ID ----
        jsr clearStatusRow
        jsr printStatus
        .word txtEditId
        lda #<idBuf
        sta inputBuf
        lda #>idBuf
        sta inputBuf+1
        lda idLen
        sta inputLen
        lda #2
        sta inputMax
        lda #<SCREEN+(ROW_ID*40)+ID_COL
        sta zpInp
        lda #>SCREEN+(ROW_ID*40)+ID_COL
        sta zpInp+1
        jsr showInputBuf
        jsr doInput
        lda inputLen
        sta idLen
        jsr showIdOnScreen

        // ---- Confirm (mode-aware) ----
efConfirm:
        jsr clearStatusRow
        lda opMode
        cmp #2
        bne efCfmFmt
        jsr printStatus
        .word txtConfVer
        jmp efConf
efCfmFmt:
        jsr printStatus
        .word txtConfFmt
efConf:
        jsr GETIN
        beq efConf
        cmp #$59
        beq efGo
        cmp #$4E
        beq efCancel
        jmp efConf
efCancel:
        jsr clearStatusRow
        rts
efGo:
        jsr drawTrackGrid
        jsr updateTrackDisplay
        jsr clearStatusRow
        jsr formatDisk

        // Skip post-actions if aborted (curTrack < trackMode)
        lda curTrack
        cmp trackMode
        bcc efDone

        // Auto-list directory for format modes
        lda opMode
        cmp #2
        beq efComplete
        jsr listDirectory   // shows dir, waits RETURN
        rts

efComplete:
        // Verify-only: show completion message
        jsr clearStatusRow
        jsr printStatus
        .word txtComplRet
        jsr waitReturn
efDone:
        rts

// ============================================================
// FORMAT DISK - PER-TRACK VIA LAUNCHER
// ============================================================
formatDisk:
        jsr openCmdChannel
        bcc fdOpen
        jsr printStatus
        .word txtDrvErr
        rts
fdOpen:
        // Verify-only: initialize drive so DOS reads BAM and sets
        // disk ID into ZP $16/$17 - READ jobs compare sector header
        // IDs against these bytes, uninitialized = every sector fails
        lda opMode
        cmp #2
        bne fdSkipInit
        jsr clearStatusRow
        jsr printStatus
        .word txtInitDrive
        ldx #CMDFILE
        jsr CHKOUT
        lda #'I'
        jsr CHROUT
        jsr CLRCHN
        lda #100
        jsr waitJiffies
        jsr drainErrorChannel
fdSkipInit:
        jsr clearStatusRow
        jsr printStatus
        .word txtUploading
        jsr uploadAll
        jsr patchLauncherID
        jsr clearStatusRow
        lda opMode
        cmp #2
        bne fdShowFmt
        jsr printStatus
        .word txtVerifying
        jmp fdStartLoop
fdShowFmt:
        jsr printStatus
        .word txtFormatting
fdStartLoop:
        jsr showStopHint
        lda #0
        sta curTrack
fdLoop:
        lda curTrack
        cmp trackMode
        bcc fdNotDone
        jmp fdAllDone
fdNotDone:
        // Highlight current track column - RED flash
        ldx curTrack
        lda #RED
        sta COLRAM + ROW_TENS*40,x
        sta COLRAM + ROW_ONES*40,x
        // 1-based track
        lda curTrack
        clc
        adc #1
        sta curTrack1

        // ======== FORMAT PHASE ========
        lda opMode
        cmp #2
        bne fdDoFmt         // not mode 2 -> format
        jmp fdSkipFmt       // mode 2 (VERIFY only) -> skip
fdDoFmt:

        // Show FORMATTING... status
        jsr clearStatusRow
        jsr printStatus
        .word txtFormatting

        // Border = LBLUE during format
        lda #LBLUE
        sta BORDER

        // Show activity in format row (reverse space, stays LBLUE)
        ldx curTrack
        lda #SC_SPACE | $80
        sta SCREEN + ROW_FORMAT*40,x

        // Repair engine tail if prior verify damaged $0500+
        lda curTrack
        beq fdSkipRepair
        lda opMode
        bne fdSkipRepair    // only mode 0 does verify+format
        jsr repairEngineTail
fdSkipRepair:
        // Patch launcher: start track -> $030D
        ldx #CMDFILE
        jsr CHKOUT
        lda #'M'
        jsr CHROUT
        lda #'-'
        jsr CHROUT
        lda #'W'
        jsr CHROUT
        lda #$0D
        jsr CHROUT
        lda #$03
        jsr CHROUT
        lda #1
        jsr CHROUT
        lda curTrack1
        jsr CHROUT
        jsr CLRCHN
        // Patch launcher: end track -> $0311
        ldx #CMDFILE
        jsr CHKOUT
        lda #'M'
        jsr CHROUT
        lda #'-'
        jsr CHROUT
        lda #'W'
        jsr CHROUT
        lda #$11
        jsr CHROUT
        lda #$03
        jsr CHROUT
        lda #1
        jsr CHROUT
        lda curTrack1
        clc
        adc #1
        jsr CHROUT
        jsr CLRCHN
        // M-E $0300 - format one track
        jsr sendME_0300
        // Wait
        lda curTrack
        bne fdShort
        lda #100
        jmp fdWait
fdShort:
        lda #50
fdWait:
        jsr flashWait
        // Mark format OK (reverse space, color stays LBLUE)
        ldx curTrack
        lda #SC_SPACE | $80
        sta SCREEN + ROW_FORMAT*40,x
        jmp fdDoVerify

fdSkipFmt:
        // Mode 2: mark format row as dash (skipped, color stays LBLUE)
        ldx curTrack
        lda #SC_DASH | $80
        sta SCREEN + ROW_FORMAT*40,x

        // ======== VERIFY PHASE ========
fdDoVerify:
        lda opMode
        cmp #1
        beq fdSkipVf        // mode 1 (FORMAT only) -> skip

        // Show VERIFYING... status
        jsr clearStatusRow
        jsr printStatus
        .word txtVerifying

        // Border = YELLOW during verify
        lda #YELLOW
        sta BORDER

        // Show activity in verify row (reverse space, stays YELLOW)
        ldx curTrack
        lda #SC_SPACE | $80
        sta SCREEN + ROW_VERIFY*40,x
        jsr verifyCurrentTrack
        // A = error count (0 = all OK)
        sta vfErrCnt

        // Convert error count to display character
        jsr errToChar       // returns A = screencode
        ldx curTrack
        sta SCREEN + ROW_VERIFY*40,x

        // Color: 0 = LGREEN, else LRED
        lda vfErrCnt
        bne fdVerErr
        lda #LGREEN
        jmp fdVerCol
fdVerErr:
        lda #LRED
fdVerCol:
        ldx curTrack
        sta COLRAM + ROW_VERIFY*40,x

        // R/C/A prompt only in FMT+VER mode (opMode 0)
        lda opMode
        bne fdVerChk2       // modes 1,2: no prompt
        lda vfErrCnt
        beq fdVerOk         // no errors: continue
        jsr sidError
        jsr clearStatusRow
        jsr printStatus
        .word txtRCA
fdRCALoop:
        jsr GETIN
        beq fdRCALoop
        cmp #$52            // 'R' - retry (reformat + reverify)
        beq fdRetry
        cmp #$43            // 'C' - continue
        beq fdVerOk
        cmp #$41            // 'A' - abort
        beq fdAbort
        jmp fdRCALoop
fdRetry:
        // Reformat then reverify this track
        jsr clearStatusRow
        jmp fdDoFmt

fdVerChk2:
        // Modes 1,2: no R/C/A prompt, but beep on error
        lda vfErrCnt
        beq fdVerOk
        jsr sidError

fdVerOk:
        jsr clearStatusRow
        jmp fdNext

fdSkipVf:
        ldx curTrack
        lda #SC_DASH | $80
        sta SCREEN + ROW_VERIFY*40,x
fdNext:
        // Restore border + track number color (green = completed)
        lda #BLACK
        sta BORDER
        ldx curTrack
        lda #GREEN
        sta COLRAM + ROW_TENS*40,x
        sta COLRAM + ROW_ONES*40,x
        jsr sidTick

        // Check STOP key - abort if pressed
        jsr STOP
        beq fdAbort

        inc curTrack
        jmp fdLoop

fdAbort:
        // Re-initialize drive before closing (refresh BAM cache)
        ldx #CMDFILE
        jsr CHKOUT
        lda #'I'
        jsr CHROUT
        jsr CLRCHN
        lda #50
        jsr waitJiffies
        jsr drainErrorChannel
        jsr closeDrive
        jsr sidAbort
        jsr clearStatusRow
        lda opMode
        cmp #2
        beq fdAbortVer
        jsr printStatus
        .word txtAbortRet
        jmp fdAbortWait
fdAbortVer:
        jsr printStatus
        .word txtAbortVRet
fdAbortWait:
        jsr waitReturn
        rts

fdAllDone:
        // Skip filesystem write in verify-only mode
        lda opMode
        cmp #2
        beq fdFinish

        jsr clearStatusRow
        jsr printStatus
        .word txtWritingDir
        jsr writeBAMSector
        jsr writeDIRSector

fdFinish:
        // Re-initialize drive: refreshes BAM cache at $0700
        // (our GCR block 2 upload overwrites it)
        jsr clearStatusRow
        jsr printStatus
        .word txtInitDrive
        ldx #CMDFILE
        jsr CHKOUT
        lda #'I'
        jsr CHROUT
        jsr CLRCHN
        lda #100
        jsr waitJiffies
        jsr drainErrorChannel
        lda #BLACK
        sta BORDER
        jsr sidComplete
        jsr closeDrive
        rts

// ============================================================
// VERIFY CURRENT TRACK - M-E $0320 (fast interleaved)
//
// Drive-side routine at $0320 reads sectors in +11 interleave
// with bitmap at $06E0, completing all sectors in ~3-7
// revolutions instead of ~17-21 (sequential). ~3-4x faster.
//
// Patches before call:
//   $0022  = track (tracks 36+ only - bypasses ROM seek hang)
//   $000A  = track (1-based)
//   $06FE  = $FF (busy flag - cleared by drive when done)
//   $06FF  = sector count
// ============================================================
verifyCurrentTrack:
        // For tracks 36+: the ROM's READ job seek routine hangs.
        // Fix: patch $22 = curTrack1 so the seek is a no-op.
        // In FMT+VER/FORMAT modes, the head is already positioned
        // from the format phase. In VERIFY-only mode, we must
        // step the head ourselves first.
        lda curTrack1
        cmp #36
        bcc vctStandard

        // ---- Track 36+: patch $22 to bypass ROM seek ----
        lda opMode
        cmp #2
        bne vctPatch22      // FMT+VER or FORMAT: head already there
        jsr stepOneTrack    // VERIFY-only: step head forward
vctPatch22:
        ldx #CMDFILE
        jsr CHKOUT
        lda #'M'
        jsr CHROUT
        lda #'-'
        jsr CHROUT
        lda #'W'
        jsr CHROUT
        lda #$22
        jsr CHROUT
        lda #$00
        jsr CHROUT
        lda #1
        jsr CHROUT
        lda curTrack1
        jsr CHROUT
        jsr CLRCHN

vctStandard:
        // Set JOB2 track header: $000A = curTrack1
        ldx #CMDFILE
        jsr CHKOUT
        lda #'M'
        jsr CHROUT
        lda #'-'
        jsr CHROUT
        lda #'W'
        jsr CHROUT
        lda #$0A
        jsr CHROUT
        lda #$00
        jsr CHROUT
        lda #1
        jsr CHROUT
        lda curTrack1
        jsr CHROUT
        jsr CLRCHN

        // Set busy flag ($06FE=$FF) and sector count ($06FF) in one M-W
        ldx #CMDFILE
        jsr CHKOUT
        lda #'M'
        jsr CHROUT
        lda #'-'
        jsr CHROUT
        lda #'W'
        jsr CHROUT
        lda #$FE
        jsr CHROUT
        lda #$06
        jsr CHROUT
        lda #2              // write 2 bytes
        jsr CHROUT
        lda #$FF            // $06FE = busy flag
        jsr CHROUT
        ldx curTrack
        lda sectorsPerTrack,x
        jsr CHROUT          // $06FF = sector count
        jsr CLRCHN

        // M-E $0320 - interleaved read, counts errors
        jsr sendME_0320

        // Poll $06FE with flash until drive clears it to $00.
        // Polls every 8 jiffies (~130ms) to minimize ATN overhead.
        jsr pollVerifyDone

        // Read result from $0002 (error count: 0=all OK)
        jsr readJob2Result
        // A = error count
        rts

// ============================================================
// POLL VERIFY DONE - flash delay + poll $06FE
//
// Phase 1: flashWait for sectors×4 jiffies - no serial traffic.
//          Interleave 11 is coprime with all sector counts, so
//          drive finishes in ~3-4 revolutions (~1-1.2s).
//          21 sectors -> 84j (~1.7s), 17 -> 68j (~1.4s).
// Phase 2: tight poll M-R $06FE until done.
// ============================================================
pollVerifyDone:
        // Phase 1: uninterrupted flash delay
        ldx curTrack
        lda sectorsPerTrack,x
        asl                 // ×2
        asl                 // ×4 (max 21×4=84, fits byte)
        jsr flashWait

        // Phase 2: tight poll - no flash (M-R blocks ~300ms)
pvPoll:
        ldx #CMDFILE
        jsr CHKOUT
        lda #'M'
        jsr CHROUT
        lda #'-'
        jsr CHROUT
        lda #'R'
        jsr CHROUT
        lda #$FE
        jsr CHROUT
        lda #$06
        jsr CHROUT
        lda #$01
        jsr CHROUT
        jsr CLRCHN
        ldx #CMDFILE
        jsr CHKIN
        jsr CHRIN
        pha
        jsr CLRCHN
        pla
        cmp #$FF
        beq pvPoll          // still busy -> poll again

        // Ensure RED at exit (fdNext restores to GREEN)
        ldx curTrack
        lda #RED
        sta COLRAM + ROW_TENS*40,x
        sta COLRAM + ROW_ONES*40,x
        rts

// ============================================================
// STEP HEAD FORWARD ONE TRACK (2 half-track steps)
//
// For verify-only on tracks 36+: the ROM seek hangs, so we
// step the stepper motor directly via M-W to VIA2 $1C00.
// Called sequentially, so head is already on previous track.
// ============================================================
stepOneTrack:
        jsr doHalfStep
        lda #2
        jsr waitJiffies     // ~33ms step delay
        jsr doHalfStep
        lda #3
        jsr waitJiffies     // ~50ms settle
        rts

// ---- Single half-track step forward via serial bus ----
doHalfStep:
        // M-R $1C00: read current VIA2 state
        ldx #CMDFILE
        jsr CHKOUT
        lda #'M'
        jsr CHROUT
        lda #'-'
        jsr CHROUT
        lda #'R'
        jsr CHROUT
        lda #$00
        jsr CHROUT
        lda #$1C
        jsr CHROUT
        lda #$01
        jsr CHROUT
        jsr CLRCHN
        ldx #CMDFILE
        jsr CHKIN
        jsr CHRIN
        sta dhsTmp          // save $1C00
        jsr CLRCHN

        // Compute next stepper phase: (phase+1) AND 3
        lda dhsTmp
        and #$03            // current phase bits
        clc
        adc #1
        and #$03            // new phase
        sta dhsPhase
        lda dhsTmp
        and #$FC            // clear old phase bits
        ora dhsPhase        // merge new phase
        sta dhsTmp

        // M-W $1C00: write new stepper phase
        ldx #CMDFILE
        jsr CHKOUT
        lda #'M'
        jsr CHROUT
        lda #'-'
        jsr CHROUT
        lda #'W'
        jsr CHROUT
        lda #$00
        jsr CHROUT
        lda #$1C
        jsr CHROUT
        lda #1
        jsr CHROUT
        lda dhsTmp
        jsr CHROUT
        jsr CLRCHN
        rts

dhsTmp:   .byte 0
dhsPhase: .byte 0

// ============================================================
// REPAIR ENGINE TAIL - re-upload $0500-$054D (78 bytes)
//
// JOB2 READ writes into buffer 2 ($0500-$05FF), which
// overlaps the format engine's format-write code at $0500-$054D.
// After any verify, those 78 bytes are disk sector data.
// This routine restores them before the next format call.
// ============================================================
repairEngineTail:
        lda #<(engine_data + 256)
        ldx #>(engine_data + 256)
        sta zpSrc
        stx zpSrc+1
        lda #$00
        sta zpDstLo
        lda #$05
        sta zpDstHi
        ldx #78
        ldy #0
        jsr upload_bytes
        rts

// ============================================================
// LIST DIRECTORY
//
// Based on proven ML snippet using direct serial bus I/O.
// TALK/TKSA/ACPTR for reading, $BDCD for block count,
// $E716 (screen editor BSOUT) for output - handles RVS,
// scrolling, cursor, wrap automatically.
// Any key pauses, RUN/STOP aborts.
// ============================================================
listDirectory:
        // Clear screen + white text
        lda #$93            // PETSCII clear screen
        jsr CHROUT
        lda #$05            // PETSCII white
        jsr CHROUT

        // Store "$" at ZP $22 for SETNAM
        lda #$24
        sta $22
        lda #0
        sta $C6             // clear keyboard buffer

        // SETNAM(len=1, addr=$0022)
        lda #1
        ldx #$22
        ldy #$00
        jsr SETNAM

        // SETLFS(LF=1, dev, SA=$60)
        lda #1              // LF=1 (explicit, don't rely on SETNAM preserving A)
        ldx deviceNum
        ldy #$60            // SA $60 = directory
        jsr SETLFS

        // OPEN
        jsr OPEN
        bcs ldDone

        // Direct serial: TALK + secondary address
        lda deviceNum
        jsr $FFB4           // TALK
        lda #$60
        jsr $FF96           // TKSA

        // X=3: first line reads 3 pairs (load addr, next-ptr, block count)
        ldx #3

ldPairLoop:
        jsr $FFA5           // ACPTR - lo byte
        sta $C3
        jsr $FFA5           // ACPTR - hi byte
        sta $C4
        ldy $90             // check status
        bne ldDone
        dex
        bne ldPairLoop      // loop until X=0

        // $C3=block count lo, A=$C4=block count hi
        ldx $C3
        tay                 // Y = hi (for $BDCD)
        jsr $BDCD           // BASIC ROM: print unsigned int A/X

        // Space + character loop
        lda #$20            // space after block count
ldOutChar:
        jsr $E716           // screen editor BSOUT
        ldx $90
        bne ldDone
        jsr $FFA5           // ACPTR - next byte
        bne ldOutChar       // not $00 -> print it

        // End of line: print CR
        lda #$0D
        jsr $E716

        // Check for keypress
        jsr GETIN
        beq ldNextLine      // no key -> continue
        cmp #$03            // RUN/STOP?
        beq ldDone

        // Pause: wait for another keypress to resume
ldPause:
        jsr GETIN
        beq ldPause
        // Fall through: check if resume key was STOP

ldNextLine:
        ldx #2              // X=2: next-ptr + block count
        cmp #$03            // was key STOP?
        bne ldPairLoop      // no -> continue listing

ldDone:
        // Cleanup
        jsr $FFAB           // UNTALK
        lda #1              // logical file 1
        jsr CLOSE
        jsr CLRCHN

        // Prompt (green)
        lda #$0D
        jsr CHROUT
        lda #$99            // PETSCII light green
        jsr CHROUT
        ldx #0
ldPrP:
        lda txtPressKey,x
        beq ldWait
        jsr CHROUT
        inx
        bne ldPrP
ldWait:
        jsr GETIN
        beq ldWait
        rts


// ============================================================
// UPLOAD ALL DRIVE CODE
// ============================================================
uploadAll:
        lda #<engine_data
        ldx #>engine_data
        sta zpSrc
        stx zpSrc+1
        lda #$00
        sta zpDstLo
        lda #$04
        sta zpDstHi
        ldx #<334
        ldy #>334
        jsr upload_bytes
        lda #<gcr_block1
        ldx #>gcr_block1
        sta zpSrc
        stx zpSrc+1
        lda #$BB
        sta zpDstLo
        lda #$01
        sta zpDstHi
        ldx #69
        ldy #0
        jsr upload_bytes
        lda #<gcr_block2
        ldx #>gcr_block2
        sta zpSrc
        stx zpSrc+1
        lda #$00
        sta zpDstLo
        lda #$07
        sta zpDstHi
        ldx #0
        ldy #1
        jsr upload_bytes
        lda #<launcher_data
        ldx #>launcher_data
        sta zpSrc
        stx zpSrc+1
        lda #$00
        sta zpDstLo
        lda #$03
        sta zpDstHi
        ldx #31
        ldy #0
        jsr upload_bytes
        // Upload fast verify routine -> $0320 (93 bytes)
        // Located after launcher in buffer 0 - safe during JOB2 reads.
        // ($0600 is NOT safe: format engine's GCR encode overwrites it)
        lda #<verify_fast_data
        ldx #>verify_fast_data
        sta zpSrc
        stx zpSrc+1
        lda #$20
        sta zpDstLo
        lda #$03
        sta zpDstHi
        ldx #93
        ldy #0
        jsr upload_bytes
        rts

// ============================================================
// PATCH LAUNCHER ID ($0301, $0307)
// ============================================================
patchLauncherID:
        ldx #CMDFILE
        jsr CHKOUT
        lda #'M'
        jsr CHROUT
        lda #'-'
        jsr CHROUT
        lda #'W'
        jsr CHROUT
        lda #$01
        jsr CHROUT
        lda #$03
        jsr CHROUT
        lda #1
        jsr CHROUT
        lda idBuf
        jsr CHROUT
        jsr CLRCHN
        ldx #CMDFILE
        jsr CHKOUT
        lda #'M'
        jsr CHROUT
        lda #'-'
        jsr CHROUT
        lda #'W'
        jsr CHROUT
        lda #$07
        jsr CHROUT
        lda #$03
        jsr CHROUT
        lda #1
        jsr CHROUT
        lda idBuf+1
        jsr CHROUT
        jsr CLRCHN
        rts

// ============================================================
// WRITE BAM SECTOR (T18S0) - uses M-E $0443
// ============================================================
writeBAMSector:
        jsr buildBAM
        lda #<bamBuf
        ldx #>bamBuf
        sta zpSrc
        stx zpSrc+1
        lda #$00
        sta zpDstLo
        lda #$05
        sta zpDstHi
        ldx #0
        ldy #1
        jsr upload_bytes
        lda #18
        sta mwTrkSec
        lda #0
        sta mwTrkSec+1
        jsr sendMW_TrkSec
        jsr sendME_0443
        lda #150
        jsr waitJiffies
        rts

// ============================================================
// WRITE DIR SECTOR (T18S1) - uses M-E $0443
// ============================================================
writeDIRSector:
        ldx #0
        lda #0
wdsClear:
        sta bamBuf,x
        inx
        bne wdsClear
        lda #$00
        sta bamBuf+0
        lda #$FF
        sta bamBuf+1
        lda #<bamBuf
        ldx #>bamBuf
        sta zpSrc
        stx zpSrc+1
        lda #$00
        sta zpDstLo
        lda #$05
        sta zpDstHi
        ldx #0
        ldy #1
        jsr upload_bytes
        lda #18
        sta mwTrkSec
        lda #1
        sta mwTrkSec+1
        jsr sendMW_TrkSec
        jsr sendME_0443
        lda #100
        jsr waitJiffies
        rts

// ============================================================
// BUILD BAM
// ============================================================
buildBAM:
        ldx #0
        lda #0
bbClear:
        sta bamBuf,x
        inx
        bne bbClear
        lda #18
        sta bamBuf+0
        lda #1
        sta bamBuf+1
        lda #$41
        sta bamBuf+2
        lda #$00
        sta bamBuf+3
        ldx #0
        ldy #4
bbLoop:
        lda sectorsPerTrack,x
        sta bamBuf,y
        lda #$FF
        sta bamBuf+1,y
        sta bamBuf+2,y
        stx bbTmpX
        lda sectorsPerTrack,x
        tax
        lda bamByte3Tbl-17,x   // indexed by (sectorCount-17): 17->$01,18->$03,19->$07,20->$0F,21->$1F
        ldx bbTmpX
        sta bamBuf+3,y
        iny
        iny
        iny
        iny
        inx
        cpx #35
        bne bbLoop
        lda #17
        sta bamBuf+72
        lda #$FC
        sta bamBuf+73
        lda #$FF
        sta bamBuf+74
        lda #$07
        sta bamBuf+75
        ldx #0
bbName:
        cpx nameLen
        bcs bbPad
        lda nameBuf,x
        sta bamBuf+144,x
        inx
        jmp bbName
bbPad:
        cpx #16
        bcs bbDone
        lda #$A0
        sta bamBuf+144,x
        inx
        jmp bbPad
bbDone:
        lda #$A0
        sta bamBuf+160
        sta bamBuf+161
        lda idBuf
        sta bamBuf+162
        lda idBuf+1
        sta bamBuf+163
        lda #$A0
        sta bamBuf+164
        lda #$32
        sta bamBuf+165
        lda #$41
        sta bamBuf+166
        lda #$A0
        sta bamBuf+167
        sta bamBuf+168
        sta bamBuf+169
        sta bamBuf+170
        rts
bbTmpX: .byte 0
bamByte3Tbl:
        .byte $01, $03, $07, $0F, $1F

// ============================================================
// UPLOAD_BYTES
// ============================================================
upload_bytes:
        stx ubCount
        sty ubCount+1
ubLoop:
        lda ubCount
        ora ubCount+1
        beq ubDone
        lda ubCount+1
        bne ubFull
        lda ubCount
        cmp #MW_MAX+1
        bcc ubPart
ubFull:
        lda #MW_MAX
        jmp ubSend
ubPart:
        lda ubCount
ubSend:
        sta ubChunk
        ldx #CMDFILE
        jsr CHKOUT
        lda #'M'
        jsr CHROUT
        lda #'-'
        jsr CHROUT
        lda #'W'
        jsr CHROUT
        lda zpDstLo
        jsr CHROUT
        lda zpDstHi
        jsr CHROUT
        lda ubChunk
        jsr CHROUT
        ldy #0
ubByte:
        lda (zpSrc),y
        jsr CHROUT
        iny
        cpy ubChunk
        bne ubByte
        jsr CLRCHN
        clc
        lda zpSrc
        adc ubChunk
        sta zpSrc
        bcc ubNsc
        inc zpSrc+1
ubNsc:
        clc
        lda zpDstLo
        adc ubChunk
        sta zpDstLo
        bcc ubNdc
        inc zpDstHi
ubNdc:
        sec
        lda ubCount
        sbc ubChunk
        sta ubCount
        bcs ubNb
        dec ubCount+1
ubNb:
        jmp ubLoop
ubDone:
        rts
ubCount: .word 0
ubChunk: .byte 0

// ============================================================
// M-W / M-E / M-R HELPERS
// ============================================================
sendMW_TrkSec:
        ldx #CMDFILE
        jsr CHKOUT
        lda #'M'
        jsr CHROUT
        lda #'-'
        jsr CHROUT
        lda #'W'
        jsr CHROUT
        lda #$0A
        jsr CHROUT
        lda #$00
        jsr CHROUT
        lda #2
        jsr CHROUT
        lda mwTrkSec
        jsr CHROUT
        lda mwTrkSec+1
        jsr CHROUT
        jsr CLRCHN
        rts
mwTrkSec: .byte 0, 0

sendME_0300:
        ldx #CMDFILE
        jsr CHKOUT
        lda #'M'
        jsr CHROUT
        lda #'-'
        jsr CHROUT
        lda #'E'
        jsr CHROUT
        lda #$00
        jsr CHROUT
        lda #$03
        jsr CHROUT
        jsr CLRCHN
        rts

sendME_044E:
        ldx #CMDFILE
        jsr CHKOUT
        lda #'M'
        jsr CHROUT
        lda #'-'
        jsr CHROUT
        lda #'E'
        jsr CHROUT
        lda #$4E
        jsr CHROUT
        lda #$04
        jsr CHROUT
        jsr CLRCHN
        rts

sendME_0320:
        ldx #CMDFILE
        jsr CHKOUT
        lda #'M'
        jsr CHROUT
        lda #'-'
        jsr CHROUT
        lda #'E'
        jsr CHROUT
        lda #$20
        jsr CHROUT
        lda #$03
        jsr CHROUT
        jsr CLRCHN
        rts

sendME_0443:
        ldx #CMDFILE
        jsr CHKOUT
        lda #'M'
        jsr CHROUT
        lda #'-'
        jsr CHROUT
        lda #'E'
        jsr CHROUT
        lda #$43
        jsr CHROUT
        lda #$04
        jsr CHROUT
        jsr CLRCHN
        rts

readJob2Result:
        ldx #CMDFILE
        jsr CHKOUT
        lda #'M'
        jsr CHROUT
        lda #'-'
        jsr CHROUT
        lda #'R'
        jsr CHROUT
        lda #$02
        jsr CHROUT
        lda #$00
        jsr CHROUT
        lda #$01            // explicit: read 1 byte
        jsr CHROUT
        jsr CLRCHN
        ldx #CMDFILE
        jsr CHKIN
        jsr CHRIN
        pha
        jsr CLRCHN
        pla
        rts

drainErrorChannel:
        ldx #CMDFILE
        jsr CHKIN
        ldy #0
decDrain:
        jsr CHRIN
        cmp #$0D
        beq decDone
        iny
        cpy #40
        bcc decDrain
decDone:
        jsr CLRCHN
        rts

openCmdChannel:
        lda #0
        ldx #<cmdName
        ldy #>cmdName
        jsr SETNAM
        lda #CMDFILE
        ldx deviceNum
        ldy #15
        jsr SETLFS
        jsr OPEN
        rts
cmdName: .byte 0

closeDrive:
        lda #CMDFILE
        jsr CLOSE
        jsr CLRCHN
        rts

// Wraparound-safe wait
waitJiffies:
        sta wjCount
        lda JIFFYL
        sta wjStart
wjLoop:
        lda JIFFYL
        sec
        sbc wjStart
        cmp wjCount
        bcc wjLoop
        rts
wjStart: .byte 0
wjCount: .byte 0

// ---- Wait A jiffies while flashing current track RED/WHITE ----
flashWait:
        sta fwTotal
        lda JIFFYL
        sta fwStart
        sta fwLast          // absolute jiffy time of last toggle
fwLoop:
        // Read JIFFYL exactly once per iteration
        lda JIFFYL
        sta fwNow

        // Check timeout
        sec
        sbc fwStart
        cmp fwTotal
        bcs fwDone

        // Toggle every 4 jiffies (~65ms PAL, ~67ms NTSC)
        lda fwNow
        sec
        sbc fwLast
        cmp #4
        bcc fwLoop

        // Time to toggle
        lda fwNow
        sta fwLast

        ldx curTrack
        lda COLRAM + ROW_TENS*40,x
        and #$0F            // color RAM is 4-bit, mask garbage upper nybble
        cmp #RED
        beq fwWhite
        lda #RED
        jmp fwSet
fwWhite:
        lda #WHITE
fwSet:
        sta COLRAM + ROW_TENS*40,x
        sta COLRAM + ROW_ONES*40,x
        jmp fwLoop
fwDone:
        // Ensure RED at exit (fdNext restores to GREEN)
        ldx curTrack
        lda #RED
        sta COLRAM + ROW_TENS*40,x
        sta COLRAM + ROW_ONES*40,x
        rts
fwTotal: .byte 0
fwStart: .byte 0
fwLast:  .byte 0
fwNow:   .byte 0

// ============================================================
// SCREEN ROUTINES
// ============================================================
clearAllScreen:
        lda #SC_SPACE
        ldx #0
casLoop:
        sta SCREEN,x
        sta SCREEN+250,x
        sta SCREEN+500,x
        sta SCREEN+750,x
        inx
        bne casLoop
        lda #LBLUE
        ldx #0
cacLoop:
        sta COLRAM,x
        sta COLRAM+250,x
        sta COLRAM+500,x
        sta COLRAM+750,x
        inx
        bne cacLoop
        rts

drawTrackGrid:
        ldx #0
dtgLoop:
        lda txtTensRow,x
        ora #$80            // reverse char
        sta SCREEN + ROW_TENS*40,x
        lda txtOnesRow,x
        ora #$80            // reverse char
        sta SCREEN + ROW_ONES*40,x
        lda #WHITE
        sta COLRAM + ROW_TENS*40,x
        sta COLRAM + ROW_ONES*40,x
        lda #SC_DOT | $80   // reverse dot
        sta SCREEN + ROW_FORMAT*40,x
        sta SCREEN + ROW_VERIFY*40,x
        lda #LBLUE
        sta COLRAM + ROW_FORMAT*40,x
        lda #YELLOW
        sta COLRAM + ROW_VERIFY*40,x
        inx
        cpx #35
        bne dtgLoop
        rts

printStatus:
        pla
        sta zpSrc
        pla
        sta zpSrc+1
        inc zpSrc
        bne ps1
        inc zpSrc+1
ps1:    ldy #0
        lda (zpSrc),y
        sta zpDst
        iny
        lda (zpSrc),y
        sta zpDst+1
        lda zpSrc
        clc
        adc #1
        sta zpSrc
        lda zpSrc+1
        adc #0
        sta zpSrc+1
        lda zpSrc+1
        pha
        lda zpSrc
        pha
        ldy #0
psLoop:
        lda (zpDst),y
        beq psEnd
        sta SCREEN+(ROW_STATUS*40)+5,y
        lda #WHITE
        sta COLRAM+(ROW_STATUS*40)+5,y
        iny
        bne psLoop
psEnd:  rts

clearStatusRow:
        ldx #39
        lda #SC_SPACE
csrLoop:
        sta SCREEN+(ROW_STATUS*40),x
        dex
        bpl csrLoop
        rts

showNameOnScreen:
        ldx #0
snoLbl: lda txtNameLbl,x
        beq snoCh
        sta SCREEN + ROW_NAME*40,x
        lda #LGRAY
        sta COLRAM + ROW_NAME*40,x
        inx
        jmp snoLbl
snoCh:  ldy #0
snoChr: cpy nameLen
        bcs snoPad
        lda nameBuf,y
        jsr petToScr
        sta SCREEN + ROW_NAME*40 + NAME_COL,y
        lda #WHITE
        sta COLRAM + ROW_NAME*40 + NAME_COL,y
        iny
        jmp snoChr
snoPad: cpy #16
        bcs snoEnd
        lda #SC_DOT
        sta SCREEN + ROW_NAME*40 + NAME_COL,y
        lda #DGRAY
        sta COLRAM + ROW_NAME*40 + NAME_COL,y
        iny
        jmp snoPad
snoEnd: rts

showIdOnScreen:
        ldx #0
sioLbl: lda txtIdLbl,x
        beq sioCh
        sta SCREEN + ROW_ID*40,x
        lda #LGRAY
        sta COLRAM + ROW_ID*40,x
        inx
        jmp sioLbl
sioCh:  ldy #0
sioChr: cpy idLen
        bcs sioPd
        lda idBuf,y
        jsr petToScr
        sta SCREEN + ROW_ID*40 + ID_COL,y
        lda #WHITE
        sta COLRAM + ROW_ID*40 + ID_COL,y
        iny
        jmp sioChr
sioPd:  cpy #2
        bcs sioEnd
        lda #SC_DOT
        sta SCREEN + ROW_ID*40 + ID_COL,y
        lda #DGRAY
        sta COLRAM + ROW_ID*40 + ID_COL,y
        iny
        jmp sioPd
sioEnd: rts

showDeviceNum:
        ldx #0
sdnLbl: lda txtDevLbl,x
        beq sdnNum
        sta SCREEN + ROW_DEVICE*40,x
        lda #LGRAY
        sta COLRAM + ROW_DEVICE*40,x
        inx
        jmp sdnLbl
sdnNum: lda deviceNum
        sec
        sbc #8
        asl
        tax
        lda devNumTxt,x
        sta SCREEN + ROW_DEVICE*40 + DEV_COL
        lda #WHITE
        sta COLRAM + ROW_DEVICE*40 + DEV_COL
        lda devNumTxt+1,x
        sta SCREEN + ROW_DEVICE*40 + DEV_COL + 1
        lda #WHITE
        sta COLRAM + ROW_DEVICE*40 + DEV_COL + 1
        rts

showModeFlag:
        ldx #0
smfLbl: lda txtModeLbl,x
        beq smfVal
        sta SCREEN + ROW_VFLAG*40,x
        lda #LGRAY
        sta COLRAM + ROW_VFLAG*40,x
        inx
        jmp smfLbl
smfVal:
        // Clear value area (7 chars max)
        ldx #6
smfCl:  lda #SC_SPACE
        sta SCREEN + ROW_VFLAG*40 + VF_COL,x
        dex
        bpl smfCl

        lda opMode
        cmp #1
        beq smfFmt
        cmp #2
        beq smfVer

        // Mode 0: FMT+VER (green)
        ldx #0
smfFV:  lda txtModeFV,x
        beq smfDone
        sta SCREEN + ROW_VFLAG*40 + VF_COL,x
        lda #LGREEN
        sta COLRAM + ROW_VFLAG*40 + VF_COL,x
        inx
        jmp smfFV

smfFmt: // Mode 1: FORMAT (yellow)
        ldx #0
smfF:   lda txtModeFO,x
        beq smfDone
        sta SCREEN + ROW_VFLAG*40 + VF_COL,x
        lda #YELLOW
        sta COLRAM + ROW_VFLAG*40 + VF_COL,x
        inx
        jmp smfF

smfVer: // Mode 2: VERIFY (cyan)
        ldx #0
smfV:   lda txtModeVO,x
        beq smfDone
        sta SCREEN + ROW_VFLAG*40 + VF_COL,x
        lda #CYAN
        sta COLRAM + ROW_VFLAG*40 + VF_COL,x
        inx
        jmp smfV

smfDone:
        rts

updateTrackDisplay:
        lda trackMode
        cmp #40
        beq udShow40
        ldx #0
ud35txt:lda txt35trk,x
        beq ud35clr
        sta SCREEN + ROW_TRKNUM*40 + 15,x
        lda #LGRAY
        sta COLRAM + ROW_TRKNUM*40 + 15,x
        inx
        jmp ud35txt
ud35clr:ldx #0
udDim:  lda txtTensRaw,x
        ora #$80
        sta SCREEN + ROW_TENS*40 + 35,x
        lda txtOnesRaw,x
        ora #$80
        sta SCREEN + ROW_ONES*40 + 35,x
        lda #SC_DOT | $80
        sta SCREEN + ROW_FORMAT*40 + 35,x
        sta SCREEN + ROW_VERIFY*40 + 35,x
        lda #DGRAY
        sta COLRAM + ROW_TENS*40 + 35,x
        sta COLRAM + ROW_ONES*40 + 35,x
        sta COLRAM + ROW_FORMAT*40 + 35,x
        sta COLRAM + ROW_VERIFY*40 + 35,x
        inx
        cpx #5
        bne udDim
        rts
udShow40:
        ldx #0
ud40txt:lda txt40trk,x
        beq ud40d
        sta SCREEN + ROW_TRKNUM*40 + 15,x
        lda #LGRAY
        sta COLRAM + ROW_TRKNUM*40 + 15,x
        inx
        jmp ud40txt
ud40d:  ldx #0
udRest: lda txtTensRaw,x
        ora #$80
        sta SCREEN + ROW_TENS*40 + 35,x
        lda txtOnesRaw,x
        ora #$80
        sta SCREEN + ROW_ONES*40 + 35,x
        lda #WHITE
        sta COLRAM + ROW_TENS*40 + 35,x
        sta COLRAM + ROW_ONES*40 + 35,x
        lda #SC_DOT | $80
        sta SCREEN + ROW_FORMAT*40 + 35,x
        sta SCREEN + ROW_VERIFY*40 + 35,x
        lda #LBLUE
        sta COLRAM + ROW_FORMAT*40 + 35,x
        lda #YELLOW
        sta COLRAM + ROW_VERIFY*40 + 35,x
        inx
        cpx #5
        bne udRest
        rts

drawAllText:
        ldx #0
dtLoop: lda textTable,x
        sta zpSrc
        lda textTable+1,x
        sta zpSrc+1
        lda zpSrc
        ora zpSrc+1
        beq dtDone
        lda textTable+2,x
        sta zpDst
        lda textTable+3,x
        sta zpDst+1
        lda textTable+4,x
        sta dtCV+1
        txa
        pha
        ldy #0
dtPr:   lda (zpSrc),y
        beq dtNxt
        sta (zpDst),y
        lda zpDst+1
        pha
        clc
        adc #>(COLRAM-SCREEN)
        sta zpDst+1
dtCV:   lda #$00
        sta (zpDst),y
        pla
        sta zpDst+1
        iny
        bne dtPr
dtNxt:  pla
        tax
        txa
        clc
        adc #5
        tax
        jmp dtLoop
dtDone: rts

// ---- Color F-key labels WHITE on the keys row ----
// Keys text at SCREEN + ROW_KEYS*40 + 3:
// "F1:35/40 F3:DEVICE F5:MODE F7:DIR"
//  ^0       ^9        ^19      ^28
colorFKeys:
        lda #WHITE
        sta COLRAM + ROW_KEYS*40 + 3       // F
        sta COLRAM + ROW_KEYS*40 + 4       // 1
        sta COLRAM + ROW_KEYS*40 + 5       // :
        sta COLRAM + ROW_KEYS*40 + 12      // F
        sta COLRAM + ROW_KEYS*40 + 13      // 3
        sta COLRAM + ROW_KEYS*40 + 14      // :
        sta COLRAM + ROW_KEYS*40 + 22      // F
        sta COLRAM + ROW_KEYS*40 + 23      // 5
        sta COLRAM + ROW_KEYS*40 + 24      // :
        sta COLRAM + ROW_KEYS*40 + 30      // F
        sta COLRAM + ROW_KEYS*40 + 31      // 7
        sta COLRAM + ROW_KEYS*40 + 32      // :
        rts

// ---- Show "STOP TO ABORT" on start row (yellow) ----
showStopHint:
        ldx #39
        lda #SC_SPACE
sshClr: sta SCREEN + ROW_START*40,x
        dex
        bpl sshClr
        ldx #0
sshLoop:lda txtStopHint,x
        beq sshDone
        sta SCREEN + ROW_START*40 + 11,x
        lda #YELLOW
        sta COLRAM + ROW_START*40 + 11,x
        inx
        bne sshLoop
sshDone:rts

// ============================================================
// SID SOUND EFFECTS (X-Copy style)
// Voice 1 only. Short, snappy feedback sounds.
// ============================================================

sidInit:
        // Clear all SID registers
        ldx #$18
siClr:  lda #0
        sta $D400,x
        dex
        bpl siClr
        // Volume max, no filters
        lda #$0F
        sta SID_VOL
        rts

// ---- Per-track tick: short high triangle pip ----
sidTick:
        lda #$00
        sta SID_V1FL
        lda #$18
        sta SID_V1FH        // freq $1800
        lda #$09
        sta SID_V1AD        // attack=0, decay=9
        lda #$00
        sta SID_V1SR        // sustain=0, release=0
        lda #$11
        sta SID_V1CR        // triangle + gate
        lda #3
        jsr waitJiffies
        lda #$10
        sta SID_V1CR        // gate off
        rts

// ---- Error buzz: short low pulse ----
sidError:
        lda #$00
        sta SID_V1FL
        sta SID_V1PL
        lda #$05
        sta SID_V1FH        // freq $0500
        lda #$08
        sta SID_V1PH        // pulse width $0800
        lda #$0A
        sta SID_V1AD        // attack=0, decay=10
        lda #$00
        sta SID_V1SR
        lda #$41
        sta SID_V1CR        // pulse + gate
        lda #6
        jsr waitJiffies
        lda #$40
        sta SID_V1CR        // gate off
        rts

// ---- Completion: three ascending triangle notes ----
sidComplete:
        lda #$14
        jsr scNote
        lda #$1C
        jsr scNote
        lda #$24
        jsr scNote
        rts
scNote:
        sta SID_V1FH
        lda #$00
        sta SID_V1FL
        lda #$09
        sta SID_V1AD
        lda #$00
        sta SID_V1SR
        lda #$11
        sta SID_V1CR        // triangle + gate
        lda #5
        jsr waitJiffies
        lda #$10
        sta SID_V1CR        // gate off
        lda #2
        jsr waitJiffies     // gap between notes
        rts

// ---- Abort: descending tone ----
sidAbort:
        lda #$18
        jsr scNote
        lda #$08
        jsr scNote
        rts

// ============================================================
// INPUT ROUTINES
// ============================================================
showInputBuf:
        ldy #0
sibLoop:cpy inputLen
        bcs sibPad
        sty sibTmp
        lda inputBuf
        clc
        adc sibTmp
        sta zpDst
        lda inputBuf+1
        adc #0
        sta zpDst+1
        ldy #0
        lda (zpDst),y
        jsr petToScr
        ldy sibTmp
        sta (zpInp),y
        lda zpInp+1
        pha
        clc
        adc #>(COLRAM-SCREEN)
        sta zpInp+1
        lda #WHITE
        sta (zpInp),y
        pla
        sta zpInp+1
        iny
        jmp sibLoop
sibPad: cpy inputMax
        bcs sibEnd
        lda #SC_DOT
        sta (zpInp),y
        lda zpInp+1
        pha
        clc
        adc #>(COLRAM-SCREEN)
        sta zpInp+1
        lda #DGRAY
        sta (zpInp),y
        pla
        sta zpInp+1
        iny
        jmp sibPad
sibEnd: rts

doInput:
        jsr showCursor
diLoop: jsr GETIN
        beq diLoop
        cmp #$0D
        bne diNR
        jmp diDone
diNR:   cmp #$14
        beq diDel
        // Accept all printable PETSCII: $20-$5F, $C1-$DA
        cmp #$20
        bcc diL2
        cmp #$60
        bcc diAcc           // $20-$5F: space, !@#$%&, digits, A-Z, etc
        cmp #$C1
        bcc diL2
        cmp #$DB
        bcc diAcc           // $C1-$DA: shifted letters
diL2:   jmp diLoop
diAcc:  ldx inputLen
        cpx inputMax
        bcs diL2
        sta diTmp
        lda inputBuf
        clc
        adc inputLen
        sta zpDst
        lda inputBuf+1
        adc #0
        sta zpDst+1
        lda diTmp
        ldy #0
        sta (zpDst),y
        lda diTmp
        jsr petToScr
        ldy inputLen
        sta (zpInp),y
        lda zpInp+1
        pha
        clc
        adc #>(COLRAM-SCREEN)
        sta zpInp+1
        lda #WHITE
        sta (zpInp),y
        pla
        sta zpInp+1
        inc inputLen
        jsr showCursor
        jmp diLoop
diDel:  lda inputLen
        bne diDO
        jmp diLoop
diDO:   ldy inputLen
        lda #SC_DOT
        sta (zpInp),y
        lda zpInp+1
        pha
        clc
        adc #>(COLRAM-SCREEN)
        sta zpInp+1
        lda #DGRAY
        sta (zpInp),y
        pla
        sta zpInp+1
        dec inputLen
        ldy inputLen
        lda #SC_DOT
        sta (zpInp),y
        lda zpInp+1
        pha
        clc
        adc #>(COLRAM-SCREEN)
        sta zpInp+1
        lda #DGRAY
        sta (zpInp),y
        pla
        sta zpInp+1
        jsr showCursor
        jmp diLoop
diDone: ldy inputLen
        lda #SC_SPACE
        sta (zpInp),y
        rts
showCursor:
        ldy inputLen
        lda #SC_SPACE | $80  // reverse space = solid block
        sta (zpInp),y
        // Write WHITE to color RAM at same position
        lda zpInp+1
        pha
        clc
        adc #>(COLRAM-SCREEN)
        sta zpInp+1
        lda #WHITE
        sta (zpInp),y
        pla
        sta zpInp+1
        rts
waitReturn:
        jsr GETIN
        cmp #$0D
        bne waitReturn
        rts
// ---- Convert error count to screencode (non-reverse) ----
// Input: A = error count (0-21)
// Output: A = screencode
//     0-9 -> '0'-'9'
//   10-15 -> 'A'-'F'
//     16+ -> 'G'+
errToChar:
        cmp #10
        bcs etcAlpha
        clc
        adc #$30            // 0-9 -> screencode $30-$39
        rts
etcAlpha:
        sec
        sbc #9              // 10->1, 11->2, ...  (A=1, B=2)
        rts

petToScr:
        cmp #$40
        bcc ptsLow          // $20-$3F: same screencode
        cmp #$60
        bcs ptsHi
        sec
        sbc #$40            // $40-$5F -> $00-$1F
        rts
ptsHi:  cmp #$C1
        bcc ptsLow
        cmp #$DB
        bcs ptsLow
        sec
        sbc #$80            // $C1-$DA -> $41-$5A (graphic chars)
ptsLow: rts

GETIN:  jmp $FFE4
CHROUT: jmp $FFD2
CLRCHN: jmp $FFCC
CHKOUT: jmp $FFC9
CHKIN:  jmp $FFC6
CHRIN:  jmp $FFCF
OPEN:   jmp $FFC0
CLOSE:  jmp $FFC3
SETLFS: jmp $FFBA
SETNAM: jmp $FFBD
STOP:   jmp $FFE1

// ============================================================
// VARIABLES
// ============================================================
nameBuf:   .fill 16, 0
idBuf:     .fill 2, 0
bamBuf:    .fill 256, 0
trackMode: .byte 40
deviceNum: .byte 8
opMode:    .byte 0             // 0=FMT+VER, 1=FORMAT, 2=VERIFY
nameLen:   .byte 0
idLen:     .byte 0
curTrack:  .byte 0
curTrack1: .byte 0
inputLen:  .byte 0
inputMax:  .byte 0
inputBuf:  .word 0
vfSector:  .byte 0
vfSectCnt: .byte 0
diTmp:     .byte 0
sibTmp:    .byte 0
vfErrCnt:  .byte 0

sectorsPerTrack:
        .byte 21,21,21,21,21,21,21,21,21,21
        .byte 21,21,21,21,21,21,21
        .byte 19,19,19,19,19,19,19
        .byte 18,18,18,18,18,18
        .byte 17,17,17,17,17
        .byte 17,17,17,17,17

// ============================================================
// ENGINE DATA - 334 bytes -> $0400
// With read($0438) and write($0443) in NOP gap
// ============================================================
engine_data:
        .byte $20,$8D,$04       // $0400 JSR $048D
        .byte $E6,$08           // $0403 INC $08
        .byte $A5,$08           // $0405 LDA $08
        .byte $C5,$06           // $0407 CMP $06
        .byte $B0,$03           // $0409 BCS $040E
        .byte $4C,$78,$F9       // $040B JMP $F978
        .byte $4C,$18,$F4       // $040E JMP $F418
        .byte $86,$08           // $0411
        .byte $A9,$24           // $0413
        .byte $85,$06           // $0415
        .byte $B9,$00,$02       // $0417
        .byte $85,$12           // $041A
        .byte $85,$16           // $041C
        .byte $B9,$01,$02       // $041E
        .byte $85,$13           // $0421
        .byte $85,$17           // $0423
        .byte $78               // $0425 SEI
        .byte $A5,$22           // $0426
        .byte $D0,$04           // $0428
        .byte $A9,$C0           // $042A
        .byte $85,$02           // $042C
        .byte $A9,$E0           // $042E
        .byte $85,$01           // $0430
        .byte $58               // $0432 CLI
        .byte $A5,$01           // $0433
        .byte $30,$FC           // $0435
        .byte $60               // $0437 RTS
// Read routine at $0438
        .byte $78               // SEI
        .byte $A9,$80           // LDA #$80
        .byte $85,$02           // STA $02
        .byte $58               // CLI
        .byte $A5,$02           // LDA $02
        .byte $30,$FC           // BMI *-2
        .byte $60               // RTS
// Write routine at $0443
        .byte $78               // SEI
        .byte $A9,$90           // LDA #$90
        .byte $85,$02           // STA $02
        .byte $58               // CLI
        .byte $A5,$02           // LDA $02
        .byte $30,$FC           // BMI *-2
        .byte $60               // RTS
// Verify-all-sectors routine at $044E (42 bytes)
// Reads ALL sectors 0..N-1, counts failures.
// C64 side patches $22 for tracks 36+ to bypass ROM seek hang.
// Input: $0A=track (via M-W), sector count at $0470 (patched)
// Output: $02=error count (0=all OK)
// M-E entry: $044E
        .byte $AD,$00,$1C      // $044E  LDA $1C00      read VIA2
        .byte $09,$08          // $0451  ORA #$08        LED on
        .byte $8D,$00,$1C      // $0453  STA $1C00
        .byte $A9,$00          // $0456  LDA #$00        error count=0
        .byte $85,$C3          // $0458  STA $C3
        .byte $A2,$00          // $045A  LDX #$00        sector counter
        .byte $86,$0B          // $045C  STX $0B         set sector
        .byte $78              // $045E  SEI
        .byte $A9,$80          // $045F  LDA #$80        READ job
        .byte $85,$02          // $0461  STA $02         submit JOB2
        .byte $58              // $0463  CLI
        .byte $A5,$02          // $0464  LDA $02         poll
        .byte $30,$FC          // $0466  BMI $0464
        .byte $C9,$01          // $0468  CMP #$01        OK?
        .byte $F0,$02          // $046A  BEQ $046E       skip if OK
        .byte $E6,$C3          // $046C  INC $C3         count error
        .byte $E8              // $046E  INX
        .byte $E0,$15          // $046F  CPX #nn         PATCHED sector count
        .byte $D0,$E9          // $0471  BNE $045C       next sector
        .byte $A5,$C3          // $0473  LDA $C3         load error count
        .byte $85,$02          // $0475  STA $02         store as result
        .byte $60              // $0477  RTS
// Remaining NOPs $0478-$048C
        .fill 21, $EA
// Header builder $048D
        .byte $A9,$07,$85,$31,$A0,$00,$98,$91,$30,$C8
        .byte $D0,$FB,$88,$8C,$01,$07,$84,$3A,$20,$8F
        .byte $F7,$A9,$CE,$8D,$0C,$1C,$A9,$FF,$8D,$03
        .byte $1C,$8D,$01,$1C,$A9,$00,$85,$C2,$85,$C0
        .byte $A5,$22,$85,$18,$A5,$C2,$85,$19,$45,$16
        .byte $45,$17,$45,$18,$85,$1A,$20,$34,$F9,$A2
        .byte $00,$A4,$C0,$B5,$24,$99,$00,$06,$C8,$E8
        .byte $E0,$08,$D0,$F5,$84,$C0,$E6,$C2,$A5,$C2
        .byte $C5,$43,$D0,$D8
// Format write $04E1-$054D
        .byte $A9,$00,$85,$C0,$A9,$FF,$8D,$01,$1C,$A2
        .byte $05,$50,$FE,$B8,$CA,$D0,$FA,$A2,$08,$A4
        .byte $C0,$50,$FE,$B8,$B9,$00,$06,$8D,$01,$1C
        .byte $C8,$CA,$D0,$F3,$84,$C0,$A2,$0B,$50,$FE
        .byte $B8,$A9,$55,$8D,$01,$1C,$CA,$D0,$F5,$A2
        .byte $05,$50,$FE,$B8,$A9,$FF,$8D,$01,$1C,$CA
        .byte $D0,$F5,$A0,$BB,$50,$FE,$B8,$B9,$00,$01
        .byte $8D,$01,$1C,$C8,$D0,$F4,$50,$FE,$B8,$B1
        .byte $30,$8D,$01,$1C,$C8,$D0,$F5,$A2,$08,$50
        .byte $FE,$B8,$A9,$55,$8D,$01,$1C,$CA,$D0,$F5
        .byte $50,$FE,$C6,$C2,$D0,$9A,$4C,$00,$FE
engine_data_end:

// ============================================================
// FAST VERIFY DATA - 93 bytes -> $0320
//
// Interleaved sector read with +11 step and bitmap.
// After reading sector N, tries sector N+11 (mod count).
// If already done, scans forward linearly.
// All sectors in ~3-4 revolutions instead of ~17-21.
//
// Located in buffer 0 ($0300-$03FF) after the 31-byte launcher.
// Safe during JOB2 reads (only JOB0 uses buffer 0, unused here).
//
// Entry: M-E $0320
// Patch: $06FE = $FF (busy flag, cleared to $00 on completion)
//        $06FF = sector count (via M-W)
// Uses:  $06E0-$06F4 bitmap, $C0/$C3 ZP
// Output: $06FE=$00 (done), $02 = error count (0 = all OK)
// ============================================================
verify_fast_data:
        .byte $AD,$00,$1C      // $0320  LDA $1C00      read VIA2
        .byte $09,$08          // $0323  ORA #$08       LED on
        .byte $8D,$00,$1C      // $0325  STA $1C00
// Clear bitmap
        .byte $A9,$00          // $0328  LDA #$00
        .byte $AE,$FF,$06      // $032A  LDX $06FF      sector count
        .byte $CA              // $032D  DEX
        .byte $9D,$E0,$06      // $032E  STA $06E0,X    clear bitmap[X]
        .byte $D0,$FA          // $0331  BNE $032D      loop X->0
// Init
        .byte $85,$C3          // $0333  STA $C3        error count=0
        .byte $A2,$00          // $0335  LDX #$00       start sector=0
        .byte $AD,$FF,$06      // $0337  LDA $06FF      remaining
        .byte $85,$C0          // $033A  STA $C0
// read_sector:
        .byte $86,$0B          // $033C  STX $0B        set sector
        .byte $78              // $033E  SEI
        .byte $A9,$80          // $033F  LDA #$80       READ job
        .byte $85,$02          // $0341  STA $02        submit JOB2
        .byte $58              // $0343  CLI
        .byte $A5,$02          // $0344  LDA $02        poll
        .byte $30,$FC          // $0346  BMI $0344      wait
        .byte $C9,$01          // $0348  CMP #$01       OK?
        .byte $F0,$02          // $034A  BEQ $034E      skip if OK
        .byte $E6,$C3          // $034C  INC $C3        error++
// mark_done:
        .byte $A9,$FF          // $034E  LDA #$FF
        .byte $9D,$E0,$06      // $0350  STA $06E0,X    mark done
        .byte $C6,$C0          // $0353  DEC $C0        remaining--
        .byte $F0,$1C          // $0355  BEQ $0373      all done
// advance +11 (coprime with 21,19,18,17 - all sectors in one cycle):
        .byte $8A              // $0357  TXA
        .byte $18              // $0358  CLC
        .byte $69,$0B          // $0359  ADC #$0B       interleave
        .byte $CD,$FF,$06      // $035B  CMP $06FF      >= sectorCount?
        .byte $90,$03          // $035E  BCC $0363      no wrap
        .byte $ED,$FF,$06      // $0360  SBC $06FF      wrap (modulo)
// no_wrap:
        .byte $AA              // $0363  TAX
        .byte $BD,$E0,$06      // $0364  LDA $06E0,X    already done?
        .byte $F0,$D3          // $0367  BEQ $033C      no -> read it
// scan_next:
        .byte $E8              // $0369  INX
        .byte $EC,$FF,$06      // $036A  CPX $06FF      past last?
        .byte $90,$F5          // $036D  BCC $0364      no -> check
        .byte $A2,$00          // $036F  LDX #$00       wrap to 0
        .byte $F0,$F1          // $0371  BEQ $0364      always taken
// all_done:
        .byte $A9,$00          // $0373  LDA #$00
        .byte $8D,$FE,$06      // $0375  STA $06FE      clear busy flag
        .byte $A5,$C3          // $0378  LDA $C3        error count
        .byte $85,$02          // $037A  STA $02        store result
        .byte $60              // $037C  RTS
verify_fast_end:

gcr_block1:
        .byte $55,$D4,$A5,$29
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29
        .byte $4A,$52,$94,$A5,$29

gcr_block2:
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29  // 1-2
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29  // 3-4
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29  // 5-6
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29  // 7-8
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29  // 9-10
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29  // 11-12
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29  // 13-14
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29  // 15-16
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29  // 17-18
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29  // 19-20
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29  // 21-22
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29  // 23-24
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29  // 25-26
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29  // 27-28
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29  // 29-30
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29  // 31-32
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29  // 33-34
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29  // 35-36
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29  // 37-38
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29  // 39-40
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29  // 41-42
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29  // 43-44
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29  // 45-46
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29  // 47-48
        .byte $4A,$52,$94,$A5,$29,$4A,$52,$94,$A5,$29  // 49-50
        .byte $4A,$52,$94,$A5,$29,$4A                  // 51 + trail

launcher_data:
        .byte $A9,$41,$85,$12,$85,$16,$A9,$42,$85,$13
        .byte $85,$17,$A9,$01,$85,$08,$A9,$24,$85,$06
        .byte $AD,$00,$1C,$09,$08,$8D,$00,$1C,$4C,$25,$04

// ============================================================
// TEXT DATA
// ============================================================
.encoding "screencode_upper"

textTable:
        .word txt_title,  SCREEN + ROW_TITLE*40 + 4
        .byte WHITE
        .word txt_copy,   SCREEN + ROW_COPY*40 + 6
        .byte CYAN
        .word txt_trklbl, SCREEN + ROW_TRKLBL*40 + 0
        .byte LGRAY
        .word txt_legend, SCREEN + ROW_LEGEND*40 + 6
        .byte LGRAY
        .word txt_keys,   SCREEN + ROW_KEYS*40 + 3
        .byte LGRAY
        .word txt_start,  SCREEN + ROW_START*40 + 10
        .byte LGREEN
        .word $0000

txt_title:  .text "DISK FORMATTER WITH VERIFICATION"
            .byte 0
txt_copy:   .text "(C) 2026 SAYIT BELET  V1.3"
            .byte 0
txt35trk:   .text "35 TRACKS"
            .byte 0
txt40trk:   .text "40 TRACKS"
            .byte 0
txt_trklbl: .text "TRACK:"
            .byte 0
txtTensRow: .text "         1111111111222222222233333333334"
            .byte 0
txtOnesRow: .text "1234567890123456789012345678901234567890"
            .byte 0
txtTensRaw: .text "33334"
txtOnesRaw: .text "67890"
txtNameLbl: .text "DISK NAME: "
            .byte 0
txtIdLbl:   .text "DISK ID  : "
            .byte 0
txtDevLbl:  .text "DEVICE   : "
            .byte 0
txtModeLbl: .text "MODE     : "
            .byte 0
txtModeFV:  .text "FMT+VER"
            .byte 0
txtModeFO:  .text "FORMAT"
            .byte 0
txtModeVO:  .text "VERIFY"
            .byte 0
txt_legend: .text "VERIFY: 0=OK 1+=BAD SECTORS"
            .byte 0
txt_keys:   .text "F1:35/40 F3:DEVICE F5:MODE F7:DIR"
            .byte 0
txt_start:  .text "PRESS RETURN TO START"
            .byte 0
txtComplRet:.text "COMPLETE - PRESS RETURN"
            .byte 0
txtAbortRet:.text "FORMAT ABORTED - PRESS RETURN"
            .byte 0
txtAbortVRet:.text "VERIFY ABORTED - PRESS RETURN"
            .byte 0
txtRCA:     .text "R)ETRY  C)ONTINUE  A)BORT?"
            .byte 0
txtStopHint:.text "HOLD STOP TO ABORT"
            .byte 0
txtEditName:.text "TYPE DISK NAME, PRESS RETURN"
            .byte 0
txtEditId:  .text "TYPE 2-CHAR DISK ID, RETURN"
            .byte 0
txtConfFmt: .text "FORMAT DISK? (Y/N)"
            .byte 0
txtConfVer: .text "VERIFY DISK? (Y/N)"
            .byte 0
txtDrvErr:  .text "DRIVE ERROR - PRESS RETURN"
            .byte 0
txtWritingDir: .text "CREATING DIRECTORY..."
            .byte 0
txtInitDrive:  .text "REINITIALIZING DRIVE..."
            .byte 0
txtFormatting: .text "FORMATTING..."
            .byte 0
txtVerifying:  .text "VERIFYING..."
            .byte 0
txtUploading:  .text "UPLOADING TO DRIVE..."
            .byte 0
devNumTxt:  .byte $30,$38, $30,$39, $31,$30, $31,$31


.encoding "petscii_upper"
txtPressKey:.text "PRESS ANY KEY TO CONTINUE"
            .byte 0
.encoding "screencode_upper"

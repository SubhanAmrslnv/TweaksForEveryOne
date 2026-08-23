; Acoustic keystrokes - the mechanical keyboard sound bank.
;
; Function definitions and global initialisers only, no top-level statements.
;
; This replaced a MIDI implementation, and the reason is worth keeping. The old
; PlayAcousticSound() sent GM percussion notes on channel 10 through
; midiOutShortMsg - woodblock, rimshot, hi-hat, bass drum, hand clap. Those are
; ORCHESTRAL SAMPLES from the Microsoft GS wavetable synth, so typing sounded
; like somebody playing a drum kit, which is not what a keyboard sounds like and
; not what the setting promises. It also inherited every property of that synth:
; a shared device another application can take, a wavetable that can be
; reassigned, and no control over the timbre at all.
;
; So the sounds are SYNTHESISED here instead - no sample files to ship, no
; external dependency, and every voice is a handful of numbers that can be
; tuned. A mechanical switch press is two things layered:
;
;   1. the click - a very short bright noise transient (the switch leaf and the
;      keycap letting go), a few milliseconds long
;   2. the thock - the keycap bottoming out on the plate, which rings as a
;      heavily damped low sine at the plate's resonance
;
; A voice is those two with their own amplitudes and decay times, plus an
; optional second click at a fixed delay - that is the spacebar's stabiliser
; rattle, and it is also what makes the copy and cut voices read as a distinct
; double tick rather than as another letter.
;
; Each voice is rendered to AK_VARIANTS complete RIFF/WAVE images at slightly
; different pitch and level and one is picked at random per press, because a
; bit-identical click on every key is the one thing that instantly sounds
; synthetic - real switches never repeat exactly.
;
; PLAYBACK IS PlaySound WITH SND_MEMORY, not a waveOut voice mixer. A new call
; cuts off the previous clip, which sounds right here (a click is under 90 ms
; and the next keystroke really does interrupt it) and costs nothing. The
; buffers must therefore stay alive for as long as they can be playing, which is
; what AK_BANK is for - and why AK_Shutdown() purges playback BEFORE dropping
; them.
;
; Rendering the bank is floating point per sample, so it never happens on the
; input path: SyncKeySounds() is the Sync* for this feature and arms a one-shot,
; exactly like every other deferred producer in the program.

global AK_SR := 22050          ; sample rate. A click is broadband but short - 22 kHz is
                               ; indistinguishable from 44 here and halves the render cost
global AK_VARIANTS := 3        ; alternates per voice, so held-down typing does not machine-gun
global AK_BANK := Map()        ; "voice|n" -> Buffer holding a complete RIFF/WAVE image
global AK_BankVol := -1        ; the levels and pitch the bank was rendered at. A settings
global AK_BankHotVol := -1     ; change that differs from these is what forces a re-render.
global AK_BankTone := -1       ; All three are declared HERE: SyncKeySounds() compares against
                               ; them, and a name that exists only after the first render is a
                               ; read of an unassigned variable waiting to happen
global AK_LastVariant := Map() ; voice -> the variant used last, so it is not used twice running
global AK_KeysDown := Map()    ; vk -> tick of its last key-down, for the auto-repeat gate

; f0     plate resonance in Hz - low is a "thock", high is a "clack"
; click  amplitude of the noise transient     ctau  its decay time constant, seconds
; body   amplitude of the damped sine         btau  its decay time constant, seconds
; ms     total length                         second  seconds until a second click, 0 = none
; pitch2 body pitch of that second hit, as a multiple of f0. 0 = click only, so a
;        key gets a rattle while an action gets a deliberate two-tone gesture -
;        rising for on, falling for off, which is legible without being musical.
AK_Voice(f0, click, body, ctau, btau, ms, second := 0, pitch2 := 0) =>
    {f0: f0, click: click, body: body, ctau: ctau, btau: btau, ms: ms
    , second: second, pitch2: pitch2}

; The keystroke voices. One per class of key - see AK_VoiceForKey().
global AK_VOICES := Map(
;      voice              f0  click  body    ctau   btau  ms  second pitch2
  "normal"    , AK_Voice(168, 0.55, 0.42, 0.0032, 0.020, 48)
, "structural", AK_Voice(205, 0.62, 0.36, 0.0028, 0.017, 46)
, "operator"  , AK_Voice(186, 0.50, 0.34, 0.0030, 0.016, 44)
, "modifier"  , AK_Voice(132, 0.38, 0.40, 0.0038, 0.024, 52)
, "space"     , AK_Voice(104, 0.50, 0.62, 0.0040, 0.030, 72, 0.007)
, "enter"     , AK_Voice(126, 0.60, 0.58, 0.0036, 0.028, 68, 0.005)
, "backspace" , AK_Voice(150, 0.52, 0.44, 0.0032, 0.022, 52)
, "copy"      , AK_Voice(238, 0.60, 0.30, 0.0026, 0.014, 62, 0.034)
, "cut"       , AK_Voice(262, 0.62, 0.26, 0.0022, 0.012, 54, 0.020)
, "paste"     , AK_Voice(92 , 0.46, 0.70, 0.0042, 0.038, 88)
; ----- action voices: a hotkey did something, and it is worth hearing which -----
, "toggleon"  , AK_Voice(196, 0.42, 0.75, 0.0026, 0.026, 132, 0.060, 1.500)
, "toggleoff" , AK_Voice(196, 0.42, 0.75, 0.0026, 0.026, 132, 0.060, 0.667)
, "command"   , AK_Voice(262, 0.50, 0.60, 0.0024, 0.018,  74)
, "alert"     , AK_Voice(110, 0.46, 0.90, 0.0040, 0.042, 190, 0.075, 1.000))

; Which voices are actions rather than keystrokes. They answer to their own
; enable flag and their own volume, because a click that fires on every letter
; and a click that fires when a feature switches off want very different levels.
global AK_ACTION_VOICES := Map("toggleon", 1, "toggleoff", 1, "command", 1, "alert", 1)

; ====== Which voice a key gets ======

AK_VoiceForKey(vk) {
    global ClipboardAppendEnabled, CopyFeedbackEnabled, MorphingPasteEnabled
    ; The clipboard verbs, and the one place in this file that has to agree with
    ; a #HotIf in InputBindings.ahk. Measured on 2.0.26: a SUPPRESSING hotkey
    ; ($^v) hides its key from the InputHook, but a PASS-THROUGH one (~^c, ~^x)
    ; does not - the hook sees the key AND the hotkey fires. So whenever those
    ; hotkeys are live, TriggerCopyFeedback / TriggerCutFeedback already make the
    ; sound and this path must stay quiet, or every Ctrl+C clicks twice.
    ;
    ; The conditions below mirror the two hotkey contexts exactly:
    ;   ~^c / ~^x   #HotIf ClipboardAppendEnabled || CopyFeedbackEnabled
    ;   $^v         #HotIf MorphingPasteEnabled   (suppressing, so v never
    ;                                              arrives here while it is on)
    ; Change one and you must change the other.
    if GetKeyState("Control", "P") {
        clipHotkeys := ClipboardAppendEnabled || CopyFeedbackEnabled
        if (vk = 0x43)
            return clipHotkeys ? "" : "copy"
        if (vk = 0x58)
            return clipHotkeys ? "" : "cut"
        if (vk = 0x56)
            return MorphingPasteEnabled ? "" : "paste"
    }

    if (vk = 0x20)
        return "space"
    if (vk = 0x0D)
        return "enter"
    if (vk = 0x08)
        return "backspace"
    ; Shift, Ctrl, Alt, CapsLock, the Win keys and the L/R forms. They are still
    ; physical keys with a keycap that bottoms out, so they get the deeper,
    ; quieter voice rather than silence.
    if (vk = 0x10 || vk = 0x11 || vk = 0x12 || vk = 0x14 || vk = 0x5B || vk = 0x5C
        || (vk >= 0xA0 && vk <= 0xA5))
        return "modifier"
    ; A-Z, 0-9 and the numpad digits
    if ((vk >= 0x41 && vk <= 0x5A) || (vk >= 0x30 && vk <= 0x39) || (vk >= 0x60 && vk <= 0x69))
        return "normal"
    ; Tab, and the OEM keys - brackets, quotes, semicolon, comma, slash, backtick
    if (vk = 0x09 || (vk >= 0xBA && vk <= 0xC0) || (vk >= 0xDB && vk <= 0xDF))
        return "structural"
    return "operator"
}

; Auto-repeat produces a key-down every ~30-100 ms for as long as a key is held,
; and a real keyboard clicks ONCE for that - the switch is already down. The
; shared hook reports key-up as well (UpdateKeyboardHook sets Notify on every key
; for it), so "already down" is exact rather than a guess at a repeat rate. The
; 2 s staleness is the self-heal: a key-up can be missed when focus changes under
; a held key, and without it that key would be silent for the rest of the session.
AK_IsRepeat(vk) {
    global AK_KeysDown
    now := A_TickCount
    held := AK_KeysDown.Has(vk) && (now - AK_KeysDown[vk]) < 2000
    AK_KeysDown[vk] := now
    return held
}

AK_KeyReleased(vk) {
    global AK_KeysDown
    ; Map.Delete THROWS on a key that is not in the map ("Item has no value"),
    ; and this runs for every key that goes UP - including plenty whose key-down
    ; the hook never saw: a key consumed by a suppressing hotkey (Win+Alt+B sends
    ; no LWin down here but does send the up), a key already held when the hook
    ; started, or anything pressed while the feature was switched off. This is a
    ; hook callback, so the throw pops an error dialog in the user's face and
    ; kills the handler for the rest of the session.
    if AK_KeysDown.Has(vk)
        AK_KeysDown.Delete(vk)
}

; ====== Playback ======

; A key was pressed. Gated on the keystroke flag.
PlayAcousticSound(voice) {
    global TypingSoundsEnabled
    if (!TypingSoundsEnabled)
        return
    AK_Emit(voice)
}

; A hotkey did something - a feature toggled, a window moved, everything was
; restored. Gated on its OWN flag, so somebody who wants the commands audible but
; not their typing (or the reverse) can have exactly that.
;
; Every call site is a named feature function that the tray menu and the settings
; window also call, never a hotkey body, so the sound follows the ACTION rather
; than the key that happened to trigger it.
PlayHotkeySound(voice) {
    global HotkeySoundsEnabled
    if (!HotkeySoundsEnabled)
        return
    AK_Emit(voice)
}

AK_Emit(voice) {
    global AK_BANK, AK_VARIANTS, AK_LastVariant
    ; "" is a deliberate silence, not a missing voice - AK_VoiceForKey returns it
    ; for a key whose sound another path is already making. It must NOT fall
    ; through to the unknown-voice fallback below.
    if (voice == "")
        return
    ; Not rendered yet. SyncKeySounds() has armed that, and a keystroke is not
    ; worth a stall to do it here.
    if (!AK_BANK.Count)
        return

    n := Random(1, AK_VARIANTS)
    if (AK_LastVariant.Has(voice) && AK_LastVariant[voice] = n)
        n := Mod(n, AK_VARIANTS) + 1
    AK_LastVariant[voice] := n

    key := voice "|" n
    if !AK_BANK.Has(key)
        key := "normal|" n
    if !AK_BANK.Has(key)
        return

    ; SND_ASYNC | SND_NODEFAULT | SND_MEMORY. ASYNC because this is on the
    ; keyboard path and must not block, NODEFAULT so a malformed buffer is
    ; silence rather than the Windows ding on every keystroke.
    try DllCall("winmm\PlaySoundW", "ptr", AK_BANK[key].Ptr, "ptr", 0, "uint", 0x0001 | 0x0002 | 0x0004)
}

; ====== The bank ======

; The Sync* for this feature: called from UpdateKeyboardHook(), which Boot() and
; ApplyUi() both call. Renders on a one-shot, re-renders when the volume or pitch
; setting changed, and frees the bank when the feature is switched off.
SyncKeySounds() {
    global TypingSoundsEnabled, HotkeySoundsEnabled, AK_BANK, AK_BankVol, AK_BankHotVol, AK_BankTone
    if (!TypingSoundsEnabled && !HotkeySoundsEnabled) {
        if AK_BANK.Count
            AK_Shutdown()
        return
    }
    if (AK_BANK.Count && AK_BankVol = Tune("keyVol") && AK_BankHotVol = Tune("hotkeyVol")
        && AK_BankTone = Tune("keyTone"))
        return
    SetTimer(AK_BuildBank, -1)
}

AK_BuildBank() {
    global AK_BANK, AK_VOICES, AK_ACTION_VOICES, AK_VARIANTS
    global AK_BankVol, AK_BankHotVol, AK_BankTone, TypingSoundsEnabled, HotkeySoundsEnabled
    if (!TypingSoundsEnabled && !HotkeySoundsEnabled)
        return

    keyVol := Tune("keyVol") / 100
    hotVol := Tune("hotkeyVol") / 100
    tone := Tune("keyTone") / 100

    ; Built into a local and published in one assignment. A keystroke can land
    ; between any two lines of this loop, and a half-filled bank would play the
    ; wrong voice or none.
    bank := Map()
    for voice, v in AK_VOICES {
        ; Actions carry their own level. The pitch setting is deliberately shared:
        ; it is the character of the whole sound set, not a per-sound tuning.
        vol := AK_ACTION_VOICES.Has(voice) ? hotVol : keyVol
        Loop AK_VARIANTS {
            ; -6%, 0, +6% of pitch, with the detuned pair very slightly quieter.
            j := (A_Index - 2) * 0.06
            bank[voice "|" A_Index] := AK_Render(v, tone * (1 + j), vol * (1 - Abs(j)))
        }
    }
    ; PUBLISH, PURGE, THEN RELEASE - in that order, and none of the three is
    ; optional. SND_ASYNC means winmm is still reading one of the OLD buffers,
    ; and dropping the last reference to them frees that memory out from under
    ; the mixer. AK_Shutdown() has the same rule; this path is the one the user
    ; actually exercises, because every change to a level or the pitch rebuilds
    ; the bank - usually while they are still typing in the field.
    ;
    ; Publishing first means a keystroke that interrupts between these lines
    ; plays a NEW clip; oldBank keeps the previous buffers alive until after the
    ; purge has stopped anything still sounding from them.
    oldBank := AK_BANK
    AK_BANK := bank
    try DllCall("winmm\PlaySoundW", "ptr", 0, "ptr", 0, "uint", 0x0040)   ; SND_PURGE
    oldBank := ""

    prevVol := AK_BankVol, prevHot := AK_BankHotVol, prevTone := AK_BankTone
    AK_BankVol := Tune("keyVol")
    AK_BankHotVol := Tune("hotkeyVol")
    AK_BankTone := Tune("keyTone")

    ; A LEVEL THE USER JUST CHANGED IS ONLY BELIEVABLE IF IT CAN BE HEARD. The
    ; settings window has no other feedback - the field holds a number, the
    ; sound it governs only happens on the next keystroke somewhere else - so a
    ; change that took effect and a change that silently did nothing look
    ; identical. One click at the new level is the difference. prev < 0 is the
    ; boot render, where a click out of nowhere would just be noise.
    if (prevVol >= 0) {
        if (AK_BankVol != prevVol || AK_BankTone != prevTone)
            PlayAcousticSound("normal")
        else if (AK_BankHotVol != prevHot)
            PlayHotkeySound("command")
    }
    try WriteLog("keysounds: rendered " bank.Count " clips, keys " AK_BankVol "% actions "
        AK_BankHotVol "% tone " AK_BankTone "%")
}

; One voice, one variant -> a Buffer holding a complete RIFF/WAVE file image.
AK_Render(v, pitch, vol) {
    global AK_SR
    sr := AK_SR
    n := Round(sr * v.ms / 1000)
    buf := Buffer(44 + n * 2, 0)
    AK_WavHeader(buf, n, sr)

    w0 := 6.283185307 * (v.f0 * pitch) / sr
    w1 := w0 * 2.63          ; the plate's second partial - inharmonic on purpose, a plain
                             ; octave rings like a musical note instead of like plastic
    ; Envelopes decay by a constant FACTOR per sample rather than by Exp() per
    ; sample: same curve, one multiply instead of a transcendental, and the whole
    ; bank renders in a fraction of the time.
    cd := Exp(-1 / (v.ctau * sr))
    bd := Exp(-1 / (v.btau * sr))
    bd2 := Exp(-1 / (v.btau * 0.55 * sr))
    ce := 1.0, be := 1.0, be2 := 1.0
    se := 0.0                              ; the second click starts silent
    sb := 0.0                              ; and so does the second body, if there is one
    w2 := v.pitch2 ? (w0 * v.pitch2) : 0
    sAt := v.second ? Round(v.second * sr) : 0
    lp := 0.0
    fade := 96                             ; samples of tail ramp. A buffer that ends mid-swing
                                           ; is a step to zero, which is itself an audible click
    i := 0
    Loop n {
        nz := Random(-1.0, 1.0)
        lp += (nz - lp) * 0.42             ; one-pole low pass...
        hp := nz - lp                      ; ...subtracted back out, so what is left is the
                                           ; bright end of the noise - the plastic in the click
        s := hp * v.click * ce
        if (sAt && i = sAt)
            se := 1.0, sb := 1.0
        if (se > 0.0) {
            s += hp * v.click * 0.6 * se
            se *= cd
        }
        s += (Sin(w0 * i) * be + Sin(w1 * i) * 0.34 * be2) * v.body
        ; The second hit's own pitch, phase-reset at the moment it lands so it
        ; reads as a separate strike rather than as the first one wavering.
        if (w2 && sb > 0.0) {
            s += Sin(w2 * (i - sAt)) * sb * v.body
            sb *= bd
        }

        if (i < 8)                         ; a hard start is a DC step, and pops
            s *= i / 8
        else if (i > n - fade)
            s *= (n - i) / fade

        val := Round(s * vol * 32767)
        if (val > 32767)
            val := 32767
        else if (val < -32767)
            val := -32767
        NumPut("short", val, buf, 44 + i * 2)

        ce *= cd, be *= bd, be2 *= bd2
        i += 1
    }
    return buf
}

; 16-bit mono PCM. The four-character tags are written byte by byte rather than
; with StrPut, which wants to add a terminator that would land in the next field.
AK_WavHeader(buf, n, sr) {
    bytes := n * 2
    AK_Tag(buf,  0, "RIFF")
    NumPut("uint", 36 + bytes, buf, 4)
    AK_Tag(buf,  8, "WAVE")
    AK_Tag(buf, 12, "fmt ")
    NumPut("uint", 16, buf, 16)            ; fmt chunk size
    NumPut("ushort", 1, buf, 20)           ; PCM
    NumPut("ushort", 1, buf, 22)           ; mono
    NumPut("uint", sr, buf, 24)
    NumPut("uint", sr * 2, buf, 28)        ; byte rate
    NumPut("ushort", 2, buf, 32)           ; block align
    NumPut("ushort", 16, buf, 34)          ; bits per sample
    AK_Tag(buf, 36, "data")
    NumPut("uint", bytes, buf, 40)
}

AK_Tag(buf, off, tag) {
    Loop 4
        NumPut("uchar", Ord(SubStr(tag, A_Index, 1)), buf, off + A_Index - 1)
}

; Purge FIRST, then drop the buffers: PlaySound is reading one of them
; asynchronously, and freeing memory out from under winmm is a crash rather than
; a wrong note. Called by Bye() and whenever the feature is switched off.
AK_Shutdown() {
    global AK_BANK, AK_BankVol, AK_BankHotVol, AK_BankTone, AK_KeysDown
    try DllCall("winmm\PlaySoundW", "ptr", 0, "ptr", 0, "uint", 0x0040)   ; SND_PURGE
    AK_BANK := Map()
    AK_KeysDown := Map()
    AK_BankVol := -1
    AK_BankHotVol := -1
    AK_BankTone := -1
}

#Requires AutoHotkey v2.0
; ============================================================================
; MediaCore.ahk - "is this window playing audio or video?"
; ============================================================================
; Answers that question for the opacity features (breathing, monitor dimmer,
; focus vignette, parallax drag, proximity ghost) so a window that is actually
; playing something never gets faded.
;
; Primary signal is the Windows audio session API (WASAPI): every render
; endpoint is asked for its session list, and a session that is Active and
; either producing signal or explicitly muted marks its process as playing.
; A user-editable executable list in settings.ini is the fallback for silent
; playback that no API reports.
;
; Design notes measured with tests\diagnostics\probe-media.ahk on 25H2 26200:
;   - IAudioSessionManager2::GetSessionEnumerator is vtable index 5.  Index 4
;     returns S_OK with a null pointer and index 6 faults, so a wrong guess
;     here is silent, not loud.
;   - IAudioMeterInformation is obtained by QueryInterface on the *session*
;     pointer, not the device.  A playing Spotify read peak 0.41-0.47 while
;     every idle session read exactly 0.
;   - The session enumerator is a snapshot.  It has to be re-fetched every
;     sweep or playback started after it was created stays invisible forever.
;     Only the device and the session manager are worth caching.
;   - CLSIDFromString on every QueryInterface was most of a 5.4 ms sweep, so
;     the IID buffers are memoised and only one endpoint is read per tick.
;
; This file must stay include-safe: function definitions and global
; initialisers only, no top-level statements, no calls to QPC(),
; RegisterAnimation() or WriteLog() - none of those exist when
; tests\test-snap.ahk includes it.  Every function that needs the clock takes
; `now` (QPC milliseconds) as a parameter.  Registration lives in
; WindowTweaks.ahk with the other Sync* functions.
; ============================================================================

; ----- tuning -----------------------------------------------------------------
global MC_PEAK_EPS       := 0.0008   ; above this counts as signal
global MC_SWEEP_MS       := 1000     ; sweep cadence while something is playing
global MC_IDLE_SWEEP_MS  := 3000     ; ... and once nothing has played for a while
global MC_IDLE_AFTER_MS  := 30000    ; how long "a while" is
global MC_ENDPOINT_TTL   := 30000    ; rebuild the cached endpoint list this often
global MC_HOLD_MS        := 8000     ; see MC_HoldMs()
global MC_MAX_POSTPONE   := 8        ; sweeps skippable while animating (~2s at 250ms)

; Only honour the fallback executable list while that program actually owns an
; audio session.  A closed-and-idle VLC is then dimmable like anything else,
; but the moment it has a file open it is protected, playing or muted.
global MC_FALLBACK_NEEDS_SESSION := true

; ----- interface identifiers --------------------------------------------------
global MC_CLSID_MMDeviceEnumerator := "{BCDE0395-E52F-467C-8E3D-C4579291692E}"
global MC_IID_IMMDeviceEnumerator  := "{A95664D2-9614-4F35-A746-DE8DB63617E6}"
global MC_IID_IAudioSessionManager2  := "{77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F}"
global MC_IID_IAudioSessionControl2  := "{BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D}"
global MC_IID_IAudioMeterInformation := "{C02216F6-8C67-4B5B-9D00-D008E73E0064}"
global MC_IID_ISimpleAudioVolume     := "{87CE5498-68D6-44E5-9215-6DA47EF883D8}"

; ----- process-level observations ---------------------------------------------
global MC_PidSeenAt      := Map()   ; pid -> ms we last saw any session for it
global MC_PidQualifiedAt := Map()   ; pid -> ms it last looked like playback
global MC_PidExe         := Map()   ; pid -> lowercased executable basename

; ----- derived per-sweep snapshots (what consumers read) ----------------------
global MC_LivePid        := Map()   ; pid -> true, currently playing
global MC_LiveExe        := Map()   ; exe -> true, some pid of this image plays
global MC_LiveSessionExe := Map()   ; exe -> true, owns a session in any state
global MC_MediaMonitor   := Map()   ; 1-based monitor index -> true

; ----- caches -----------------------------------------------------------------
global MC_HwndInfo   := Map()       ; hwnd -> {pid, exe}; neither ever changes
global MC_FallbackExe := Map()      ; exe -> true, from settings.ini

; ----- COM state --------------------------------------------------------------
global MC_EnumObj     := ""         ; ComObject wrapper - never ObjRelease this
global MC_Endpoints   := []         ; [{pDev, pMgr}] raw pointers, long-lived
global MC_BuiltAt     := 0
global MC_NextEndpoint := 1         ; round-robin cursor, one endpoint per tick

; ----- lifecycle --------------------------------------------------------------
global MC_Wanted        := false    ; is any consumer feature switched on
global MC_TrackMonitors := false    ; does the monitor dimmer need MC_MediaMonitor
global MC_LastHitAt     := 0        ; ms we last saw anything playing
global MC_MeterOk       := true     ; cleared if the meter interface is missing
global MC_MeterWarned   := false

; ==============================================================================
;  Pure helpers - no COM, no clock, no window calls.  Unit tested.
; ==============================================================================

; Lowercased file name with any directory stripped.
MC_Basename(path) {
    if (path = "")
        return ""
    SplitPath(path, &name)
    return StrLower(name)
}

; Parse the user's fallback list into a Map of lowercased "foo.exe" keys.
; Accepts commas, semicolons and whitespace as separators.  A token containing
; a path separator is rejected outright rather than silently basenamed - the
; setting is a list of image names, and accepting paths would imply we match on
; the full path, which we do not.
MC_ParseExeList(s) {
    out := Map()
    if (s = "")
        return out
    for token in StrSplit(RegExReplace(s, "[;\s]+", ","), ",") {
        token := Trim(token)
        if (token = "")
            continue
        if InStr(token, "\") || InStr(token, "/") || InStr(token, ":")
            continue
        token := StrLower(token)
        if !RegExMatch(token, "\.exe$")
            token .= ".exe"
        out[token] := true
    }
    return out
}

; Does one audio session look like playback right now?
;
; Both halves matter.  Active on its own is a false positive that never clears:
; Discord and a lot of Electron apps hold a permanently open silent render
; stream, and those windows would become undimmable forever.  Peak on its own
; is a false negative, because GetPeakValue only reports the last device period
; (~10 ms), so a once-per-second sample lands in a quiet passage regularly.
; Muted is folded in because the meter is post-volume, so a muted VLC reads
; zero while very much still playing.
MC_Qualifies(state, peak, muted, eps) {
    if (state != 1)                  ; 0 Inactive, 1 Active, 2 Expired
        return false
    return (peak > eps) || (muted = 1)
}

; Has an observation aged out?  Never-seen (0) counts as expired.
MC_HoldExpired(lastAt, now, holdMs) {
    if (lastAt = 0)
        return true
    return (now - lastAt) >= holdMs
}

; How long to keep treating a process as playing after it stops looking like it.
; Tied to the breathing idle threshold so the two can never be configured into
; a dim/wake flicker: the hold must outlast the gap that triggers dimming.
MC_HoldMs(breathingIdleMs) {
    return Max(8000, breathingIdleMs + 2000)
}

; Which monitor owns a rectangle, by its centre point.  monRects is an array of
; {l, t, r, b}.  Falls back to 1 when the centre is off every monitor, matching
; what the dimmer does with an unplaceable window.
MC_MonitorIndexForRect(x, y, w, h, monRects) {
    cx := x + w // 2
    cy := y + h // 2
    for i, m in monRects {
        if (cx >= m.l && cx < m.r && cy >= m.t && cy < m.b)
            return i
    }
    return 1
}

; ==============================================================================
;  Consumer API - O(1), safe to call from inside a per-frame loop
; ==============================================================================

; Is this window playing audio or video?
;
; Three ways to match, in order of precision:
;   1. Direct pid.  Native players - VLC, mpv, foobar - render their own audio.
;   2. Same image name.  Chrome, Edge and Firefox route every tab through one
;      out-of-process audio service, and Electron apps do the same, so the
;      producing pid is never the pid that owns the window.  There is no way to
;      recover which *window* is playing, so every window of a program that is
;      producing audio is protected.  That over-protects a browser with one
;      noisy tab, which is invisible; under-protecting is the reported bug.
;   3. The fallback list, for playback no API reports (a muted browser tab).
; Is anything at all capable of matching right now?  O(1), four Map.Count reads.
;
; Consumers call MC_IsMediaHwnd once per window per animation frame, and it was
; measured at 1.70 us - about 2 ms/s with 20 tracked windows at 60 fps, the
; largest steady-state cost in the whole fade path.  Almost all of that was paid
; while nothing was playing, because the old early-out tested MC_FallbackExe,
; which is never empty (it holds the user's exe list).  What actually matters is
; whether any of those exes owns a session, which is MC_LiveSessionExe.
;
; Hoist this out of a per-window loop and skip the loop's calls entirely when it
; is false; the result is identical because every branch below needs one of these
; Maps to be non-empty.
MC_AnyMedia() {
    global MC_LivePid, MC_LiveExe, MC_LiveSessionExe, MC_FallbackExe
    global MC_FALLBACK_NEEDS_SESSION
    if (MC_LivePid.Count || MC_LiveExe.Count)
        return true
    if !MC_FallbackExe.Count
        return false
    ; The fallback list only counts while that program owns an audio session -
    ; unless the caller has turned that requirement off.
    return MC_FALLBACK_NEEDS_SESSION ? (MC_LiveSessionExe.Count > 0) : true
}

MC_IsMediaHwnd(hwnd) {
    global MC_LivePid, MC_LiveExe, MC_LiveSessionExe, MC_FallbackExe
    global MC_FALLBACK_NEEDS_SESSION

    ; Same condition as MC_AnyMedia(), deliberately inline: measured A/B, calling
    ; it here instead cost 33% of this function's time in the common early-out
    ; case. Keep the two in step if either changes.
    if !(MC_LivePid.Count || MC_LiveExe.Count
        || (MC_FallbackExe.Count && (MC_LiveSessionExe.Count || !MC_FALLBACK_NEEDS_SESSION)))
        return false
    info := MC_InfoFor(hwnd)
    if !info
        return false
    if MC_LivePid.Has(info.pid)
        return true
    if (info.exe != "" && MC_LiveExe.Has(info.exe))
        return true
    if (info.exe != "" && MC_FallbackExe.Has(info.exe)) {
        if (!MC_FALLBACK_NEEDS_SESSION || MC_LiveSessionExe.Has(info.exe))
            return true
    }
    return false
}

; Does this 1-based monitor index hold a window that is playing?
MC_MediaOnMonitor(idx) {
    global MC_MediaMonitor
    return MC_MediaMonitor.Has(idx)
}

; pid and image name for a window.  Both are fixed for the life of the handle,
; so this is resolved once and cached; the sweep never pays for it again.
MC_InfoFor(hwnd) {
    global MC_HwndInfo
    if MC_HwndInfo.Has(hwnd)
        return MC_HwndInfo[hwnd]
    if !DllCall("IsWindow", "ptr", hwnd)
        return ""
    pid := 0, exe := ""
    try {
        pid := WinGetPID(hwnd)
        exe := StrLower(WinGetProcessName(hwnd))
    } catch
        return ""
    info := {pid: pid, exe: exe}
    MC_HwndInfo[hwnd] := info
    return info
}

MC_SetFallbackList(s) {
    global MC_FallbackExe
    MC_FallbackExe := MC_ParseExeList(s)
}

MC_SetHoldMs(breathingIdleMs) {
    global MC_HOLD_MS
    MC_HOLD_MS := MC_HoldMs(breathingIdleMs)
}

; ==============================================================================
;  Sweep
; ==============================================================================

; Driven by the MC_Tick() timer in WindowTweaks.ahk, not by the animation
; scheduler: a sweep this slow does not belong on the 16 ms frame loop, where it
; would keep the scheduler (and timeBeginPeriod(1)) alive forever.  Self-throttles
; on top of the timer cadence; MC_SetWanted() plus SyncMediaCore() own start/stop.
; `busy` lets the caller say "something is animating right now". A sweep costs a
; measured 230 us, and the 30-second endpoint rebuild costs 6.5 ms of blocking
; COM - dropped into a 16 ms animation frame that is a visible hitch. Playback
; observations are held for 8 seconds, so postponing a sweep by a few hundred
; milliseconds cannot change any consumer's answer.
;
; Bounded: after MC_MAX_POSTPONE consecutive deferrals the sweep runs anyway, so
; a continuously-animating desktop cannot starve it.
MC_SweepStep(now, busy := false) {
    global MC_Wanted, MC_SWEEP_MS, MC_IDLE_SWEEP_MS, MC_IDLE_AFTER_MS, MC_LastHitAt
    global MC_MAX_POSTPONE
    static lastCheck := 0
    static postponed := 0

    if !MC_Wanted
        return

    ; Back off to a slower cadence when nothing has played for a while, so an
    ; idle machine is not woken once a second for nothing.
    interval := ((now - MC_LastHitAt) > MC_IDLE_AFTER_MS) ? MC_IDLE_SWEEP_MS : MC_SWEEP_MS
    if (now - lastCheck < interval)
        return

    if (busy && postponed < MC_MAX_POSTPONE) {
        postponed++
        return
    }
    postponed := 0
    lastCheck := now

    MC_Sweep(now)
}

MC_Sweep(now) {
    global MC_Endpoints, MC_BuiltAt, MC_ENDPOINT_TTL, MC_NextEndpoint

    if (!MC_Endpoints.Length || (now - MC_BuiltAt) > MC_ENDPOINT_TTL)
        MC_BuildEndpoints(now)
    if !MC_Endpoints.Length
        return

    ; One endpoint per tick.  Reading every endpoint every tick was the bulk of
    ; the measured sweep cost, and a machine with two outputs still gets a full
    ; refresh every two seconds - far inside the hold window.
    if (MC_NextEndpoint > MC_Endpoints.Length)
        MC_NextEndpoint := 1
    MC_ReadEndpoint(MC_Endpoints[MC_NextEndpoint], now)
    MC_NextEndpoint++

    MC_Expire(now)
    MC_Publish(now)
    MC_RefreshMonitors()
}

; Turn the raw per-pid observations into the flat Maps consumers read.
MC_Publish(now) {
    global MC_PidSeenAt, MC_PidQualifiedAt, MC_PidExe, MC_HOLD_MS
    global MC_LivePid, MC_LiveExe, MC_LiveSessionExe, MC_LastHitAt

    MC_LivePid.Clear(), MC_LiveExe.Clear(), MC_LiveSessionExe.Clear()

    for pid, ts in MC_PidQualifiedAt {
        if MC_HoldExpired(ts, now, MC_HOLD_MS)
            continue
        MC_LivePid[pid] := true
        if MC_PidExe.Has(pid)
            MC_LiveExe[MC_PidExe[pid]] := true
    }
    for pid, ts in MC_PidSeenAt {
        if MC_HoldExpired(ts, now, MC_HOLD_MS)
            continue
        if MC_PidExe.Has(pid)
            MC_LiveSessionExe[MC_PidExe[pid]] := true
    }
    if MC_LivePid.Count
        MC_LastHitAt := now
}

; Drop observations for processes that have been quiet for two hold windows.
; A pid number can be recycled by a new process, so this also bounds how long a
; stale pid->exe mapping can mis-protect a window: worst case one window stays
; bright for 2 * MC_HOLD_MS.
MC_Expire(now) {
    global MC_PidSeenAt, MC_PidQualifiedAt, MC_PidExe, MC_HOLD_MS
    dead := []
    for pid, ts in MC_PidSeenAt {
        if MC_HoldExpired(ts, now, MC_HOLD_MS * 2)
            dead.Push(pid)
    }
    for pid in dead {
        MC_PidSeenAt.Delete(pid)
        if MC_PidQualifiedAt.Has(pid)
            MC_PidQualifiedAt.Delete(pid)
        if MC_PidExe.Has(pid)
            MC_PidExe.Delete(pid)
    }
}

; Which monitors currently hold a playing window.  Only the monitor dimmer
; needs this, and only while something is actually playing, so the window
; enumeration is skipped entirely the rest of the time.
MC_RefreshMonitors() {
    global MC_TrackMonitors, MC_MediaMonitor
    global MC_LivePid, MC_LiveExe, MC_FallbackExe

    MC_MediaMonitor.Clear()
    if !MC_TrackMonitors
        return
    if (!MC_LivePid.Count && !MC_LiveExe.Count && !MC_FallbackExe.Count)
        return

    rects := []
    try {
        loop MonitorGetCount() {
            MonitorGet(A_Index, &mL, &mT, &mR, &mB)
            rects.Push({l: mL, t: mT, r: mR, b: mB})
        }
    } catch
        return
    if !rects.Length
        return

    try list := WinGetList()
    catch
        return

    for hwnd in list {
        if !DllCall("IsWindow", "ptr", hwnd)
            continue
        try {
            if !(WinGetStyle(hwnd) & 0x10000000)          ; WS_VISIBLE
                continue
            if (WinGetMinMax(hwnd) = -1)                  ; minimized
                continue
            if !MC_IsMediaHwnd(hwnd)
                continue
            WinGetPos(&wX, &wY, &wW, &wH, hwnd)
            MC_MediaMonitor[MC_MonitorIndexForRect(wX, wY, wW, wH, rects)] := true
        }
    }
}

; ==============================================================================
;  WASAPI
; ==============================================================================
; Pointer discipline, because AHK has no `finally` and a throw halfway through
; would leak every pointer held at that moment:
;   1. Every raw pointer is set to 0 before the try.
;   2. It is released in exactly one place - the tail of the function that
;      obtained it.  Never inside a continue path, never inside a catch.
;   3. ComObject() wrappers are reference-counted by AHK.  Never ObjRelease one.
;   4. Every ComCall passes "Int" as its final argument so it returns the raw
;      HRESULT instead of throwing.  A throw from the middle of a function
;      holding four pointers is exactly the leak rule 2 exists to prevent.

; Memoised IID buffers.  CLSIDFromString on every QueryInterface was most of
; the original 5.4 ms sweep.
MC_Iid(guid) {
    static cache := Map()
    if cache.Has(guid)
        return cache[guid]
    buf := Buffer(16, 0)
    if (DllCall("ole32\CLSIDFromString", "WStr", guid, "Ptr", buf, "Int") != 0)
        return ""
    cache[guid] := buf
    return buf
}

MC_BuildEndpoints(now) {
    global MC_EnumObj, MC_Endpoints, MC_BuiltAt, MC_NextEndpoint
    global MC_CLSID_MMDeviceEnumerator, MC_IID_IMMDeviceEnumerator
    global MC_IID_IAudioSessionManager2

    MC_ReleaseEndpoints()
    MC_BuiltAt := now
    MC_NextEndpoint := 1

    try MC_EnumObj := ComObject(MC_CLSID_MMDeviceEnumerator, MC_IID_IMMDeviceEnumerator)
    catch {
        MC_EnumObj := ""
        return
    }

    pColl := 0
    try {
        ; EnumAudioEndpoints(eRender = 0, DEVICE_STATE_ACTIVE = 1).  Every active
        ; output matters, not just the default one - a film playing through an
        ; HDMI monitor is on a different endpoint than the desktop speakers.
        if (ComCall(3, MC_EnumObj, "Int", 0, "UInt", 1, "Ptr*", &pColl, "Int") != 0 || !pColl)
            throw Error("EnumAudioEndpoints")

        nDev := 0
        if (ComCall(3, pColl, "UInt*", &nDev, "Int") != 0)
            nDev := 0

        iidMgr := MC_Iid(MC_IID_IAudioSessionManager2)
        loop nDev {
            pDev := 0, pMgr := 0
            if (ComCall(4, pColl, "UInt", A_Index - 1, "Ptr*", &pDev, "Int") != 0 || !pDev)
                continue
            ; IMMDevice::Activate(iid, CLSCTX_ALL = 23, null, out)
            if (ComCall(3, pDev, "Ptr", iidMgr, "UInt", 23, "Ptr", 0, "Ptr*", &pMgr, "Int") = 0 && pMgr)
                MC_Endpoints.Push({pDev: pDev, pMgr: pMgr})
            else
                ObjRelease(pDev)
        }
    }
    if pColl
        ObjRelease(pColl)
}

MC_ReleaseEndpoints() {
    global MC_EnumObj, MC_Endpoints
    for dev in MC_Endpoints {
        try ObjRelease(dev.pMgr)          ; manager before the device that made it
        try ObjRelease(dev.pDev)
    }
    MC_Endpoints := []
    MC_EnumObj := ""                      ; wrapper: drop the reference, no Release
}

MC_ReadEndpoint(dev, now) {
    global MC_Endpoints, MC_BuiltAt

    pSE := 0
    ok := false
    try {
        ; The session enumerator is a snapshot of the sessions that existed when
        ; it was created, so it cannot be cached - a track started since would
        ; never appear.  Index 5 is GetSessionEnumerator; see the header.
        if (ComCall(5, dev.pMgr, "Ptr*", &pSE, "Int") = 0 && pSE) {
            ok := true
            cnt := 0
            if (ComCall(3, pSE, "Int*", &cnt, "Int") = 0) {
                loop cnt
                    MC_ReadSession(pSE, A_Index - 1, now)
            }
        }
    }
    if pSE
        ObjRelease(pSE)

    ; A device that stops answering has usually been unplugged or reset.  Force
    ; a rebuild rather than reading a dead pointer once a second forever.
    if !ok
        MC_BuiltAt := 0
}

MC_ReadSession(pSE, i, now) {
    global MC_PidSeenAt, MC_PidQualifiedAt, MC_PidExe, MC_PEAK_EPS
    global MC_IID_IAudioSessionControl2, MC_IID_IAudioMeterInformation
    global MC_IID_ISimpleAudioVolume, MC_MeterOk, MC_MeterWarned
    static ownPid := DllCall("GetCurrentProcessId", "uint")

    pCtl := 0, pCtl2 := 0, pMeter := 0, pVol := 0
    state := -1, pid := 0, peak := 0.0, muted := 0

    try {
        if (ComCall(4, pSE, "Int", i, "Ptr*", &pCtl, "Int") != 0 || !pCtl)
            throw Error("GetSession")
        if (ComCall(3, pCtl, "Int*", &state, "Int") != 0)     ; IAudioSessionControl::GetState
            throw Error("GetState")

        if (ComCall(0, pCtl, "Ptr", MC_Iid(MC_IID_IAudioSessionControl2), "Ptr*", &pCtl2, "Int") != 0 || !pCtl2)
            throw Error("QI IAudioSessionControl2")
        ; IsSystemSoundsSession returns S_OK for yes, S_FALSE for no.  Those
        ; sessions report pid 0 and fire on every notification chime.
        if (ComCall(15, pCtl2, "Int") = 0)
            throw Error("system sounds")
        if (ComCall(14, pCtl2, "UInt*", &pid, "Int") != 0 || !pid)
            throw Error("GetProcessId")
        if (pid = ownPid) {
            pid := 0                 ; clear first: the tail below keys off pid
            throw Error("self")
        }

        ; Only Active sessions are worth metering, and on a real machine most
        ; sessions are Inactive or Expired - so the two extra QueryInterface
        ; calls below are skipped for the majority of them.
        if (state = 1) {
            if (ComCall(0, pCtl, "Ptr", MC_Iid(MC_IID_IAudioMeterInformation), "Ptr*", &pMeter, "Int") = 0 && pMeter) {
                if (ComCall(3, pMeter, "Float*", &peak, "Int") != 0)
                    peak := 0.0
            } else if (MC_MeterOk) {
                ; Without a meter we cannot tell playback from an idle open
                ; stream.  Degrade to state alone: over-protects apps that hold
                ; a silent stream, but never flickers.
                MC_MeterOk := false
                if !MC_MeterWarned {
                    MC_MeterWarned := true
                    OutputDebug("MediaCore: IAudioMeterInformation unavailable, "
                        . "falling back to session state only")
                }
            }
            if (ComCall(0, pCtl, "Ptr", MC_Iid(MC_IID_ISimpleAudioVolume), "Ptr*", &pVol, "Int") = 0 && pVol) {
                if (ComCall(6, pVol, "Int*", &muted, "Int") != 0)   ; GetMute
                    muted := 0
            }
        }
    }

    if pVol    ObjRelease(pVol)
    if pMeter  ObjRelease(pMeter)
    if pCtl2   ObjRelease(pCtl2)
    if pCtl    ObjRelease(pCtl)

    if !pid
        return

    MC_PidSeenAt[pid] := now
    if !MC_PidExe.Has(pid)
        MC_PidExe[pid] := MC_ExeForPid(pid)

    qualifies := MC_MeterOk
        ? MC_Qualifies(state, peak, muted, MC_PEAK_EPS)
        : (state = 1)
    if qualifies
        MC_PidQualifiedAt[pid] := now
}

; Image name for a pid.  ProcessGetName handles almost everything; the Win32
; fallback exists because a sandboxed browser child can refuse the handle types
; the builtin asks for.
MC_ExeForPid(pid) {
    try return StrLower(ProcessGetName(pid))
    hProc := DllCall("OpenProcess", "uint", 0x1000, "int", 0, "uint", pid, "ptr")
    if !hProc
        return ""
    name := ""
    try {
        buf := Buffer(520, 0)
        size := 260
        if DllCall("QueryFullProcessImageNameW", "ptr", hProc, "uint", 0,
                   "ptr", buf, "uint*", &size, "int")
            name := MC_Basename(StrGet(buf, "UTF-16"))
    }
    DllCall("CloseHandle", "ptr", hProc)
    return name
}

; ==============================================================================
;  Lifecycle
; ==============================================================================

; Called by WindowTweaks whenever a consumer feature is toggled.  MediaCore
; cannot register itself with the scheduler - AnimationScheduler.ahk is not
; include-safe for the test harness - so the caller owns registration and this
; only records intent and tears down when nothing wants it.
MC_SetWanted(wanted, trackMonitors, now) {
    global MC_Wanted, MC_TrackMonitors, MC_LastHitAt
    MC_TrackMonitors := trackMonitors
    if (wanted = MC_Wanted)
        return
    MC_Wanted := wanted
    if wanted {
        MC_LastHitAt := now      ; start the idle back-off clock from here
        return
    }
    MC_ReleaseAll()
}

MC_RemoveHwnd(hwnd) {
    global MC_HwndInfo
    if MC_HwndInfo.Has(hwnd)
        MC_HwndInfo.Delete(hwnd)
    ; Deliberately does not touch MC_PidQualifiedAt: that is keyed by process,
    ; and a browser can close one window while another keeps playing.
}

MC_ReleaseAll() {
    global MC_PidSeenAt, MC_PidQualifiedAt, MC_PidExe
    global MC_LivePid, MC_LiveExe, MC_LiveSessionExe, MC_MediaMonitor, MC_HwndInfo
    MC_ReleaseEndpoints()
    for m in [MC_PidSeenAt, MC_PidQualifiedAt, MC_PidExe,
              MC_LivePid, MC_LiveExe, MC_LiveSessionExe, MC_MediaMonitor, MC_HwndInfo] {
        m.Clear()
    }
}

MC_Shutdown() {
    global MC_Wanted
    MC_Wanted := false
    MC_ReleaseAll()
}

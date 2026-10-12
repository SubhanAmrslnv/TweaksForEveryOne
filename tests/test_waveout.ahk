#Requires AutoHotkey v2.0

AK_SR := 22050
AK_Voices := []
AK_NextVoice := 1

AK_InitPool() {
    global AK_Voices, AK_SR
    if AK_Voices.Length
        return

    wfx := Buffer(18, 0)
    NumPut("ushort", 1, wfx, 0) ; wFormatTag = WAVE_FORMAT_PCM
    NumPut("ushort", 1, wfx, 2) ; nChannels = 1
    NumPut("uint", AK_SR, wfx, 4) ; nSamplesPerSec
    NumPut("uint", AK_SR * 2, wfx, 8) ; nAvgBytesPerSec
    NumPut("ushort", 2, wfx, 12) ; nBlockAlign
    NumPut("ushort", 16, wfx, 14) ; wBitsPerSample
    NumPut("ushort", 0, wfx, 16) ; cbSize

    Loop 16 {
        hwo := 0
        if DllCall("winmm\waveOutOpen", "ptr*", &hwo, "uint", 0xFFFFFFFF, "ptr", wfx.Ptr, "ptr", 0, "ptr", 0, "uint", 0) == 0 {
            hdr := Buffer(A_PtrSize == 8 ? 48 : 32, 0)
            AK_Voices.Push({hwo: hwo, hdr: hdr, prepared: false})
        }
    }
}

AK_ShutdownPool() {
    global AK_Voices
    for v in AK_Voices {
        DllCall("winmm\waveOutReset", "ptr", v.hwo)
        if v.prepared {
            DllCall("winmm\waveOutUnprepareHeader", "ptr", v.hwo, "ptr", v.hdr.Ptr, "uint", v.hdr.Size)
        }
        DllCall("winmm\waveOutClose", "ptr", v.hwo)
    }
    AK_Voices := []
}

; generate a 100ms beep at 440hz
AK_RenderBeep() {
    global AK_SR
    sr := AK_SR
    ms := 100
    n := Round(sr * ms / 1000)
    buf := Buffer(44 + n * 2, 0)
    
    f := 440
    vol := 0.5
    Loop n {
        s := Sin(6.283185307 * f * (A_Index - 1) / sr)
        val := Round(s * vol * 32767)
        if (val > 32767)
            val := 32767
        else if (val < -32767)
            val := -32767
        NumPut("short", val, buf, 44 + (A_Index - 1) * 2)
    }
    return buf
}

global TestBuf := AK_RenderBeep()

AK_EmitBeep() {
    global TestBuf
    global AK_Voices, AK_NextVoice
    
    v := AK_Voices[AK_NextVoice]
    AK_NextVoice := Mod(AK_NextVoice, AK_Voices.Length) + 1
    
    DllCall("winmm\waveOutReset", "ptr", v.hwo)
    
    if v.prepared {
        DllCall("winmm\waveOutUnprepareHeader", "ptr", v.hwo, "ptr", v.hdr.Ptr, "uint", v.hdr.Size)
        v.prepared := false
    }
    
    NumPut("ptr", TestBuf.Ptr + 44, v.hdr, 0)
    NumPut("uint", TestBuf.Size - 44, v.hdr, A_PtrSize)
    NumPut("uint", 0, v.hdr, A_PtrSize + 4)
    NumPut("ptr", 0, v.hdr, A_PtrSize + 8)
    NumPut("uint", 0, v.hdr, A_PtrSize * 2 + 8)
    NumPut("uint", 0, v.hdr, A_PtrSize * 2 + 12)
    NumPut("ptr", 0, v.hdr, A_PtrSize * 2 + 16)
    NumPut("ptr", 0, v.hdr, A_PtrSize * 3 + 16)
    
    if (DllCall("winmm\waveOutPrepareHeader", "ptr", v.hwo, "ptr", v.hdr.Ptr, "uint", v.hdr.Size) == 0) {
        v.prepared := true
        DllCall("winmm\waveOutWrite", "ptr", v.hwo, "ptr", v.hdr.Ptr, "uint", v.hdr.Size)
    }
}

AK_InitPool()
Loop 10 {
    AK_EmitBeep()
    Sleep 20
}
Sleep 1000
AK_ShutdownPool()
FileAppend("Success
", "*")

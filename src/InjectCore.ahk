#Requires AutoHotkey v2.0
; Loads and unloads the in-process thumbnail payload inside explorer.exe.
; Function definitions only, so the test scripts can include this without
; starting the program.
;
; Why this can be done without administrator rights: explorer.exe runs as the
; logged-in user at medium integrity, the same as this program, so a same-user
; process may open it with full access. Measured on this machine unelevated -
; OpenProcess(PROCESS_ALL_ACCESS) on both explorer PIDs returned a live handle.
; Elevation is only needed by tools that hook the shell at boot from a service.
;
; This file deliberately does no XAML work. It moves a DLL into the process and
; nothing else; everything about thumbnail ordering lives in the payload. That
; split is what keeps the AutoHotkey side testable and the C++ side replaceable.

global INJ_DLL_NAME := "ThumbReorder.dll"
global INJ_LastError := ""

; ====================================================================== state =
; The taskbar's owner, not "any explorer.exe". There are routinely two or more
; explorer processes - on this machine, two - and only the one that owns
; Shell_TrayWnd hosts the taskbar and its thumbnail flyouts. Injecting into a
; folder-window explorer would load the payload somewhere it can never work.
INJ_TaskbarPid() {
    hwnd := DllCall("FindWindow", "str", "Shell_TrayWnd", "ptr", 0, "ptr")
    if !hwnd
        return 0
    pid := 0
    DllCall("GetWindowThreadProcessId", "ptr", hwnd, "uint*", &pid)
    return pid
}

; Walks the target's module list. Used both to avoid double-injection and to
; recover the real module handle for ejecting.
;
; The handle cannot come from the injecting thread's exit code: CreateRemoteThread
; reports a DWORD, so a 64-bit HMODULE is silently truncated to its low 32 bits
; and FreeLibrary would later be handed a bogus pointer.
INJ_ModuleBase(pid, name) {
    static TH32CS_SNAPMODULE := 0x00000008
    static ENTRY_SIZE := 1080          ; sizeof(MODULEENTRY32W) on x64

    snap := DllCall("CreateToolhelp32Snapshot", "uint", TH32CS_SNAPMODULE
                  , "uint", pid, "ptr")
    if (snap = -1 || !snap)
        return 0

    found := 0
    try {
        me := Buffer(ENTRY_SIZE, 0)
        NumPut("uint", ENTRY_SIZE, me, 0)
        ok := DllCall("Module32FirstW", "ptr", snap, "ptr", me)
        while ok {
            if (StrGet(me.Ptr + 48, 256, "UTF-16") = name) {
                found := NumGet(me, 40, "ptr")     ; hModule
                break
            }
            ok := DllCall("Module32NextW", "ptr", snap, "ptr", me)
        }
    }
    DllCall("CloseHandle", "ptr", snap)
    return found
}

INJ_IsInjected(pid := 0) {
    global INJ_DLL_NAME
    if !pid
        pid := INJ_TaskbarPid()
    if !pid
        return false
    return INJ_ModuleBase(pid, INJ_DLL_NAME) != 0
}

; ===================================================================== inject =
; Classic LoadLibraryW-in-a-remote-thread. kernel32 is mapped at the same base
; in every process of a session, so this process's LoadLibraryW address is valid
; in the target - which is the only reason this technique needs no shellcode.
INJ_Inject(dllPath) {
    global INJ_DLL_NAME, INJ_LastError
    static MEM_COMMIT_RESERVE := 0x3000
    static PAGE_READWRITE     := 0x04
    static MEM_RELEASE        := 0x8000
    static RIGHTS             := 0x0002 | 0x0008 | 0x0010 | 0x0020 | 0x0400

    INJ_LastError := ""

    if !FileExist(dllPath) {
        INJ_LastError := "payload not found: " dllPath
        return false
    }

    ; A relative path would be resolved against the TARGET's working directory,
    ; which is not this program's folder.
    dllPath := INJ_FullPath(dllPath)

    pid := INJ_TaskbarPid()
    if !pid {
        INJ_LastError := "no Shell_TrayWnd; explorer may be restarting"
        return false
    }
    if INJ_ModuleBase(pid, INJ_DLL_NAME)
        return true                      ; already loaded, nothing to do

    proc := DllCall("OpenProcess", "uint", RIGHTS, "int", 0, "uint", pid, "ptr")
    if !proc {
        INJ_LastError := "OpenProcess failed, error " A_LastError
        return false
    }

    remote := 0, thread := 0, okAll := false
    try {
        bytes := (StrLen(dllPath) + 1) * 2
        remote := DllCall("VirtualAllocEx", "ptr", proc, "ptr", 0, "uptr", bytes
                        , "uint", MEM_COMMIT_RESERVE, "uint", PAGE_READWRITE, "ptr")
        if !remote
            throw Error("VirtualAllocEx failed, error " A_LastError)

        buf := Buffer(bytes, 0)
        StrPut(dllPath, buf, "UTF-16")
        if !DllCall("WriteProcessMemory", "ptr", proc, "ptr", remote, "ptr", buf
                  , "uptr", bytes, "ptr", 0)
            throw Error("WriteProcessMemory failed, error " A_LastError)

        loadLib := DllCall("GetProcAddress"
                         , "ptr", DllCall("GetModuleHandle", "str", "kernel32.dll", "ptr")
                         , "astr", "LoadLibraryW", "ptr")
        if !loadLib
            throw Error("LoadLibraryW not found")

        thread := DllCall("CreateRemoteThread", "ptr", proc, "ptr", 0, "uptr", 0
                        , "ptr", loadLib, "ptr", remote, "uint", 0, "ptr", 0, "ptr")
        if !thread
            throw Error("CreateRemoteThread failed, error " A_LastError)

        ; Bounded wait. A payload whose DllMain blocks must not hang the tray app.
        if (DllCall("WaitForSingleObject", "ptr", thread, "uint", 5000) != 0)
            throw Error("payload did not initialise within 5s")

        okAll := INJ_ModuleBase(pid, INJ_DLL_NAME) != 0
        if !okAll
            throw Error("LoadLibraryW returned but the module is not listed")
    } catch as e {
        INJ_LastError := e.Message
    }

    if thread
        DllCall("CloseHandle", "ptr", thread)
    if remote
        DllCall("VirtualFreeEx", "ptr", proc, "ptr", remote, "uptr", 0
              , "uint", MEM_RELEASE)
    DllCall("CloseHandle", "ptr", proc)
    return okAll
}

; ====================================================================== eject =
; The payload must survive being unloaded at any moment: the user can toggle
; this off, and explorer restarts on its own. Unhook in DllMain/DLL_PROCESS_DETACH.
INJ_Eject() {
    global INJ_DLL_NAME, INJ_LastError
    static RIGHTS := 0x0002 | 0x0008 | 0x0010 | 0x0020 | 0x0400

    INJ_LastError := ""
    pid := INJ_TaskbarPid()
    if !pid
        return true                      ; no taskbar, nothing is loaded

    base := INJ_ModuleBase(pid, INJ_DLL_NAME)
    if !base
        return true

    proc := DllCall("OpenProcess", "uint", RIGHTS, "int", 0, "uint", pid, "ptr")
    if !proc {
        INJ_LastError := "OpenProcess failed, error " A_LastError
        return false
    }

    thread := 0, gone := false
    try {
        freeLib := DllCall("GetProcAddress"
                         , "ptr", DllCall("GetModuleHandle", "str", "kernel32.dll", "ptr")
                         , "astr", "FreeLibrary", "ptr")
        thread := DllCall("CreateRemoteThread", "ptr", proc, "ptr", 0, "uptr", 0
                        , "ptr", freeLib, "ptr", base, "uint", 0, "ptr", 0, "ptr")
        if !thread
            throw Error("CreateRemoteThread failed, error " A_LastError)
        DllCall("WaitForSingleObject", "ptr", thread, "uint", 5000)
        gone := INJ_ModuleBase(pid, INJ_DLL_NAME) = 0
        if !gone
            throw Error("module still loaded after FreeLibrary")
    } catch as e {
        INJ_LastError := e.Message
    }

    if thread
        DllCall("CloseHandle", "ptr", thread)
    DllCall("CloseHandle", "ptr", proc)
    return gone
}

; ===================================================================== status =
; Shaped like TB_Status: a single human-readable line for the settings page,
; so the GUI never has to assemble one itself.
INJ_Status() {
    global INJ_DLL_NAME, INJ_LastError
    pid := INJ_TaskbarPid()
    if !pid
        return "explorer not found - taskbar restarting?"
    if INJ_ModuleBase(pid, INJ_DLL_NAME)
        return "active in explorer.exe (pid " pid ")"
    return INJ_LastError ? ("not loaded - " INJ_LastError) : "not loaded"
}

INJ_FullPath(path) {
    buf := Buffer(520 * 2, 0)
    len := DllCall("GetFullPathNameW", "str", path, "uint", 520, "ptr", buf
                 , "ptr", 0, "uint")
    return len ? StrGet(buf, "UTF-16") : path
}

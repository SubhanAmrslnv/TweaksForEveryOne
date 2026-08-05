import re

with open('src/WindowTweaks.ahk', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Remove TaskbarCore include and init
content = re.sub(r'(?m)^#Include TaskbarCore\.ahk\n', '', content)
content = re.sub(r'(?m)^TB_OnNotify := Notify\nTB_OnLog    := Log\nLastTb      := TbKey\(\)\nTB_Rescan\(\)\nTB_Apply\(true\)\nSetTimer\(TaskbarTick, 3000\)\nOnMessage\(0x007E, DisplayChange\)        ; WM_DISPLAYCHANGE\n', '', content)

# 2. Update LoadSettings
load_settings_replacement = '''    RestoreEnabled := IniStr("memory", "enabled", "1") = "1"
    EP_Style := "Win11"
    try EP_Style := RegRead("HKCU\\\\Software\\\\ExplorerPatcher", "TbStyle") == 1 ? "Win10" : "Win11"
    EP_IconSize := "Large"
    try EP_IconSize := RegRead("HKCU\\\\Software\\\\ExplorerPatcher", "Tb10SmallBtn") == 1 ? "Small" : "Large"
    ; A corrupt INI must not stop the program from starting.
    if (SNAP_DISTANCE < 1 || SNAP_DISTANCE > 300)'''

content = re.sub(
    r'    RestoreEnabled := IniStr\("memory", "enabled", "1"\) = "1".*?    if \(SNAP_DISTANCE < 1 \|\| SNAP_DISTANCE > 300\)',
    lambda m: load_settings_replacement, content, flags=re.DOTALL
)

# 3. Update SaveSettings
save_settings_replacement = '''    try IniWrite(RestoreEnabled ? 1 : 0, INI, "memory", "enabled")
    try RegWrite(EP_Style == "Win10" ? 1 : 0, "REG_DWORD", "HKCU\\\\Software\\\\ExplorerPatcher", "TbStyle")
    try RegWrite(EP_IconSize == "Small" ? 1 : 0, "REG_DWORD", "HKCU\\\\Software\\\\ExplorerPatcher", "Tb10SmallBtn")
}'''

content = re.sub(
    r'    try IniWrite\(RestoreEnabled \? 1 : 0, INI, "memory", "enabled"\).*?}',
    lambda m: save_settings_replacement, content, flags=re.DOTALL
)

# 4. Update BuildTray
content = re.sub(r'(?m)^    m\.Add\("Restore taskbar`tWin\+Alt\+0", \(\*\) => RestoreTaskbar\(\)\)\n    m\.Add\(\)\n', '', content)

# 5. Update BuildWin globals
content = re.sub(r'global RestoreEnabled, TB_HEIGHTS, TB_Height, TB_Width, TB_IconSize, TB_AllowClip, TB_CropPrimary', 'global RestoreEnabled, EP_Style, EP_IconSize', content)

# 6. Update Taskbar Page
taskbar_page_replacement = '''    ; ---- Taskbar
    pg := CreatePage("Taskbar")
    Head(pg, CW, FG, "Taskbar settings")
    Sub(pg, CW, cSub, "Requires ExplorerPatcher. Win10 style enables responsive small icons.", "xm y+10")
    
    Lbl(pg, FG, "Taskbar Style", "xm y+16")
    C["epStyle"] := pg.AddDropDownList("x170 yp-3 w100 Choose " (EP_Style=="Win10" ? 1 : 2), ["Win10", "Win11"])
    Sub(pg, 220, cSub, "Win10 supports small icons", "x+16 yp+3")
    
    Lbl(pg, FG, "Icon Size", "xm y+16")
    C["epIconSize"] := pg.AddDropDownList("x170 yp-3 w100 Choose " (EP_IconSize=="Small" ? 1 : 2), ["Small", "Large"])
    
    b2 := pg.AddButton("xm y+24 w150 h30", "Restart Explorer")
    b2.OnEvent("Click", (*) => RestartExplorer())
    Sub(pg, CW, cSub, "Explorer must be restarted to apply taskbar style changes.", "xm y+16")
    Pages["Taskbar"] := pg'''

content = re.sub(
    r'    ; ---- Taskbar.*?Pages\["Taskbar"\] := pg',
    lambda m: taskbar_page_replacement, content, flags=re.DOTALL
)

# 7. Update Event Loop in BuildWin
event_loop_replacement = '''    for key, ctl in C {
        if (key == "epStyle" || key == "epIconSize")
            ctl.OnEvent("Change", (*) => ApplyUi())
        else if InStr(ctl.Type, "CheckBox")'''

content = re.sub(
    r'    for key, ctl in C {.*?else if InStr\(ctl\.Type, "CheckBox"\)',
    lambda m: event_loop_replacement, content, flags=re.DOTALL
)

# 8. Remove RefreshStatus calls
content = re.sub(r'(?m)^    RefreshStatus\(\)\n', '', content)
content = re.sub(r'(?m)^    if \(name == "Taskbar"\)\n        RefreshStatus\(\)\n', '', content)
content = re.sub(r'(?m)^        RefreshStatus\(\)\n', '', content)

# 9. Update ApplyUi globals
content = re.sub(r'global TB_HEIGHTS, TB_Height, TB_Width, TB_IconSize, TB_AllowClip, TB_CropPrimary', 'global EP_Style, EP_IconSize', content)

# 10. Update ApplyUi vars
applyui_vars_replacement = '''        RestoreEnabled := C["mem"].Value

        EP_Style       := C["epStyle"].Text
        EP_IconSize    := C["epIconSize"].Text

        SNAP_DISTANCE  := Integer(Clamp(NumOr(C["dist"].Value, SNAP_DISTANCE), 1, 300))'''

content = re.sub(
    r'        RestoreEnabled := C\["mem"\].Value.*?        SNAP_DISTANCE  := Integer\(Clamp\(NumOr\(C\["dist"\].Value, SNAP_DISTANCE\), 1, 300\)\)',
    lambda m: applyui_vars_replacement, content, flags=re.DOTALL
)

# 11. Remove TB_ specific logic in ApplyUi
content = re.sub(
    r'        global LastTb.*?        if \(TbKey\(\) != LastTb\).*?            RebuildTaskbar\(\)\n',
    '', content, flags=re.DOTALL
)

# 12. Replace all TB helper functions and add RestartExplorer
tb_helpers_regex = r'IsHeight\(val\).*?RefreshStatus\(\) {.*?}'
restart_explorer = '''RestartExplorer() {
    RunWait('taskkill /f /im explorer.exe', , "Hide")
    Run "explorer.exe"
}'''
content = re.sub(tb_helpers_regex, lambda m: restart_explorer, content, flags=re.DOTALL)

# 13. Remove hotkeys from msgbox
content = re.sub(r'  \. "Win\+Alt\+Up`tTaskbar taller`n"\n  \. "Win\+Alt\+Down`tTaskbar shorter`n"\n  \. "Win\+Alt\+0`tRestore taskbar`n`n"\n', '', content)

# 14. Remove taskbar hotkeys and tick
taskbar_hotkeys_regex = r'#!Up::   StepHeight\(\+1\).*?TaskbarTick\(\) {.*?}'
content = re.sub(taskbar_hotkeys_regex, '', content, flags=re.DOTALL)

with open('src/WindowTweaks.ahk', 'w', encoding='utf-8') as f:
    f.write(content)
print("Done")

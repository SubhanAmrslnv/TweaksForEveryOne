<#
.SYNOPSIS
    Structural checks for the WindowTweaks module split.

.DESCRIPTION
    This project has no build system, no test runner and no CI. The split of
    src\WindowTweaks.ahk into modules is therefore verified structurally, by
    the checks below, plus the manual smoke tests recorded per phase.

    Run after every phase:

        powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Check-Split.ps1

    Capture the reference artifacts ONCE, before the first .ahk moves:

        .\scripts\Check-Split.ps1 -Baseline

    Checks:
      1  Parse         AHK parses the whole program (no hooks/timers installed)
      2  Motion proof  no code line was lost, gained or altered by a move
      3  Default ini   a fresh settings.ini matches the pre-split reference
      4  Timer drift   every SetTimer target is stopped by TEARDOWN_SPEC
      5  HotIf bracket every #HotIf a module opens, it closes
      6  Case clash    no two globals/functions differ only by case
      7  Hotkey clash  no hotkey is bound twice in the same #HotIf context
      8  Init order    nothing is armed before the state it reads is assigned

    Check 3 actually launches the program, so it is opt-in: #SingleInstance
    Force means running it would kill the copy you have open. Pass -IniCheck.

.NOTES
    Writes only under build\refs\ and the system temp directory.
#>
[CmdletBinding()]
param(
    # Capture the reference artifacts instead of comparing against them.
    [switch]$Baseline,
    # Include check 3, which launches the program briefly (see above).
    [switch]$IniCheck,
    # Print every differing line rather than the first 40.
    [switch]$Full
)

$ErrorActionPreference = 'Stop'

$repo    = Split-Path $PSScriptRoot -Parent
$srcDir  = Join-Path $repo 'src'
$entry   = Join-Path $srcDir 'WindowTweaks.ahk'
$refDir  = Join-Path $repo 'build\refs'
$ahkExe  = Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey64.exe'

$script:fail = 0
$script:skip = 0

function Ok   ($n, $m) { Write-Host ("  [ OK ]  {0,-14} {1}" -f $n, $m) -ForegroundColor Green }
function Bad  ($n, $m) { Write-Host ("  [FAIL]  {0,-14} {1}" -f $n, $m) -ForegroundColor Red;    $script:fail++ }
function Skip ($n, $m) { Write-Host ("  [skip]  {0,-14} {1}" -f $n, $m) -ForegroundColor DarkGray; $script:skip++ }
function Note ($m)     { Write-Host "          $m" -ForegroundColor DarkGray }

# UTF-8 with NO BOM. AutoHotkey v2 reads a BOM-less .ahk as UTF-8; PowerShell's
# Set-Content/Out-File would write UTF-16LE (fails to load) or UTF-8-with-BOM.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function ReadText ($p) { [System.IO.File]::ReadAllText($p) }
function WriteText ($p, $t) { [System.IO.File]::WriteAllText($p, $t, $utf8NoBom) }

# The program's own .ahk files. test_*.ahk are standalone harnesses.
function ProgramFiles {
    Get-ChildItem $srcDir -Filter '*.ahk' -File |
        Where-Object { $_.Name -notlike 'test_*' } |
        Sort-Object Name
}

Write-Host "`nCheck-Split - structural checks for the module split" -ForegroundColor Cyan
Write-Host "Repo: $repo`n" -ForegroundColor DarkGray

$files = @(ProgramFiles)
if (-not $files) { throw "No .ahk files found in $srcDir" }
Note ("{0} modules: {1}" -f $files.Count, (($files.Name) -join ', '))
Write-Host ''

New-Item -ItemType Directory -Path $refDir -Force | Out-Null

# ===========================================================================
# Shared: resolve the #Include graph into one ordered list of (file, line)
# ===========================================================================
# AHK resolves a relative #Include against the including file's directory.
# Every #Include in this project is a bare filename in src\, so this is simple -
# but it must follow nested includes (StealthPanic.ahk includes its config).
function ResolveIncludes {
    $seen  = @{}
    $out   = New-Object System.Collections.Generic.List[object]
    function Walk ($path) {
        $full = [System.IO.Path]::GetFullPath($path)
        if ($seen.ContainsKey($full)) { return }   # AHK ignores a repeat include
        $seen[$full] = $true
        if (-not (Test-Path $full)) {
            Bad 'parse' "#Include target does not exist: $full"
            return
        }
        $name = Split-Path $full -Leaf
        $n = 0
        foreach ($line in ([System.IO.File]::ReadAllLines($full))) {
            $n++
            if ($line -match '^\s*#Include(?:Again)?\s+(?:\*i\s+)?["'']?([^"''<>]+?)["'']?\s*$') {
                $target = $matches[1].Trim()
                if ($target -notmatch '^[A-Za-z]:|^\\\\') {
                    $target = Join-Path (Split-Path $full -Parent) $target
                }
                Walk $target
                continue
            }
            $out.Add([pscustomobject]@{ File = $name; Line = $n; Text = $line })
        }
    }
    Walk $entry
    return $out
}

$stream = ResolveIncludes

# ===========================================================================
# 1. Parse check
# ===========================================================================
# AHK 2.0 has no /validate (that is 2.1+). The documented substitute: copy the
# sources aside, prepend ExitApp to the entry file, run with /ErrorStdOut. AHK
# parses the ENTIRE script before executing anything, so a load-time error is
# reported, and ExitApp stops it before a single hook, timer or tray icon is
# installed. Exit code 0 with no output means it parses.
if (-not (Test-Path $ahkExe)) {
    Skip 'parse' "AutoHotkey64.exe not found at $ahkExe"
} else {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("wt-parse-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        foreach ($f in $files) { Copy-Item $f.FullName (Join-Path $tmp $f.Name) -Force }
        $entryCopy = Join-Path $tmp 'WindowTweaks.ahk'
        WriteText $entryCopy ("ExitApp`r`n" + (ReadText $entryCopy))

        $so = Join-Path $tmp 'out.txt'
        $se = Join-Path $tmp 'err.txt'
        $p  = Start-Process -FilePath $ahkExe -ArgumentList '/ErrorStdOut', "`"$entryCopy`"" `
                            -NoNewWindow -Wait -PassThru `
                            -RedirectStandardOutput $so -RedirectStandardError $se
        # Empty output IS the success case here, and it is a trap: Get-Content
        # -Raw on an empty file emits AutomationNull - nothing at all, not $null
        # - so even [string](...) casts to $null and .Trim() throws. Only string
        # interpolation reliably turns "no output" into "".
        $msg = ("$(Get-Content $so -Raw -EA SilentlyContinue)" +
                "$(Get-Content $se -Raw -EA SilentlyContinue)").Trim()
        if ($p.ExitCode -eq 0 -and -not $msg) {
            Ok 'parse' "all $($files.Count) modules parse"
        } else {
            Bad 'parse' "exit $($p.ExitCode)"
            if ($msg) { $msg -split "`r?`n" | Select-Object -First 15 | ForEach-Object { Note $_ } }
        }
    } finally {
        Remove-Item $tmp -Recurse -Force -EA SilentlyContinue
    }
}

# ===========================================================================
# 2. Motion proof
# ===========================================================================
# The single most valuable check in this file. Take every CODE line of the
# resolved include stream, sort, and compare against the reference captured
# before the split began. A pure code-motion commit must not change that set:
# a line that moved from WindowTweaks.ahk to WindowCommands.ahk sorts to the
# same place, so the set is identical.
#
# Excluded from the set, because a split legitimately adds them:
#   blank lines, full-line comments (section banners), #Include, #HotIf.
# #HotIf is covered by check 5 instead, and #Include by check 1.
#
# Catches in one shot: a dropped line, a duplicated line, a PowerShell
# re-encode, a CRLF flip, a mangled emoji, a reflowed continuation block.
function CodeLines ($s) {
    $s | Where-Object {
        $t = $_.Text.Trim()
        $t -ne '' -and
        $t -notmatch '^;' -and
        $t -notmatch '^#Include' -and
        $t -notmatch '^#HotIf'
    } | ForEach-Object { $_.Text.TrimEnd() } | Sort-Object
}

$codeRef = Join-Path $refDir 'codelines.txt'
$lines   = @(CodeLines $stream)

if ($Baseline) {
    WriteText $codeRef (($lines -join "`r`n") + "`r`n")
    Ok 'motion' "baseline captured: $($lines.Count) code lines -> build\refs\codelines.txt"
} elseif (-not (Test-Path $codeRef)) {
    Skip 'motion' "no baseline; run with -Baseline before the first move"
} else {
    $ref = @([System.IO.File]::ReadAllLines($codeRef) | Where-Object { $_ -ne '' })
    $d   = Compare-Object -ReferenceObject $ref -DifferenceObject $lines
    if (-not $d) {
        Ok 'motion' "$($lines.Count) code lines, byte-identical to baseline"
    } else {
        $lost   = @($d | Where-Object SideIndicator -eq '<=')
        $gained = @($d | Where-Object SideIndicator -eq '=>')
        Bad 'motion' "$($lost.Count) line(s) lost, $($gained.Count) gained (was $($ref.Count), now $($lines.Count))"
        Note 'If this commit is NOT pure code motion, re-run with -Baseline to re-anchor.'
        $show = if ($Full) { [int]::MaxValue } else { 20 }
        $lost   | Select-Object -First $show | ForEach-Object { Write-Host "          - $($_.InputObject)" -ForegroundColor DarkRed }
        $gained | Select-Object -First $show | ForEach-Object { Write-Host "          + $($_.InputObject)" -ForegroundColor DarkYellow }
    }
}

# ===========================================================================
# 3. Default settings.ini round-trip
# ===========================================================================
# The strongest end-to-end check, and the guard over the whole FEATURE_SPEC
# migration: if the registry writes a different default, a different section,
# or drops a key, this catches it. Opt-in because it really runs the program
# and #SingleInstance Force would kill the copy you have open.
$iniRef = Join-Path $refDir 'settings.default.ini'
if (-not $IniCheck -and -not $Baseline) {
    Skip 'default-ini' 'pass -IniCheck to run (launches the program briefly)'
} elseif (-not (Test-Path $ahkExe)) {
    Skip 'default-ini' 'AutoHotkey64.exe not found'
} else {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("wt-ini-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        foreach ($f in $files) { Copy-Item $f.FullName (Join-Path $tmp $f.Name) -Force }
        # A_ScriptDir is the entry file's directory, so it writes settings.ini here.
        $p = Start-Process -FilePath $ahkExe -ArgumentList "`"$(Join-Path $tmp 'WindowTweaks.ahk')`"" -PassThru
        Start-Sleep -Seconds 3

        # It MUST exit gracefully. Settings are written by a 700 ms debounced
        # one-shot (SaveSettings -> WriteSettings) and a fresh run has nothing to
        # debounce, so the only full write is the direct WriteSettings() call in
        # Bye(). Bye() is an OnExit handler, and Stop-Process -Force skips it -
        # which produced a 4-line baseline instead of a complete one.
        # taskkill without /F posts WM_CLOSE to the script's main window, which
        # AHK turns into a normal exit and OnExit handlers run.
        & taskkill.exe /PID $p.Id 2>&1 | Out-Null
        if (-not $p.WaitForExit(8000)) {
            Bad 'default-ini' 'the program did not exit within 8s of WM_CLOSE'
            try { Stop-Process -Id $p.Id -Force -EA SilentlyContinue } catch {}
        }
        Start-Sleep -Milliseconds 400

        $made = Join-Path $tmp 'settings.ini'
        if (-not (Test-Path $made)) {
            Bad 'default-ini' 'the program did not write a settings.ini'
        } elseif ($Baseline) {
            Copy-Item $made $iniRef -Force
            Ok 'default-ini' "baseline captured -> build\refs\settings.default.ini"
        } elseif (-not (Test-Path $iniRef)) {
            Skip 'default-ini' 'no baseline; run with -Baseline'
        } else {
            # Order within a section is not meaningful; content is.
            $a = @([System.IO.File]::ReadAllLines($iniRef) | Where-Object { $_.Trim() } | Sort-Object)
            $b = @([System.IO.File]::ReadAllLines($made)   | Where-Object { $_.Trim() } | Sort-Object)
            $d = Compare-Object $a $b
            if (-not $d) {
                Ok 'default-ini' "$($b.Count) lines, identical to the pre-split reference"
            } else {
                Bad 'default-ini' "$($d.Count) differing line(s)"
                $d | Select-Object -First 30 | ForEach-Object {
                    $sym = if ($_.SideIndicator -eq '<=') { '-' } else { '+' }
                    Note "$sym $($_.InputObject)"
                }
            }
        }
    } finally {
        Remove-Item $tmp -Recurse -Force -EA SilentlyContinue
    }
}

# ===========================================================================
# 4. Timer drift
# ===========================================================================
# Bye() used to name 25 timers by hand and missed fourteen of them. Once
# TEARDOWN_SPEC exists, every repeating SetTimer target must appear as a
# phase-1 row. Negative periods are one-shots and stop themselves.
$setTimerTargets = @{}
foreach ($e in $stream) {
    if ($e.Text -match 'SetTimer\(\s*([A-Za-z_]\w*)\s*,\s*(-?\d+|-\w)') {
        $fn = $matches[1]; $period = $matches[2]
        # A negative literal period is a one-shot; 0 is a cancel.
        if ($period -notmatch '^-' -and $period -ne '0') { $setTimerTargets[$fn] = $e.File }
    }
}
$teardown = @{}
$inSpec = $false
foreach ($e in $stream) {
    if ($e.Text -match '^\s*global\s+TEARDOWN_SPEC\s*:=') { $inSpec = $true }
    if ($inSpec) {
        if ($e.Text -match 'TD\(\s*1\s*,\s*"[^"]*"\s*,\s*([A-Za-z_]\w*)') { $teardown[$matches[1]] = $true }
        if ($e.Text -match '^\s*\]\s*$') { $inSpec = $false }
    }
}
if (-not $teardown.Count) {
    Skip 'timer-drift' 'TEARDOWN_SPEC does not exist yet (lands in phase 3)'
} else {
    $missing = @($setTimerTargets.Keys | Where-Object { -not $teardown.ContainsKey($_) } | Sort-Object)
    if (-not $missing) {
        Ok 'timer-drift' "all $($setTimerTargets.Count) repeating timers are stopped by TEARDOWN_SPEC"
    } else {
        Bad 'timer-drift' "$($missing.Count) repeating timer(s) with no phase-1 teardown row"
        $missing | ForEach-Object { Note "$_  (armed in $($setTimerTargets[$_]))" }
    }
}

# ===========================================================================
# 5. #HotIf bracket balance
# ===========================================================================
# #HotIf is a POSITIONAL directive, not a scope, and it bleeds across #Include
# boundaries: a module that ends with an open #HotIf silently applies that
# context to the first hotkeys of the next included file. Every module that
# opens a context must close it with a bare #HotIf.
$unbalanced = @()
foreach ($f in $files) {
    $ls = [System.IO.File]::ReadAllLines($f.FullName)
    $open = 0; $last = ''
    foreach ($l in $ls) {
        if ($l -match '^\s*#HotIf\s*$')      { $open = 0;      $last = 'bare' }
        elseif ($l -match '^\s*#HotIf\s+\S') { $open = 1;      $last = 'expr' }
    }
    if ($open -ne 0) { $unbalanced += "$($f.Name) ends with an OPEN #HotIf" }
}
if (-not $unbalanced) {
    Ok 'hotif' 'every module closes the contexts it opens'
} else {
    Bad 'hotif' "$($unbalanced.Count) module(s) leak a #HotIf context"
    $unbalanced | ForEach-Object { Note $_ }
}

# ===========================================================================
# 6. Case collision
# ===========================================================================
# AHK identifiers are case-insensitive SCRIPT-WIDE, not per file - so a
# "global Grid" in one module and a "Grid()" in another is a load error with a
# confusing message far from the cause. This is the check that would have
# caught the original TUNE map vs Tune() collision, and it gets more likely
# with 23 files because each module shows only its own names.
$names = @{}
function AddName ($n, $kind, $file) {
    $k = $n.ToLowerInvariant()
    if (-not $names.ContainsKey($k)) { $names[$k] = New-Object System.Collections.Generic.List[string] }
    $names[$k].Add("$kind $n ($file)")
}
foreach ($f in $files) {
    foreach ($l in [System.IO.File]::ReadAllLines($f.FullName)) {
        if ($l -match '^global\s+(.+)$') {
            # "global Win := "", Pages := Map(), CurPage := """ -> three names
            foreach ($part in ($matches[1] -split ',')) {
                if ($part -match '^\s*([A-Za-z_]\w*)') { AddName $matches[1] 'global' $f.Name }
            }
        } elseif ($l -match '^([A-Za-z_]\w*)\s*\(') {
            AddName $matches[1] 'func' $f.Name
        }
    }
}
$clashes = @($names.GetEnumerator() | Where-Object {
    ($_.Value | ForEach-Object { ($_ -split ' ')[1] } | Sort-Object -Unique).Count -gt 1
})
if (-not $clashes) {
    Ok 'case-clash' "$($names.Count) distinct identifiers, no case-only collisions"
} else {
    Bad 'case-clash' "$($clashes.Count) identifier(s) differ only by case"
    $clashes | ForEach-Object { Note (($_.Value | Sort-Object -Unique) -join '  vs  ') }
}

# ===========================================================================
# 7. Duplicate hotkey bindings
# ===========================================================================
# Once bindings live in four files you can no longer see them all at once.
# A hotkey bound twice in the SAME #HotIf context is a silent override - the
# later definition wins and the earlier one simply never fires.
$bindings = @{}
foreach ($f in $files) {
    $ctx = ''
    $n = 0
    foreach ($l in [System.IO.File]::ReadAllLines($f.FullName)) {
        $n++
        if ($l -match '^\s*#HotIf\s*$')      { $ctx = ''; continue }
        if ($l -match '^\s*#HotIf\s+(.+)$')  { $ctx = $matches[1].Trim(); continue }
        # Column-0 "<hotkey>::" and not a hotstring (":*:abc::") or a comment.
        if ($l -match '^([^\s;:][^:]*)::' ) {
            $key = "$ctx || $($matches[1].Trim())"
            if (-not $bindings.ContainsKey($key)) { $bindings[$key] = New-Object System.Collections.Generic.List[string] }
            $bindings[$key].Add("$($f.Name):$n")
        }
    }
}
$dupes = @($bindings.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 })
if (-not $dupes) {
    Ok 'hotkey-dupe' "$($bindings.Count) bindings, none defined twice in one context"
} else {
    Bad 'hotkey-dupe' "$($dupes.Count) hotkey(s) bound more than once in the same context"
    $dupes | ForEach-Object { Note "$($_.Key)   ->   $($_.Value -join ', ')" }
}

# ===========================================================================
# 8. Init order
# ===========================================================================
# One bug class, INVISIBLE when running from src\ and reproducible on end-user
# machines. A top-level "global X := ..." only runs when the auto-execute thread
# reaches that line - but hotkeys are live from load time, and a registered hook
# fires the moment the OS has something to deliver. State declared thousands of
# lines further down is therefore unassigned for the whole of startup.
#
# Both halves of it shipped: "This global variable has not been assigned a
# value" on PushedBackWindows (read by ShellEvent's HSHELL_WINDOWDESTROYED
# cleanup, which RegisterShellHook() armed ~3,200 lines above the declaration)
# and on CarouselActive (read by a #HotIf, evaluated on any Alt/Tab/Esc press).
# It reproduced on a fresh install, where the setup window closes as the app
# starts, and almost never on a quiet desktop - which is exactly why it needs a
# checker rather than testing.
#
#   8a  every global named in a #HotIf must be initialised before the first
#       top-level call in the entry file, i.e. up in the flag/state block
#   8b  no top-level call may sit between the first and last top-level global
#       initialiser. Anything that arms a timer or registers a hook belongs in
#       the deferred-init block at the bottom of WindowTweaks.ahk
#
# The allowlist is the four calls the entry file documents as safe above the
# deferred block (each touches only globals declared above it) plus the pure
# registrations, which run nothing at the point they are reached.
$allowedTopCalls = @('LoadSettings', 'RotateLog', 'SyncTray', 'BuildTray',
                     'WriteLog', 'OnMessage', 'OnExit')
$entryName = Split-Path $entry -Leaf

# A top-level CALL, not a definition: "Name(args)" at column 0 with nothing
# after the closing paren. "Name(a, b) => expr" is a fat-arrow definition and
# "Name(a, b) {" opens a body - neither may match.
$globalInit  = @{}
$topCalls    = New-Object System.Collections.Generic.List[object]
$firstGlobal = 0
$lastGlobal  = 0
$idx = 0
foreach ($e in $stream) {
    $idx++
    $t = $e.Text
    if ($t -match '^global\s') {
        # "global HotCornerTL := "None", HotCornerTR := "Task View"" -> two names
        foreach ($m in [regex]::Matches($t, '([A-Za-z_]\w*)\s*:=')) {
            if ($firstGlobal -eq 0) { $firstGlobal = $idx }
            $lastGlobal = $idx
            $k = $m.Groups[1].Value.ToLowerInvariant()
            if (-not $globalInit.ContainsKey($k)) {
                $globalInit[$k] = [pscustomobject]@{
                    Name = $m.Groups[1].Value; Idx = $idx; Where = "$($e.File):$($e.Line)" }
            }
        }
    } elseif ($t -match '^([A-Za-z_]\w*)\s*\(.*\)\s*(;.*)?$' -and $t -notmatch '=>') {
        $topCalls.Add([pscustomobject]@{
            Name = $matches[1]; Idx = $idx; File = $e.File; Where = "$($e.File):$($e.Line)" })
    }
}

# 8a. The boundary is the first top-level call in the ENTRY file - startup work
# begins there. Module-level registrations sort ahead of the entry file's own
# globals (an #Include splices the module in above them), so they cannot be it.
$entryCalls = @($topCalls | Where-Object { $_.File -eq $entryName } | Sort-Object Idx)
$firstEntryCall = if ($entryCalls.Count) { $entryCalls[0].Idx } else { [int]::MaxValue }

# -match, not -notmatch: only -match populates $Matches.
$initBad = @()
foreach ($e in $stream) {
    if ($e.Text -match '^\s*#HotIf\s+(\S.*)$') {
        foreach ($m in [regex]::Matches($matches[1], '[A-Za-z_]\w*')) {
            $k = $m.Value.ToLowerInvariant()
            if (-not $globalInit.ContainsKey($k)) { continue }  # a function, or a built-in
            $g = $globalInit[$k]
            if ($g.Idx -gt $firstEntryCall) {
                $initBad += ("{0} is read by #HotIf at {1}:{2} but assigned at {3}, after startup begins - move the declaration up to the flag/state block" -f `
                             $g.Name, $e.File, $e.Line, $g.Where)
            }
        }
    }
}
$initBad = @($initBad | Sort-Object -Unique)

# 8b. Anything not on the allowlist, sitting between the first and last
# top-level global initialiser, is armed while later initialisers have not run.
$orderBad = @()
foreach ($c in $topCalls) {
    if ($allowedTopCalls -contains $c.Name) { continue }
    if ($c.Idx -gt $firstGlobal -and $c.Idx -lt $lastGlobal) {
        $orderBad += ("{0}() at {1} runs while later 'global X := ...' initialisers have not - move it to the deferred-init block at the bottom of {2}, or add it to `$allowedTopCalls in this check with a reason" -f `
                      $c.Name, $c.Where, $entryName)
    }
}

if (-not $initBad -and -not $orderBad) {
    Ok 'init-order' "$($globalInit.Count) top-level globals, $($topCalls.Count) top-level calls, nothing armed early"
} else {
    Bad 'init-order' "$($initBad.Count + $orderBad.Count) init-order violation(s)"
    $initBad  | ForEach-Object { Note $_ }
    $orderBad | ForEach-Object { Note $_ }
}

# ===========================================================================
Write-Host ''
if ($script:fail) {
    Write-Host "  $($script:fail) check(s) FAILED" -ForegroundColor Red
    Write-Host ''
    exit 1
}
Write-Host "  All checks passed$(if ($script:skip) { " ($($script:skip) skipped)" })" -ForegroundColor Green
Write-Host ''
exit 0

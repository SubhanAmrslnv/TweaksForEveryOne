<#
.SYNOPSIS
    Authenticode-signs and timestamps the published Window Tweaks binary.

.DESCRIPTION
    Signing is the single most effective fix for the antivirus false positives this project hits.
    See docs/ANTIVIRUS.md for why, and for how to obtain a certificate.

    This script does NOT obtain a certificate for you. It signs with one you already have, in
    whichever of the three supported forms:

      -Thumbprint    a certificate already installed in your certificate store, including one whose
                     private key lives on a hardware token (the usual case for a modern OV cert)
      -PfxPath       a .pfx file (older certs, and test certs)
      -Dlib/-Dmdf    a signtool "digest library" plus its metadata file - this is how Azure Trusted
                     Signing works, where the key never leaves Microsoft's service

    TIMESTAMPING IS NOT OPTIONAL and this script will not skip it. An untimestamped signature stops
    being valid the moment the certificate expires, so every copy of the app you ever shipped
    becomes unsigned - and therefore flagged again - on that date. A timestamped signature stays
    valid for the life of the timestamp authority's certificate.

.PARAMETER Path
    File or directory to sign. Defaults to the published output. Directories are searched for
    WindowTweaks.exe and WindowTweaks.dll.

.PARAMETER Thumbprint
    SHA1 thumbprint of a certificate in Cert:\CurrentUser\My (run with -List to see candidates).

.PARAMETER PfxPath
    Path to a .pfx. You will be prompted for its password; it is never written to disk or history.

.PARAMETER Dlib
    Path to the signing digest library (Azure Trusted Signing).

.PARAMETER Dmdf
    Path to the metadata JSON that accompanies -Dlib.

.PARAMETER List
    List code-signing certificates available in your store and exit.

.EXAMPLE
    .\build\Sign.ps1 -List
    .\build\Sign.ps1 -Thumbprint A1B2C3...
    .\build\Sign.ps1 -PfxPath .\mycert.pfx
    .\build\Sign.ps1 -Dlib "C:\ATS\bin\x64\Azure.CodeSigning.Dlib.dll" -Dmdf .\ats-metadata.json
#>
param (
    [string]$Path = "csharp\bin\Release\net10.0-windows",
    [string]$Thumbprint,
    [string]$PfxPath,
    [string]$Dlib,
    [string]$Dmdf,
    [switch]$List
)

$ErrorActionPreference = 'Stop'

# RFC 3161 timestamp authority. DigiCert's is free, public and does not require an account.
$TimestampUrl = 'http://timestamp.digicert.com'

# --- Locate signtool.exe ----------------------------------------------------------------------
# signtool ships with the Windows SDK, not with .NET, so it is not on PATH by default. Prefer the
# newest version found rather than hardcoding an SDK version that will age out.
function Find-SignTool {
    $cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $roots = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\bin",
        "$env:ProgramFiles\Windows Kits\10\bin"
    ) | Where-Object { $_ -and (Test-Path $_) }

    $found = foreach ($root in $roots) {
        Get-ChildItem -Path $root -Filter signtool.exe -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\x64\\' }
    }

    if (-not $found) { return $null }
    ($found | Sort-Object { $_.VersionInfo.FileVersionRaw } -Descending | Select-Object -First 1).FullName
}

# --- -List ------------------------------------------------------------------------------------
if ($List) {
    Write-Host ""
    Write-Host "Code-signing certificates in Cert:\CurrentUser\My" -ForegroundColor Cyan
    Write-Host ""

    $certs = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue
    if (-not $certs) {
        Write-Host "  none found." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  A self-signed certificate will NOT help with antivirus or SmartScreen - it has"
        Write-Host "  no chain of trust. See docs/ANTIVIRUS.md for the options that do."
        Write-Host ""
        exit 0
    }

    foreach ($c in $certs) {
        $expired = if ($c.NotAfter -lt (Get-Date)) { "  [EXPIRED]" } else { "" }
        Write-Host ("  {0}`n    subject : {1}`n    issuer  : {2}`n    expires : {3}{4}`n" -f `
            $c.Thumbprint, $c.Subject, $c.Issuer, $c.NotAfter.ToString('yyyy-MM-dd'), $expired)
    }
    exit 0
}

# --- Validate arguments -----------------------------------------------------------------------
$modes = @($Thumbprint, $PfxPath, $Dlib) | Where-Object { $_ }
if ($modes.Count -eq 0) {
    Write-Host ""
    Write-Host "No certificate specified." -ForegroundColor Yellow
    Write-Host "  Run '.\build\Sign.ps1 -List' to see what is available, then pass one of:"
    Write-Host "    -Thumbprint <sha1>      certificate from your store (incl. hardware token)"
    Write-Host "    -PfxPath <file.pfx>     certificate file"
    Write-Host "    -Dlib <dll> -Dmdf <json>  Azure Trusted Signing"
    Write-Host ""
    Write-Host "  See docs/ANTIVIRUS.md."
    Write-Host ""
    exit 1
}
if ($modes.Count -gt 1) { throw "Specify only one of -Thumbprint, -PfxPath, -Dlib." }
if ($Dlib -and -not $Dmdf) { throw "-Dlib also requires -Dmdf." }

$signtool = Find-SignTool
if (-not $signtool) {
    throw "signtool.exe not found. Install the Windows SDK (the 'Windows SDK Signing Tools' component)."
}
Write-Host "signtool: $signtool" -ForegroundColor DarkGray

# --- Collect the files to sign ----------------------------------------------------------------
# Sign the app's OWN assemblies only. Never re-sign the .NET runtime files - they are already signed
# by Microsoft and replacing that signature is both pointless and destructive.
if (-not (Test-Path $Path)) {
    throw "Path not found: $Path`nBuild first: dotnet publish .\csharp\WindowTweaks.csproj -c Release -r win-x64 --self-contained false"
}

$targets = if ((Get-Item $Path).PSIsContainer) {
    @('WindowTweaks.exe', 'WindowTweaks.dll') |
        ForEach-Object { Join-Path $Path $_ } |
        Where-Object { Test-Path $_ }
} else {
    @($Path)
}

if (-not $targets) { throw "Nothing to sign under $Path" }

Write-Host ""
Write-Host "Signing:" -ForegroundColor Cyan
$targets | ForEach-Object { Write-Host "  $_" }
Write-Host ""

# --- Build the signtool arguments -------------------------------------------------------------
# /fd sha256  file digest algorithm  (sha1 is long dead; a sha1 signature is worse than none)
# /td sha256  timestamp digest algorithm
# /tr         RFC 3161 timestamp server (/t is the obsolete Authenticode form)
$common = @('/fd', 'sha256', '/tr', $TimestampUrl, '/td', 'sha256', '/v')

$credential = @()
if ($Thumbprint) {
    $credential = @('/sha1', $Thumbprint)
}
elseif ($PfxPath) {
    if (-not (Test-Path $PfxPath)) { throw "PFX not found: $PfxPath" }

    # Read the password interactively. Never accept it as a plain parameter: it would land in the
    # shell history and in any transcript.
    $secure = Read-Host -Prompt "PFX password" -AsSecureString
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
    $credential = @('/f', $PfxPath, '/p', $plain)
}
else {
    $credential = @('/dlib', $Dlib, '/dmdf', $Dmdf)
}

# --- Sign -------------------------------------------------------------------------------------
$failed = @()
foreach ($t in $targets) {
    & $signtool sign @credential @common $t
    if ($LASTEXITCODE -ne 0) { $failed += $t }
}

# Drop the password from memory as soon as it is no longer needed.
if ($plain) { Remove-Variable plain -ErrorAction SilentlyContinue }

if ($failed) {
    Write-Host ""
    Write-Host "FAILED to sign:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  $_" }
    exit 1
}

# --- Verify ---------------------------------------------------------------------------------
# Signing reporting success is not proof the result validates. Check it, including the timestamp.
Write-Host ""
Write-Host "Verifying..." -ForegroundColor Cyan
foreach ($t in $targets) {
    $sig = Get-AuthenticodeSignature $t
    $stamp = if ($sig.TimeStamperCertificate) { 'timestamped' } else { 'NOT TIMESTAMPED' }
    $colour = if ($sig.Status -eq 'Valid' -and $sig.TimeStamperCertificate) { 'Green' } else { 'Red' }

    Write-Host ("  {0}`n    status : {1}`n    signer : {2}`n    stamp  : {3}" -f `
        (Split-Path $t -Leaf), $sig.Status, $sig.SignerCertificate.Subject, $stamp) -ForegroundColor $colour
}

Write-Host ""
Write-Host "Done. Next: upload to VirusTotal to confirm the detection is gone, and submit" -ForegroundColor Cyan
Write-Host "false-positive reports for any engine still flagging it (docs/ANTIVIRUS.md)." -ForegroundColor Cyan
Write-Host ""

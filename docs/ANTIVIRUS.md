# Antivirus false positives

Window Tweaks gets flagged by Bitdefender and other engines. It contains no malicious code. This
document explains why it happens, what has been changed in the code to reduce it, and what only you
can do — because most of the remaining fix is not code.

## The honest reality check first

**You cannot fully fix this in code.** Ranked by how much each actually moves the needle:

| Fix | Impact | Who can do it |
|---|---|---|
| **Authenticode code signing** with a real CA certificate | ~70–80% of the problem | You (costs money) |
| **Submitting false-positive reports** to each vendor | High, per-vendor, free, days to fix | You |
| **Download / usage reputation over time** | High, but slow and automatic | Nobody — it accrues |
| Assembly metadata, manifest, fewer input hooks | Real but modest | **Done, in this repo** |
| Not packing / not obfuscating | Critical — but as a thing to *avoid* | **Already correct** |

An unsigned executable that installs a global keyboard hook will always score badly on heuristics,
no matter how clean the source is. Signing is what converts "anonymous binary doing suspicious
things" into "identified publisher doing declared things".

## Why your app specifically is flagged

Nothing here is a bug. These are the behaviours your features genuinely need, and each one is also
something malware does:

| What the app does | Why it needs it | What the scanner thinks |
|---|---|---|
| `SetWindowsHookEx(WH_KEYBOARD_LL)` | double-tap Alt/Ctrl, triple-Esc, Smart Caps Lock | **Keylogger.** This is the single strongest signal. |
| `SetWindowsHookEx(WH_MOUSE_LL)` | alt-drag, grab & pan, transparency wheel, ripple, middle-click close | Input interception |
| Clipboard read/write | plain-text paste, Spotlight | Data theft |
| `SendInput` | Smart Caps Lock sends Escape; plain paste sends Ctrl+V | Input injection |
| Startup shortcut | "Start with Windows" | Persistence |
| `SetWindowPos` / `SetWindowLong` on other processes' windows | the entire point of the app | Process manipulation |
| One HTTPS request per 15 min to open-meteo.com | the taskbar clock's weather, **off by default** | Outbound network from a hooking process |
| Unsigned, previously no metadata | — | Unknown, untrusted binary |

Keyboard hook **+** clipboard **+** synthetic input **+** persistence is, on paper, the exact
fingerprint of a keylogger with exfiltration. The only thing separating your app from that
description is that it never stores or transmits anything — which a static scanner cannot see, but a
human analyst can verify in minutes.

## What has been changed in the code

All of these are honest descriptions of the app, not evasion. Hiding behaviour would make the
problem worse, not better.

1. **Four global keyboard hooks collapsed into one** (`Core/KeyboardHook.cs`). The process used to
   install four separate `WH_KEYBOARD_LL` hooks — which reads as a program determined to capture
   keystrokes. Now there is exactly one, shared by the features that need it.

2. **That hook does not exist unless a feature needs it.** It is installed on the first subscriber
   and released on the last. With the relevant features off, the process holds no keyboard hook at
   all. Previously four hooks were installed unconditionally at startup.

3. **No keystroke retention, anywhere.** Each subscriber keeps only a tap counter and a stopwatch.
   No key is stored, buffered, logged or written. This is stated in the file header as a rule to
   preserve — adding keystroke retention would make the heuristic *correct*.

4. **Full assembly identity** (`WindowTweaks.csproj`): Company, Product, Description, Copyright,
   FileVersion. A nameless binary is maximally suspicious; these are fields both a scanner and a
   user (file → Properties → Details) can read.

5. **An application manifest** (`app.manifest`) declaring `asInvoker` (the app never asks for
   admin), supported OS, and per-monitor DPI awareness.

6. **Deterministic builds** — the same source produces a byte-identical binary, so anyone can
   rebuild and confirm the shipped exe matches this source.

7. **Explicitly not packed, not obfuscated, not single-file, not trimmed, not ReadyToRun** — with the
   reasons recorded in the csproj so nobody adds them later.

## What only you can do

### 1. Sign the binary — this is the real fix

**Do not bother with a self-signed certificate.** It has no chain of trust, so it does nothing for
antivirus or SmartScreen. It is only useful inside a domain that already trusts your CA.

Current options, cheapest first:

- **Azure Trusted Signing** — around $10/month, and the cheapest legitimate route for an individual
  developer. Microsoft holds the key; you sign via a service. Check the current eligibility rules
  (identity verification is required, and there are history requirements) before committing.
- **OV (Organization Validation) certificate** — roughly $200–400/year from a CA. Requires verifying
  a legal entity.
- **EV (Extended Validation) certificate** — more expensive, but historically grants SmartScreen
  reputation immediately rather than earning it over time.

Note: since mid-2023 all code-signing private keys must live on FIPS-certified hardware (a USB token
or a cloud HSM). The old "download a .pfx and sign locally" flow no longer exists for new certs.

Once you have a certificate, `build/Sign.ps1` in this repo signs and timestamps the published
output. **Always timestamp** (`/tr <rfc3161-url> /td sha256`) — without it, your signatures stop being
valid the day the certificate expires.

Make `<Company>` in the csproj match your certificate's subject name, or the metadata and the
signature will name different publishers.

### 2. Submit false-positive reports

This is free, and vendors typically respond within a few days. Do it for every engine that flags you.

1. Upload the exe to **VirusTotal** first, so you know exactly which engines flag it and under what
   detection name. Do not skip this — you may find only one or two engines are the problem.
2. Submit to each vendor's false-positive channel:
   - **Bitdefender** — `virus_submission@bitdefender.com`, or their web submission form. State
     clearly that you are the developer and that this is a false positive.
   - **Microsoft Defender** — the Microsoft Security Intelligence file-submission portal
     (`microsoft.com/en-us/wdsi/filesubmission`), choosing "software developer" and "incorrectly
     detected".
   - Others as VirusTotal reports them.
3. Re-submit after each release. A new unsigned binary is a new unknown file; detections often
   return until you are signing consistently.

### 3. Paste this technical disclosure into every report

Analysts approve false positives much faster when the submission explains the behaviour up front.
Every claim below was verified against this source tree:

> Window Tweaks is an open-source window-management utility for Windows 11 (magnetic window
> snapping, keyboard tiling, per-window transparency, desktop animations).
>
> It triggers keylogger heuristics because it installs one low-level keyboard hook
> (`WH_KEYBOARD_LL`) to detect three keyboard gestures: a double-tap of Alt, a double-tap of Ctrl,
> and a triple-tap of Escape, plus a tap-versus-hold distinction on Caps Lock. The hook is installed
> only while one of those features is enabled by the user, and is released when they are all off.
>
> The hook does not store, buffer, log or transmit keystrokes. Each consumer retains only an integer
> tap counter and a stopwatch. Verifiable in `csharp/Core/KeyboardHook.cs` and the four subscribers.
>
> Network activity: there is **no telemetry, no update check and no analytics**. The application
> has exactly one network code path, `Core/WeatherService.cs`, which fetches current weather for
> the optional taskbar clock from the public open-meteo.com API. It is **disabled by default**,
> and even when enabled it makes no request until the user types a city name. When active it
> issues one HTTPS GET per 15 minutes and sends only that city name and coordinates. There is no
> other HTTP, socket or DNS use anywhere in the source, and nothing about the user, their input
> or their machine is ever transmitted.
>
> It makes **no Windows registry writes**.
>
> It writes exactly three filesystem paths, all under the user's own profile:
> `%APPDATA%\WindowTweaks\settings.json`, `%APPDATA%\WindowTweaks\window-positions.json`, and
> optionally a shortcut in the user's Startup folder for the "Start with Windows" option.
>
> It runs `asInvoker` and never requests elevation. It installs no service, driver, scheduled task or
> COM registration.
>
> The binary is not packed, obfuscated, trimmed or bundled as a self-extracting single file, and the
> build is deterministic — the published binary can be reproduced from source.
>
> Source: <your repository URL>

## The one deliberate compromise: weather

The taskbar clock can show current conditions, which means the app makes an outbound connection. That
genuinely weakens the profile above — "installs a global keyboard hook" and "connects to the internet"
are much worse together than apart, because that pair is the shape of a keylogger reporting home.

It is kept because it is a feature the app is for, and it is constrained so the pairing almost never
occurs in practice:

- **Off by default.** A fresh install makes no connection at all.
- **Silent until configured.** Even switched on, `WeatherService.Poll` returns before touching the
  network while the city setting is empty.
- **One request per 15 minutes**, backing off ×3 to a 15-minute cap on failure. No beaconing cadence.
- **A public API over HTTPS**, needing no key and no account, at a domain a reviewer can recognise.
- **Nothing personal is sent** — a city name the user typed, and the coordinates it resolved to.
- **One code path**, `Core/WeatherService.cs`, so the claim is auditable in a single file.

If antivirus false positives remain a problem after signing, this is the first feature to switch off
while you investigate — it is the only one whose absence changes the app's network behaviour.

## Things that will make it worse — never do these

- **Never add a packer, obfuscator or "protector."** Obfuscated code is the largest single cause of
  antivirus false positives. This will get you blacklisted, not protected.
- **Never publish as a self-contained single file.** Self-extraction at runtime looks like unpacking.
- **Never ask for admin rights in the app manifest.** Only the installer needs elevation.
- **Do not install to `%LOCALAPPDATA%` and add persistence there.** That combination is where malware
  lives; `%ProgramFiles%` is an admin-only, and therefore more trusted, location. The current
  installer already does the right thing.
- **Do not add further network access.** The weather lookup is the one exception and it is already
  a liability: outbound traffic from a process that holds input hooks is scored much more harshly
  than either behaviour alone. It is defensible only because it is off by default, silent until a
  city is set, goes to a well-known public API over HTTPS, and sends nothing but a place name.
  An "update check" would have none of those defences - and on an unsigned binary, periodic
  beaconing to a server you control is what command-and-control looks like.
- **Do not encrypt, compress or encode your own strings or resources** to hide them.

## A note on AutoHotkey

`GEMINI.md` bans AutoHotkey for this project because compiled AHK scripts are heavily flagged. That
reasoning is sound and this rewrite is the right response — but be aware that **the C# build is
flagged for a different reason**. Compiled AHK is flagged largely because the interpreter stub is
shared by real malware, so you inherit its reputation. A C# binary is flagged for its own behaviour
and its lack of a signature. Rewriting in C++ would not change that either: the keyboard hook is the
signal, not the language. Signing is what fixes it.

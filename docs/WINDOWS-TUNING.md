# Windows tuning — what it changes, and what it deliberately won't

> **This page is a worked example.** The specific numbers, hardware and policy
> findings below come from the machine this was developed on (Windows 11 25H2,
> build 26200.8246, domain-joined, Intel Core Ultra 5 125U, 60 Hz panel, 15.5 GB
> RAM). Your machine will differ — the *reasoning* is what transfers, not the
> readings. Run `scripts\Apply-Windows-Tuning.ps1` and it reports your own
> values.

Every change is in `HKCU` only. No admin rights were used, no system file, service,
scheduled task, driver or security setting was touched. Windows Update and
Microsoft Defender / Bitdefender were not modified.

**To undo everything:** run `Restore-Windows-Tuning.ps1`, then sign out and back in.
The exact prior values are recorded in `%LOCALAPPDATA%\Window Tweaks Backup\tuning-backup.json`.

---

## The main finding

Your machine had the premium feel **switched off**, not on. Someone had disabled
the animations you were asking for:

| Setting | Was | Now |
|---|---|---|
| `MinAnimate` (window open/close/minimise) | 0 — off | **1 — on** |
| `EnableTransparency` (acrylic / Mica) | 0 — off | **1 — on** |
| `TaskbarAnimations` | 0 — off | **1 — on** |
| `UserPreferencesMask` | `90 12 03 80 10` | **`9E 1E 07 80 12`** |
| `EnableAeroPeek` | 0 | **1** |

So the fix was to turn the good stuff **on**, which is the opposite of what most
"optimization" guides tell you to do.

These were applied through `SystemParametersInfo` — the documented Windows API —
rather than by hand-editing the `UserPreferencesMask` bytes. Windows recalculated
the mask itself, which is why it landed exactly on its own "best appearance"
profile. Effects enabled: menu animation, combo-box animation, smooth-scrolling
list boxes, tooltip animation, selection fade, client-area animation, and the master UI-effects switch.

## Explorer

| Setting | Now | Why |
|---|---|---|
| `LaunchTo` | This PC | Skips the Quick Access lookup on every new window |
| `SeparateProcess` | on | A hung folder window can no longer freeze the whole shell |
| `ShowRecent` / `ShowFrequent` | off | Quick Access was probing recent files, including network paths — a common cause of Explorer hanging for seconds |

**Sign out and back in** (or restart Explorer) for these three to take effect.

---

## What I did *not* do, and why

**Power mode — blocked by your domain policy.** Only the Balanced scheme exists on
this machine and `powercfg` doesn't expose the overlay verbs, so IT controls it.
You can still set it yourself: *Settings → System → Power & battery → Power mode →
Best performance*. On a 15 W Core Ultra 5 125U that costs battery life.

**Hardware-accelerated GPU scheduling — not available.** `HwSchModeSupported` is
absent, meaning this Intel driver doesn't offer it. Setting `HwSchMode` anyway
would be a blind registry write with no effect, so I skipped it.

**High-refresh-rate tuning — no headroom.** Your panel is 60 Hz
(`MaxRefreshRate 60`). Nothing to gain.

**Services and scheduled tasks — deliberately untouched.** This is a domain-joined
machine running managed Bitdefender Endpoint. Disabling background services here
risks breaking policy or security, which your own rules ruled out.

**Startup apps — already clean.** Every user-controllable entry is *already*
disabled: OneDrive, Teams, Edge auto-launch, Chrome auto-launch, LM Studio, Mem
Reduct, Simple Sticky Notes. There was nothing to gain.

---

## The real bottleneck: memory

**15.5 GB total, 3.4 GB free — 78% in use.** Windows is running 1.25 GB of Memory
Compression, which is a symptom of genuine pressure. This will cause far more
stutter than any visual setting.

Where it's going:

| App | Processes | RAM |
|---|---|---|
| Chrome | 26 | **3.3 GB** |
| Memory Compression | 1 | 1.25 GB |
| msedgewebview2 | 13 | 784 MB |
| svchost | 86 | 775 MB |
| Antigravity | 6 | 711 MB |
| devenv (Visual Studio) | 1 | 648 MB |
| claude | 1 | 527 MB |
| Bitdefender | 5 | 502 MB |

There is no registry tweak for this. The single biggest lever is Chrome at 3.3 GB
across 26 processes:

- **Enable Chrome Memory Saver**: `chrome://settings/performance` → Memory Saver
  on. It suspends background tabs and typically reclaims 1–2 GB.
- The 13 `msedgewebview2` processes are embedded browsers inside other apps
  (Teams, Office add-ins). Closing the host app is the only way to reclaim those.
- 86 `svchost` processes is normal on a managed machine — do not touch them.

Honestly: adding RAM, or keeping fewer Chrome tabs and Visual Studio instances
open, would do more for smoothness than everything else on this page combined.

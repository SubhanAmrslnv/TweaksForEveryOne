using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;

namespace WindowTweaks.Core;

/// <summary>Which sound to play. Each one is synthesised, not loaded from a file.</summary>
internal enum SoundId
{
    /// <summary>An ordinary character key.</summary>
    Key,

    /// <summary>The space bar: the widest key on the board, so the deepest and longest thock.</summary>
    KeySpace,

    /// <summary>Enter: as deep as space but falling in pitch, which is what reads as "committed".</summary>
    KeyEnter,

    /// <summary>Backspace: short, dry, and falling - erasing backwards.</summary>
    KeyBackspace,

    /// <summary>Delete: the mirror of backspace. Shorter, higher and RISING, so the two can be told
    /// apart with the eyes shut even though they do almost the same thing.</summary>
    KeyDelete,

    /// <summary>A modifier or navigation key: quieter than a character.</summary>
    KeySoft,

    Copy,
    Paste,
    Cut,
    SelectAll,
    Transform,

    /// <summary>Ctrl+Z: a clean glide down, because undo runs the work backwards.</summary>
    Undo,

    /// <summary>Ctrl+Y and Ctrl+Shift+Z: the same glide forwards.</summary>
    Redo,

    /// <summary>One notch of the volume wheel.</summary>
    VolumeTick,

    // --- The Windows shortcut chords ------------------------------------------------------------
    // Each one is deliberately unlike its neighbours in SHAPE - rising, falling, ticking, clacking -
    // rather than only in pitch. A set of sounds that differ only by a few semitones is a set nobody
    // learns; a set that differs in direction and texture is one you stop having to think about.

    /// <summary>Alt+Tab, Alt+Shift+Tab, Win+Shift+T: a quick rising swish.</summary>
    SwitchWindow,

    /// <summary>Alt+Shift with nothing in between: the keyboard-layout flip.</summary>
    LanguageSwitch,

    /// <summary>Win+Tab: the same movement as Alt+Tab but wider and slower, because Task View is.</summary>
    TaskView,

    /// <summary>Win+Shift+S and Win+PrintScreen: a two-stage camera clack.</summary>
    Shutter,

    /// <summary>Win+V: three ticks, like a stack of items being counted off.</summary>
    ClipboardHistory,

    /// <summary>Win+. and Win+;: a bright little arpeggio.</summary>
    EmojiPicker,

    /// <summary>Win+D and Win+M: a descending swoop - everything going down.</summary>
    ShowDesktop,

    /// <summary>Win+L: low and final.</summary>
    LockScreen,

    /// <summary>Win+A, Win+I, Win+N, Win+K: a soft blip for a panel sliding in.</summary>
    Panel,

    /// <summary>Win+Ctrl+Right and Win+Ctrl+D: a lateral whoosh, upwards.</summary>
    DesktopNext,

    /// <summary>Win+Ctrl+Left and Win+Ctrl+F4: the same whoosh, downwards.</summary>
    DesktopPrev,

    /// <summary>Win+E, Win+R, Win+S: something opening.</summary>
    Launch,

    /// <summary>Win+Left, Win+Right, Win+Shift+Left/Right: a window landing against an edge.</summary>
    SnapWindow,

    /// <summary>Win+Up: the same landing, then a rise.</summary>
    WindowGrow,

    /// <summary>Win+Down: the same landing, then a fall.</summary>
    WindowShrink
}

/// <summary>
/// Every sound this app makes, synthesised as PCM in memory and played through winmm's waveOut.
///
/// WHY NOT SystemSounds. The first version of the keyboard feature called
/// <c>SystemSounds.Exclamation.Play()</c> on every keystroke, which is wrong three times over: it is
/// the Windows error "ding", so typing sounded like a wall of alerts; it is a shared system sound, so
/// the user cannot turn it down separately from real alerts; and it was played through a
/// Dispatcher.BeginInvoke per keystroke, which put a UI-thread work item on the queue for every key
/// a person typed. Nothing in this file touches the dispatcher.
///
/// WHY THE SOUNDS ARE SYNTHESISED. Shipping .wav assets would mean disk reads on an input path (a
/// measured 1,900-9,300 microseconds for a file touch in this process) and files an antivirus engine
/// has to form an opinion about. A click is a damped noise burst plus a decaying tone - about twenty
/// lines of arithmetic - so it is generated once, cached, and thereafter costs nothing.
///
/// WHY NOT PlaySound. It was the first implementation, and it is the reason the keyboard sound used
/// to play for a while, go silent for a while, and then come back on its own. PlaySound with
/// SND_ASYNC opens a stream on the default endpoint, plays, and tears it down again - on EVERY call.
/// On Windows 11 waveOut is emulated over WASAPI, so a click asked the audio engine to build and
/// destroy a stream up to twenty times a second; under sustained typing those calls begin to fail,
/// and SND_NODEFAULT turns a failure into silence rather than an error, so the feature simply
/// stopped until the engine caught up. The same happens for as long as another application holds
/// the endpoint in exclusive mode. Nothing recovered it except waiting.
///
/// So the device is opened ONCE and kept open while sounds keep arriving (see EnsureDevice), a click
/// costs one buffer write and nothing else, and a write that fails closes the device so the next
/// click reopens it - which is what makes an endpoint change or an exclusive-mode grab recover by
/// itself instead of silencing the feature for the rest of the session.
///
/// THREADING. Play() is called from the hook thread, where the budget is microseconds. Opening a
/// device and writing a buffer are not microsecond operations, so they never run on the caller's
/// thread: a request sets a single slot and wakes a dedicated audio thread. The slot is single, not
/// a queue, deliberately - if sounds arrive faster than they can be played the newest one wins and
/// the rest are dropped, which is what you want from a click and the only way a held key cannot
/// build a backlog.
/// </summary>
internal static class SoundEngine
{
    private const int SampleRate = 44100;

    /// <summary>
    /// How many buffers may sit in the driver's queue at once. A click is under 60 ms and they
    /// arrive at most every 45 ms, so this is generous; its real job is to bound the queue if
    /// something ever asks for sounds faster than the device retires them.
    /// </summary>
    private const int SlotCount = 8;

    /// <summary>
    /// The per-slot buffer. The longest sound in the table is the lock chord at about 245 ms of
    /// 16-bit mono at 44.1 kHz, which is under 22 KB; 32 KB leaves room without being worth
    /// measuring. A clip that does not fit is DROPPED silently by Emit, so a new sound longer than
    /// this would simply never be heard - check the arithmetic before adding one.
    /// </summary>
    private const int SlotBytes = 32 * 1024;

    /// <summary>
    /// How long the output device is held open after the last sound. Long enough that a burst of
    /// typing pays for one open, short enough that plugging in headphones is followed by the next
    /// click coming out of them - waveOut binds to whatever WAVE_MAPPER resolved to at open time,
    /// so the only way to follow a default-device change is to have let go of the old one.
    /// </summary>
    private const int IdleCloseMs = 3000;

    private static readonly object Gate = new();

    /// <summary>
    /// Cached 16-bit mono PCM, keyed by (sound, profile, volume). Managed, and safe to keep managed:
    /// the driver never reads these arrays. A clip is copied into one of the pinned ring buffers
    /// below at the moment it is queued, so nothing the GC can move is ever handed to waveOut.
    /// </summary>
    private static readonly Dictionary<string, byte[]> Cache = new();

    private static readonly AutoResetEvent Wake = new(false);
    private static Thread? _player;
    private static byte[]? _pending;
    private static bool _stopping;

    // The output device and its buffer ring. Touched ONLY by the player thread; Shutdown reaches it
    // by joining that thread rather than by closing the device from underneath it.
    private static IntPtr _device = IntPtr.Zero;
    private static readonly IntPtr[] Headers = new IntPtr[SlotCount];
    private static readonly IntPtr[] Buffers = new IntPtr[SlotCount];
    private static readonly bool[] Prepared = new bool[SlotCount];
    private static int _nextSlot;

    private static readonly int HeaderSize = Marshal.SizeOf<NativeMethods.WAVEHDR>();
    private static readonly int FlagsOffset =
        (int)Marshal.OffsetOf<NativeMethods.WAVEHDR>(nameof(NativeMethods.WAVEHDR.dwFlags));

    /// <summary>
    /// Plays a sound and returns immediately. Safe to call from a hook callback, and safe to call
    /// when the machine has no audio device - in which case it does nothing.
    /// </summary>
    public static void Play(SoundId id, string profile, int volumePercent)
    {
        if (AppLifetime.IsExiting) return;
        if (volumePercent <= 0) return;

        try
        {
            byte[] clip = GetOrBuild(id, profile, Math.Clamp(volumePercent, 1, 100));

            EnsurePlayer();

            // Single slot on purpose: see the class comment.
            Interlocked.Exchange(ref _pending, clip);
            Wake.Set();
        }
        catch
        {
            // A sound is never worth an exception on an input path.
        }
    }

    /// <summary>
    /// Builds and caches sounds ahead of time, off any input path.
    ///
    /// Synthesising one sound is a couple of milliseconds of arithmetic. That is nothing on a
    /// background thread and it is not nothing on the hook thread, where the first keystroke of the
    /// session would otherwise pay for it - and where the budget before Windows starts dropping the
    /// hook is 300 ms for everything. Called when a feature that makes sounds is switched on.
    /// </summary>
    public static void Prewarm(string profile, int volumePercent, params SoundId[] ids)
    {
        if (ids.Length == 0) return;

        int volume = Math.Clamp(volumePercent, 1, 100);

        System.Threading.Tasks.Task.Run(() =>
        {
            foreach (SoundId id in ids)
            {
                try
                {
                    GetOrBuild(id, profile, volume);
                }
                catch
                {
                    // A sound that cannot be built is silence, not a failure worth reporting.
                }
            }
        });
    }

    /// <summary>Silence anything in flight and release the device. Exit only.</summary>
    public static void Shutdown()
    {
        Thread? player;

        lock (Gate)
        {
            _stopping = true;
            player = _player;
        }

        try { Wake.Set(); } catch { }

        // Joined rather than raced: the player thread owns the device, and resetting it from here
        // while that thread is mid-write is the one way this file could take the process down on the
        // way out. Bounded, because exit must not wait on an audio driver.
        try { player?.Join(150); } catch { }
    }

    private static void EnsurePlayer()
    {
        // Unlocked fast path, because this runs on the hook thread for every keystroke and the
        // thread is created exactly once in a session. The check is repeated under the lock, which
        // is the one that decides.
        if (Volatile.Read(ref _player) != null) return;

        lock (Gate)
        {
            if (_stopping) return;
            if (_player != null) return;

            _player = new Thread(PlayLoop)
            {
                IsBackground = true,
                Name = "WindowTweaks.Sound"
            };
            _player.Start();
        }
    }

    private static void PlayLoop()
    {
        try
        {
            while (true)
            {
                // A bounded wait, so an idle session is not holding an audio endpoint open. The
                // timeout is the only thing that closes the device during normal running.
                bool signalled = Wake.WaitOne(IdleCloseMs);

                lock (Gate)
                {
                    if (_stopping) return;
                }

                if (AppLifetime.IsExiting) return;

                if (!signalled)
                {
                    CloseDevice();
                    continue;
                }

                byte[]? clip = Interlocked.Exchange(ref _pending, null);
                if (clip == null) continue;

                // One retry, because the first failure is what closes a device that has gone stale -
                // an endpoint switched away, or one another application took exclusively. Without it
                // the click that discovered the problem would be lost as well.
                if (!Emit(clip)) Emit(clip);
            }
        }
        catch
        {
            // Never let this thread die with a device still open.
        }
        finally
        {
            CloseDevice();

            lock (Gate) _player = null;
        }
    }

    // -------------------------------------------------------------------------------------------
    // The output device. Everything in this section runs on the player thread only.
    // -------------------------------------------------------------------------------------------

    /// <summary>
    /// Queues one clip. Returns false only when the device failed and has been closed, which is the
    /// one case worth retrying.
    /// </summary>
    private static bool Emit(byte[] clip)
    {
        if (clip.Length <= 0 || clip.Length > SlotBytes) return true;
        if (!EnsureDevice()) return true;

        IntPtr header = TakeFreeSlot(clip);

        // Every buffer is still with the driver. Dropping the click is right: the ring is far larger
        // than any sensible backlog, so this only happens when the device has stopped retiring
        // buffers at all, and one more would not be heard either.
        if (header == IntPtr.Zero) return true;

        if (NativeMethods.waveOutWrite(_device, header, (uint)HeaderSize) != NativeMethods.MMSYSERR_NOERROR)
        {
            CloseDevice();
            return false;
        }

        return true;
    }

    private static bool EnsureDevice()
    {
        if (_device != IntPtr.Zero) return true;

        NativeMethods.WAVEFORMATEX format = new()
        {
            wFormatTag = NativeMethods.WAVE_FORMAT_PCM,
            nChannels = 1,
            nSamplesPerSec = SampleRate,
            nAvgBytesPerSec = SampleRate * 2,
            nBlockAlign = 2,
            wBitsPerSample = 16,
            cbSize = 0
        };

        try
        {
            uint result = NativeMethods.waveOutOpen(out IntPtr device, NativeMethods.WAVE_MAPPER,
                ref format, IntPtr.Zero, IntPtr.Zero, NativeMethods.CALLBACK_NULL);

            if (result != NativeMethods.MMSYSERR_NOERROR) return false;

            _device = device;
        }
        catch
        {
            _device = IntPtr.Zero;
            return false;
        }

        // The ring is allocated once for the life of the process and reused across opens. Freeing it
        // on every close would put unmanaged churn back on the path this whole design exists to
        // remove, and it is a quarter of a megabyte.
        for (int i = 0; i < SlotCount; i++)
        {
            if (Buffers[i] == IntPtr.Zero) Buffers[i] = Marshal.AllocHGlobal(SlotBytes);
            if (Headers[i] == IntPtr.Zero) Headers[i] = Marshal.AllocHGlobal(HeaderSize);

            // A header prepared against the previous device handle means nothing to this one.
            Prepared[i] = false;
        }

        _nextSlot = 0;
        return true;
    }

    /// <summary>
    /// Finds a slot the driver has finished with, loads the clip into it and prepares it. Returns
    /// the header, or zero when every slot is still queued.
    /// </summary>
    private static IntPtr TakeFreeSlot(byte[] clip)
    {
        for (int attempt = 0; attempt < SlotCount; attempt++)
        {
            int slot = _nextSlot;
            _nextSlot = (_nextSlot + 1) % SlotCount;

            IntPtr header = Headers[slot];
            if (header == IntPtr.Zero || Buffers[slot] == IntPtr.Zero) continue;

            if (Prepared[slot])
            {
                uint flags = (uint)Marshal.ReadInt32(header, FlagsOffset);
                if ((flags & NativeMethods.WHDR_DONE) == 0) continue;

                NativeMethods.waveOutUnprepareHeader(_device, header, (uint)HeaderSize);
                Prepared[slot] = false;
            }

            // Copied into the ring rather than handed over directly: the driver reads the buffer
            // after waveOutWrite returns, so it has to be unmanaged memory whose lifetime this file
            // controls, not a managed array the GC is free to move.
            Marshal.Copy(clip, 0, Buffers[slot], clip.Length);

            NativeMethods.WAVEHDR wh = new()
            {
                lpData = Buffers[slot],
                dwBufferLength = (uint)clip.Length
            };
            Marshal.StructureToPtr(wh, header, false);

            if (NativeMethods.waveOutPrepareHeader(_device, header, (uint)HeaderSize) != NativeMethods.MMSYSERR_NOERROR)
            {
                return IntPtr.Zero;
            }

            Prepared[slot] = true;
            return header;
        }

        return IntPtr.Zero;
    }

    private static void CloseDevice()
    {
        if (_device == IntPtr.Zero) return;

        IntPtr device = _device;
        _device = IntPtr.Zero;

        // Reset first: it marks every queued buffer done, which is what lets them be unprepared and
        // the handle closed at all. waveOutClose fails with WAVERR_STILLPLAYING otherwise, and the
        // device would leak for the rest of the session.
        try { NativeMethods.waveOutReset(device); } catch { }

        for (int i = 0; i < SlotCount; i++)
        {
            if (!Prepared[i]) continue;

            try { NativeMethods.waveOutUnprepareHeader(device, Headers[i], (uint)HeaderSize); } catch { }
            Prepared[i] = false;
        }

        try { NativeMethods.waveOutClose(device); } catch { }
    }

    // -------------------------------------------------------------------------------------------
    // Synthesis
    // -------------------------------------------------------------------------------------------

    private static byte[] GetOrBuild(SoundId id, string profile, int volumePercent)
    {
        // Volume is quantised to 5% steps so dragging the slider cannot generate twenty buffers.
        int bucket = volumePercent / 5 * 5;
        if (bucket < 5) bucket = 5;

        string key = id + "|" + profile + "|" + bucket;

        lock (Gate)
        {
            if (Cache.TryGetValue(key, out byte[]? existing)) return existing;
        }

        // Built outside the lock: synthesis is milliseconds of arithmetic, and Play() reaches this
        // method from the hook thread, where a lock held across that would be a lock held across an
        // input event for the whole operating system.
        byte[] pcm = BuildPcm(id, profile, bucket / 100.0);

        lock (Gate)
        {
            // NOT EVICTED, DELIBERATELY. The growth it would be protecting against is small and
            // hard-bounded: ten sounds times three profiles times twenty volume buckets, about five
            // kilobytes each, so under three megabytes even if a user sweeps every slider through
            // every position. Real sessions hold four or five entries.
            if (Cache.TryGetValue(key, out byte[]? raced)) return raced;

            Cache[key] = pcm;
        }

        return pcm;
    }

    /// <summary>Synthesises one sound as raw little-endian 16-bit mono PCM - no container.</summary>
    private static byte[] BuildPcm(SoundId id, string profile, double gain)
    {
        double[] samples = Synthesise(id, profile);

        // Normalise, then apply the user's gain. Normalising first means the volume slider means the
        // same thing for every sound instead of tracking how loud that particular formula came out.
        double peak = 0;
        for (int i = 0; i < samples.Length; i++)
        {
            double a = Math.Abs(samples[i]);
            if (a > peak) peak = a;
        }
        if (peak <= 0) peak = 1;

        // Normalisation alone makes every sound equally loud, which is why the old "modifiers are
        // quieter" comment was not true of the audio: KeySoft was normalised back up to the same
        // peak as a letter. The balance has to be applied AFTER normalising, not built into the
        // formula, or it is undone by the very step that makes the volume slider mean one thing.
        double scale = gain / peak * 0.9 * Balance(id);

        byte[] pcm = new byte[samples.Length * 2];
        for (int i = 0; i < samples.Length; i++)
        {
            double v = samples[i] * scale;
            short sample = (short)Math.Clamp(v * short.MaxValue, short.MinValue, short.MaxValue);

            pcm[i * 2] = (byte)sample;
            pcm[i * 2 + 1] = (byte)(sample >> 8);
        }

        return pcm;
    }

    /// <summary>
    /// How loud one sound is RELATIVE to the others, applied after normalisation so the volume
    /// slider still means the same thing everywhere. 1.0 is the reference.
    /// </summary>
    private static double Balance(SoundId id)
    {
        return id switch
        {
            // A modifier is not an event. Holding shift should be felt, not heard.
            SoundId.KeySoft => 0.45,

            // Erasing is a correction, and a correction that shouts is worse than one that does not.
            SoundId.KeyBackspace => 0.78,
            SoundId.KeyDelete => 0.78,

            // The chords fire once per gesture rather than hundreds of times a minute, so they can
            // afford to be present - but Lock and the shutter are the two loudest formulas here and
            // need pulling back rather than pushing forward.
            SoundId.Shutter => 0.85,
            SoundId.LockScreen => 0.9,

            _ => 1.0
        };
    }

    private static double[] Synthesise(SoundId id, string profile)
    {
        return id switch
        {
            // (decay, pitch, glide). Decay above 1 shortens; pitch below 1 deepens; glide is the
            // factor the body frequency reaches by the end, so 1.0 is a flat note, below 1 falls and
            // above 1 rises. The four special keys are told apart by SHAPE and not only by pitch:
            // space is a flat thock, enter falls, backspace falls fast, delete rises.
            SoundId.Key => Keystroke(profile, 1.0, 1.0, 1.0),
            SoundId.KeySpace => Keystroke(profile, 0.55, 0.60, 1.0),
            SoundId.KeyEnter => Keystroke(profile, 0.70, 0.92, 0.55),
            SoundId.KeyBackspace => Keystroke(profile, 1.45, 1.10, 0.70),
            SoundId.KeyDelete => Keystroke(profile, 1.50, 1.45, 1.40),
            SoundId.KeySoft => Keystroke(profile, 1.15, 0.55, 1.0),

            // The clipboard actions are pitched so they can be told apart without looking: copy
            // rises, paste falls, cut is a dry snip, select-all is a chord.
            SoundId.Copy => Sequence(new[] { (880.0, 0.055), (1320.0, 0.075) }),
            SoundId.Paste => Sequence(new[] { (1320.0, 0.055), (880.0, 0.075) }),
            SoundId.Cut => Snip(),
            SoundId.SelectAll => Chord(new[] { 660.0, 990.0, 1320.0 }, 0.13),
            SoundId.Transform => Sequence(new[] { (740.0, 0.05), (1108.0, 0.05), (1480.0, 0.08) }),

            // Undo runs the work backwards and redo runs it forwards, so the pair is one glide in
            // two directions. There are two other rising sweeps in this table and this pair has to
            // clear BOTH of them, which is what sets the numbers:
            //
            //   - DesktopNext is a low whoosh at 420-760 and almost all air (0.45). Separated by
            //     register and by texture - this pair is nearly a pure tone.
            //   - SwitchWindow is the close one. It rises 520-1180 in 0.075 s with a little air,
            //     which is near enough to a rising glide at 590-1050 that the two were hard to tell
            //     apart. So this pair sits ABOVE it rather than inside it: Redo now starts where the
            //     switcher finishes, and the air is turned down almost to nothing.
            SoundId.Undo => Sweep(1480, 920, 0.075, 22, 0.02),
            SoundId.Redo => Sweep(920, 1480, 0.075, 22, 0.02),

            SoundId.VolumeTick => Chord(new[] { 1600.0 }, 0.028),

            // --- The Windows chords ---------------------------------------------------------
            // Alt+Tab and Win+Tab are the same gesture at two scales, so they are the same shape at
            // two scales: a rising sweep, short and tight for the window switcher, longer and airier
            // for Task View. Getting those two backwards is the one mistake that would matter.
            SoundId.SwitchWindow => Sweep(520, 1180, 0.075, 26, 0.15),
            SoundId.TaskView => Sweep(300, 900, 0.155, 9, 0.22),

            // Not a sweep, because switching layout is not movement: it is a toggle. Down then back
            // up, so it reads as a flip rather than as a direction.
            SoundId.LanguageSwitch => Sequence(new[] { (1174.7, 0.045), (784.0, 0.045), (1174.7, 0.07) }),

            SoundId.Shutter => Shutter(),

            // Three ticks at one pitch and then a step up: a stack being counted, then opened.
            SoundId.ClipboardHistory => Sequence(new[] { (1046.5, 0.032), (1046.5, 0.032), (1568.0, 0.065) }),

            // The one sound in the app allowed to be cheerful.
            SoundId.EmojiPicker => Sequence(new[] { (1318.5, 0.04), (1661.2, 0.04), (1975.5, 0.085) }),

            // The inverse of the switcher sweep. Everything on the screen is going away and down.
            SoundId.ShowDesktop => Sweep(900, 260, 0.13, 12, 0.20),

            // Low and closed. It is the last thing you hear before the screen goes.
            SoundId.LockScreen => Sequence(new[] { (392.0, 0.085), (261.6, 0.16) }),

            SoundId.Panel => Chord(new[] { 880.0, 1174.7 }, 0.075),

            // Mostly air and a LOW glide, because moving between desktops is a slide rather than a
            // note - and because it has to be told apart from the window switcher above, which is
            // also a rising sweep. The contrast is textural: the switcher is a short clean chirp
            // high up, this is a longer whoosh underneath it. The pair is symmetrical, so whichever
            // way the desktop goes the pitch goes with it.
            //
            // The air is high-passed, so pushing it much past this buries the glide and the two
            // become the same noise burst in both directions - which is what the first pass did.
            SoundId.DesktopNext => Sweep(420, 760, 0.105, 14, 0.45),
            SoundId.DesktopPrev => Sweep(760, 420, 0.105, 14, 0.45),

            SoundId.Launch => Chord(new[] { 523.3, 784.0 }, 0.1),

            // All three open with the SAME impact, because all three are a window landing. Only up
            // and down add a direction on top of it - a plain edge snap has nowhere to go, so
            // giving it a glide would be inventing a movement that did not happen.
            SoundId.SnapWindow => Impact(230, 0.06, 65),
            SoundId.WindowGrow => Then(Impact(230, 0.045, 80), Sweep(600, 1000, 0.06, 20, 0.12)),
            SoundId.WindowShrink => Then(Impact(230, 0.045, 80), Sweep(1000, 600, 0.06, 20, 0.12)),

            _ => Keystroke(profile, 1.0, 1.0, 1.0)
        };
    }

    /// <summary>
    /// One key press. A <paramref name="decayScale"/> above 1 shortens it; a
    /// <paramref name="pitchScale"/> below 1 deepens it; <paramref name="glide"/> is the factor the
    /// body frequency has reached by the last sample, so 1.0 is a flat note, 0.55 falls a little
    /// under an octave and 1.4 rises. Those three are how space, enter, backspace and delete differ
    /// from a letter and - just as importantly - from each other.
    ///
    /// The tone is built by ACCUMULATING PHASE rather than evaluating sin(2*pi*f*t). With a moving
    /// frequency the second form is wrong: it jumps the phase every sample, so a glide comes out as
    /// a buzz rather than as a pitch change. It is the same arithmetic either way once the frequency
    /// is constant, so the flat sounds are unaffected.
    /// </summary>
    private static double[] Keystroke(string profile, double decayScale, double pitchScale, double glide)
    {
        // (length ms, click decay, body frequency, body decay, noise share)
        (double ms, double clickDecay, double bodyHz, double bodyDecay, double noise) p = profile switch
        {
            // A dry, high, very short tick. The default, because it is the one that disappears into
            // typing instead of competing with it.
            "click" => (26, 420, 2100, 260, 0.55),

            // A heavier mechanical thock: more low body, longer tail.
            "typewriter" => (58, 260, 340, 90, 0.45),

            // Almost no noise, just a soft tone. For someone who wants feedback, not a keyboard.
            "soft" => (40, 160, 1050, 120, 0.10),

            _ => (26, 420, 2100, 260, 0.55)
        };

        // The buffer LENGTH follows the decay, which it did not used to. A sound asked to decay
        // slowly inside a fixed-length buffer is not a longer sound - it is the same length with its
        // tail cut off by the release fade, which is why space and enter used to be distinguishable
        // on paper and not in the ear. Clamped so no profile can ask for a buffer worth measuring.
        double lengthSeconds = p.ms / 1000.0 / Math.Clamp(decayScale, 0.45, 2.0);

        int count = Samples(lengthSeconds);
        double[] result = new double[count];

        // Deterministic, so the same key always sounds the same and the buffer can be cached. A
        // fresh random burst per press would mean synthesising on the input path.
        Random rng = new(unchecked(profile.Length * 7919 + (int)(pitchScale * 1000) + (int)(glide * 97)));

        double bodyHz = p.bodyHz * pitchScale;
        double clickDecay = p.clickDecay * decayScale;
        double bodyDecay = p.bodyDecay * decayScale;

        double phase = 0, harmonicPhase = 0;

        for (int i = 0; i < count; i++)
        {
            double t = i / (double)SampleRate;
            double through = count > 1 ? i / (double)(count - 1) : 0;

            double hz = bodyHz * (1 + (glide - 1) * through);
            phase += 2 * Math.PI * hz / SampleRate;
            harmonicPhase += 2 * Math.PI * hz * 2.01 / SampleRate;

            double clickEnv = Math.Exp(-t * clickDecay);
            double bodyEnv = Math.Exp(-t * bodyDecay);

            double noise = (rng.NextDouble() * 2 - 1) * clickEnv * p.noise;
            double body = Math.Sin(phase) * bodyEnv * (1 - p.noise);

            // A touch of the second harmonic stops the tone sounding like a test signal.
            double harmonic = Math.Sin(harmonicPhase) * bodyEnv * 0.18;

            result[i] = (noise + body + harmonic) * Attack(t) * Release(i, count);
        }

        return result;
    }

    /// <summary>
    /// A tone that glides from one frequency to another, mixed with high-passed noise so it reads as
    /// MOVEMENT rather than as a note. This is the shape every "something slid across the screen"
    /// chord uses - the window switcher, Task View, show desktop and the virtual desktops - and the
    /// direction of the glide always matches the direction of the thing on screen.
    ///
    /// <paramref name="noiseShare"/> is how much of the result is air: near zero is a clean sweep,
    /// near one is mostly a whoosh.
    /// </summary>
    private static double[] Sweep(double fromHz, double toHz, double seconds, double decay, double noiseShare)
    {
        int count = Samples(seconds);
        double[] result = new double[count];

        Random rng = new(unchecked((int)(fromHz * 31 + toHz * 7)));

        double phase = 0;
        double previousNoise = 0;

        for (int i = 0; i < count; i++)
        {
            double t = i / (double)SampleRate;
            double through = count > 1 ? i / (double)(count - 1) : 0;

            double hz = fromHz + (toHz - fromHz) * through;
            phase += 2 * Math.PI * hz / SampleRate;

            double raw = rng.NextDouble() * 2 - 1;

            // A one-pole high pass. Broadband noise under a tone sounds like a fault; the same noise
            // with its low end removed sounds like air moving.
            double air = (raw - previousNoise) * 0.5;
            previousNoise = raw;

            double env = Math.Exp(-t * decay);

            result[i] = (Math.Sin(phase) * (1 - noiseShare) + air * noiseShare)
                        * env * Attack(t) * Release(i, count);
        }

        return result;
    }

    /// <summary>
    /// A single dry knock: high-passed noise for the contact over a fast-decaying low sine for the
    /// weight. This is what "something landed" sounds like, and it is deliberately NOT a glide - a
    /// window snapping to an edge has arrived, so a sound that is still travelling would be lying
    /// about it.
    /// </summary>
    private static double[] Impact(double bodyHz, double seconds, double decay)
    {
        int count = Samples(seconds);
        double[] result = new double[count];

        Random rng = new(unchecked((int)(bodyHz * 13 + seconds * 10000)));

        double previousNoise = 0;

        for (int i = 0; i < count; i++)
        {
            double t = i / (double)SampleRate;
            double env = Math.Exp(-t * decay);

            double raw = rng.NextDouble() * 2 - 1;

            // The same one-pole high pass as Sweep and Shutter: broadband noise under a low body
            // sounds like a fault, the same noise with its low end removed sounds like contact.
            double contact = raw - previousNoise * 0.85;
            previousNoise = raw;

            double body = Math.Sin(2 * Math.PI * bodyHz * t) * 0.9;

            result[i] = (contact * 0.55 + body) * env * Attack(t) * Release(i, count);
        }

        return result;
    }

    /// <summary>
    /// One sound after another. Safe to join any two clips without a click at the seam, because
    /// every builder here already fades its own ends - see Attack and Release.
    /// </summary>
    private static double[] Then(double[] first, double[] second)
    {
        double[] result = new double[first.Length + second.Length];

        Array.Copy(first, 0, result, 0, first.Length);
        Array.Copy(second, 0, result, first.Length, second.Length);

        return result;
    }

    /// <summary>
    /// Win+Shift+S and Win+PrintScreen: a camera. Two clacks rather than one - the second is what
    /// makes it read as a shutter instead of as a stray click - over a short low body for weight.
    ///
    /// Close to two Impacts, and deliberately not written as two: theirs OVERLAP rather than follow
    /// one another, so Then cannot express it and a mixing helper for one caller is not worth its
    /// own function.
    /// </summary>
    private static double[] Shutter()
    {
        int count = Samples(0.125);
        int secondClack = Samples(0.05);

        double[] result = new double[count];
        Random rng = new(4177);

        double previousNoise = 0;

        for (int i = 0; i < count; i++)
        {
            double t = i / (double)SampleRate;

            double first = Math.Exp(-t * 150.0);
            double second = i >= secondClack
                ? Math.Exp(-(i - secondClack) / (double)SampleRate * 110.0) * 0.7
                : 0;

            double env = first + second;

            double raw = rng.NextDouble() * 2 - 1;
            double clack = raw - previousNoise * 0.85;
            previousNoise = raw;

            double body = Math.Sin(2 * Math.PI * 190.0 * t) * env * 0.3;

            result[i] = (clack * env + body) * Attack(t) * Release(i, count);
        }

        return result;
    }

    private static double[] Sequence((double hz, double seconds)[] steps)
    {
        int total = 0;
        foreach ((double _, double seconds) in steps) total += Samples(seconds);

        double[] result = new double[total];
        int at = 0;

        foreach ((double hz, double seconds) in steps)
        {
            int count = Samples(seconds);
            for (int i = 0; i < count; i++)
            {
                double t = i / (double)SampleRate;
                double env = Math.Exp(-t * 4.9 / seconds);
                result[at + i] = Math.Sin(2 * Math.PI * hz * t) * env * Attack(t) * Release(i, count);
            }
            at += count;
        }

        return result;
    }

    private static double[] Chord(double[] frequencies, double seconds)
    {
        int count = Samples(seconds);
        double[] result = new double[count];

        for (int i = 0; i < count; i++)
        {
            double t = i / (double)SampleRate;
            double env = Math.Exp(-t * 18.0);

            double sum = 0;
            foreach (double hz in frequencies) sum += Math.Sin(2 * Math.PI * hz * t);

            result[i] = sum / frequencies.Length * env * Attack(t) * Release(i, count);
        }

        return result;
    }

    /// <summary>Cut: a short noise burst with the low end removed, so it reads as scissors.</summary>
    private static double[] Snip()
    {
        int count = Samples(0.05);
        double[] result = new double[count];
        Random rng = new(1729);

        double previous = 0;
        for (int i = 0; i < count; i++)
        {
            double t = i / (double)SampleRate;
            double env = Math.Exp(-t * 90.0);

            double noise = rng.NextDouble() * 2 - 1;

            // A one-pole high pass, so the burst sits above the voice range and cannot be mistaken
            // for the key click.
            double filtered = noise - previous;
            previous = noise;

            result[i] = filtered * env * Attack(t) * Release(i, count);
        }

        return result;
    }

    /// <summary>A 1 ms fade-in. Starting a waveform at full amplitude puts an audible tick on it.</summary>
    private static double Attack(double t)
    {
        const double AttackSeconds = 0.001;
        return t >= AttackSeconds ? 1.0 : t / AttackSeconds;
    }

    /// <summary>A short fade-out, for the same reason at the other end.</summary>
    private static double Release(int index, int count)
    {
        int tail = Math.Min(count / 4, Samples(0.004));
        if (tail <= 0) return 1.0;

        int fromEnd = count - index;
        return fromEnd >= tail ? 1.0 : fromEnd / (double)tail;
    }

    private static int Samples(double seconds)
    {
        return Math.Max(1, (int)(seconds * SampleRate));
    }
}

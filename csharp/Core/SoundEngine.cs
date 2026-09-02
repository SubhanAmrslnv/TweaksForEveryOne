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

    /// <summary>The wide keys - space and enter - which sound deeper on a real keyboard.</summary>
    KeyDeep,

    /// <summary>Backspace and delete: a shorter, drier tick.</summary>
    KeyErase,

    /// <summary>A modifier or navigation key: quieter than a character.</summary>
    KeySoft,

    Copy,
    Paste,
    Cut,
    SelectAll,
    Transform,

    /// <summary>One notch of the volume wheel.</summary>
    VolumeTick
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
    /// The per-slot buffer. The longest sound in the table is about 180 ms of 16-bit mono at
    /// 44.1 kHz, which is under 16 KB; 32 KB leaves room without being worth measuring.
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

        double scale = gain / peak * 0.9;

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

    private static double[] Synthesise(SoundId id, string profile)
    {
        return id switch
        {
            SoundId.Key => Keystroke(profile, 1.0, 1.0),
            SoundId.KeyDeep => Keystroke(profile, 0.62, 1.25),
            SoundId.KeyErase => Keystroke(profile, 1.35, 0.7),
            SoundId.KeySoft => Keystroke(profile, 1.15, 0.5),

            // The clipboard actions are pitched so they can be told apart without looking: copy
            // rises, paste falls, cut is a dry snip, select-all is a chord.
            SoundId.Copy => Sequence(new[] { (880.0, 0.055), (1320.0, 0.075) }),
            SoundId.Paste => Sequence(new[] { (1320.0, 0.055), (880.0, 0.075) }),
            SoundId.Cut => Snip(),
            SoundId.SelectAll => Chord(new[] { 660.0, 990.0, 1320.0 }, 0.13),
            SoundId.Transform => Sequence(new[] { (740.0, 0.05), (1108.0, 0.05), (1480.0, 0.08) }),

            SoundId.VolumeTick => Chord(new[] { 1600.0 }, 0.028),
            _ => Keystroke(profile, 1.0, 1.0)
        };
    }

    /// <summary>
    /// One key press. A <paramref name="decayScale"/> above 1 shortens it; a
    /// <paramref name="pitchScale"/> below 1 deepens it. Those two are how the wide keys and
    /// backspace differ from a letter.
    /// </summary>
    private static double[] Keystroke(string profile, double decayScale, double pitchScale)
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

        int count = Samples(p.ms / 1000.0);
        double[] result = new double[count];

        // Deterministic, so the same key always sounds the same and the buffer can be cached. A
        // fresh random burst per press would mean synthesising on the input path.
        Random rng = new(unchecked(profile.Length * 7919 + (int)(pitchScale * 1000)));

        double bodyHz = p.bodyHz * pitchScale;
        double clickDecay = p.clickDecay * decayScale;
        double bodyDecay = p.bodyDecay * decayScale;

        for (int i = 0; i < count; i++)
        {
            double t = i / (double)SampleRate;

            double clickEnv = Math.Exp(-t * clickDecay);
            double bodyEnv = Math.Exp(-t * bodyDecay);

            double noise = (rng.NextDouble() * 2 - 1) * clickEnv * p.noise;
            double body = Math.Sin(2 * Math.PI * bodyHz * t) * bodyEnv * (1 - p.noise);

            // A touch of the second harmonic stops the tone sounding like a test signal.
            double harmonic = Math.Sin(2 * Math.PI * bodyHz * 2.01 * t) * bodyEnv * 0.18;

            result[i] = (noise + body + harmonic) * Attack(t) * Release(i, count);
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

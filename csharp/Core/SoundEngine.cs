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
/// Every sound this app makes, synthesised into a WAV in memory and played with winmm's PlaySound.
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
/// THREADING. Play() is called from the hook thread, where the budget is microseconds. PlaySound
/// itself opens a waveOut device and takes closer to a millisecond, so it never runs on the caller's
/// thread: a request sets a single slot and wakes a dedicated audio thread. The slot is single, not
/// a queue, deliberately - if sounds arrive faster than they can be played the newest one wins and
/// the rest are dropped, which is what you want from a click and the only way a held key cannot
/// build a backlog.
/// </summary>
internal static class SoundEngine
{
    private const int SampleRate = 44100;

    private static readonly object Gate = new();

    /// <summary>Cached unmanaged WAV buffers, keyed by (sound, profile, volume).</summary>
    private static readonly Dictionary<string, IntPtr> Cache = new();

    private static readonly AutoResetEvent Wake = new(false);
    private static Thread? _player;
    private static IntPtr _pending = IntPtr.Zero;
    private static bool _stopping;

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
            IntPtr wav = GetOrBuild(id, profile, Math.Clamp(volumePercent, 1, 100));
            if (wav == IntPtr.Zero) return;

            EnsurePlayer();

            // Single slot on purpose: see the class comment.
            Interlocked.Exchange(ref _pending, wav);
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

    /// <summary>Silence anything in flight. Exit only.</summary>
    public static void Shutdown()
    {
        lock (Gate) _stopping = true;
        try { Wake.Set(); } catch { }
        try { NativeMethods.PlaySound(IntPtr.Zero, IntPtr.Zero, NativeMethods.SND_PURGE); } catch { }
    }

    private static void EnsurePlayer()
    {
        lock (Gate)
        {
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
        while (true)
        {
            Wake.WaitOne();

            lock (Gate)
            {
                if (_stopping) return;
            }

            if (AppLifetime.IsExiting) return;

            IntPtr wav = Interlocked.Exchange(ref _pending, IntPtr.Zero);
            if (wav == IntPtr.Zero) continue;

            try
            {
                // SND_MEMORY: wav points at a WAV image, not a filename. SND_ASYNC so a longer
                // sound cannot stall the next one. SND_NODEFAULT so a failure is silence rather
                // than the Windows default beep, which would be far worse than no sound at all.
                NativeMethods.PlaySound(wav, IntPtr.Zero,
                    NativeMethods.SND_MEMORY | NativeMethods.SND_ASYNC | NativeMethods.SND_NODEFAULT);
            }
            catch
            {
            }
        }
    }

    // -------------------------------------------------------------------------------------------
    // Synthesis
    // -------------------------------------------------------------------------------------------

    private static IntPtr GetOrBuild(SoundId id, string profile, int volumePercent)
    {
        // Volume is quantised to 5% steps so dragging the slider cannot generate twenty buffers.
        int bucket = volumePercent / 5 * 5;
        if (bucket < 5) bucket = 5;

        string key = id + "|" + profile + "|" + bucket;

        lock (Gate)
        {
            if (Cache.TryGetValue(key, out IntPtr existing)) return existing;
        }

        byte[] wav = BuildWav(id, profile, bucket / 100.0);

        // Unmanaged, and never freed. SND_MEMORY with SND_ASYNC means winmm reads this buffer AFTER
        // PlaySound returns, so it has to stay put and stay valid - a managed array could be moved
        // by a collection mid-playback. There are at most a couple of dozen of these.
        IntPtr block = Marshal.AllocHGlobal(wav.Length);
        Marshal.Copy(wav, 0, block, wav.Length);

        lock (Gate)
        {
            if (Cache.TryGetValue(key, out IntPtr raced))
            {
                Marshal.FreeHGlobal(block);
                return raced;
            }

            Cache[key] = block;
        }

        return block;
    }

    private static byte[] BuildWav(SoundId id, string profile, double gain)
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

        short[] pcm = new short[samples.Length];
        for (int i = 0; i < samples.Length; i++)
        {
            double v = samples[i] * scale;
            pcm[i] = (short)Math.Clamp(v * short.MaxValue, short.MinValue, short.MaxValue);
        }

        return Wrap(pcm);
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

    /// <summary>Wraps PCM in the smallest valid RIFF/WAVE container: 16-bit, mono, 44.1 kHz.</summary>
    private static byte[] Wrap(short[] pcm)
    {
        const int HeaderBytes = 44;
        int dataBytes = pcm.Length * 2;
        byte[] wav = new byte[HeaderBytes + dataBytes];

        void Ascii(int at, string text)
        {
            for (int i = 0; i < text.Length; i++) wav[at + i] = (byte)text[i];
        }

        void U32(int at, uint value)
        {
            wav[at] = (byte)value;
            wav[at + 1] = (byte)(value >> 8);
            wav[at + 2] = (byte)(value >> 16);
            wav[at + 3] = (byte)(value >> 24);
        }

        void U16(int at, ushort value)
        {
            wav[at] = (byte)value;
            wav[at + 1] = (byte)(value >> 8);
        }

        Ascii(0, "RIFF");
        U32(4, (uint)(36 + dataBytes));
        Ascii(8, "WAVE");
        Ascii(12, "fmt ");
        U32(16, 16);              // PCM header size
        U16(20, 1);               // WAVE_FORMAT_PCM
        U16(22, 1);               // mono
        U32(24, SampleRate);
        U32(28, SampleRate * 2);  // byte rate: mono, two bytes per sample
        U16(32, 2);               // block align
        U16(34, 16);              // bits per sample
        Ascii(36, "data");
        U32(40, (uint)dataBytes);

        for (int i = 0; i < pcm.Length; i++) U16(HeaderBytes + i * 2, (ushort)pcm[i]);

        return wav;
    }
}

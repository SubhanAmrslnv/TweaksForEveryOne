using System;
using System.Diagnostics;
using System.Threading;
using System.Windows.Threading;
using Microsoft.Win32;
using Application = System.Windows.Application;

namespace WindowTweaks.Core;

/// <summary>
/// States for the cursor motion, micro-animation, and breathing state machine.
/// </summary>
public enum CursorMotionState
{
    /// <summary>Cursor is stationary at resting scale (1.00x), awaiting idle breathing threshold.</summary>
    Dormant,

    /// <summary>Active hand motion; scale dynamically driven by velocity mapping and critically damped spring (Priority 2).</summary>
    Moving,

    /// <summary>Mouse button held down or active window drag; breathing strictly suppressed, velocity tracking preserved (Priority 3).</summary>
    Dragging,

    /// <summary>Stationary beyond idle threshold with no buttons held; gentle pure-scale sine oscillation (Priority 4).</summary>
    Breathing,

    /// <summary>Screen locked, display asleep, or full-screen Game Mode active; scheduler rendering completely paused.</summary>
    Suspended
}

/// <summary>
/// Low-overhead mouse velocity tracker, physical damping model, and priority arbitration state machine
/// for macOS-style cursor micro-animations.
///
/// State Priority Hierarchy:
/// - Priority 1: Click interaction (independent overlay event via ClickOccurred)
/// - Priority 2: Active mouse movement (velocity scaling overrides breathing instantly)
/// - Priority 3: Dragging operations (suppress breathing; preserve Parallax Dragging)
/// - Priority 4: Idle breathing (active only when cursor has been completely stationary for 500ms+)
/// </summary>
public sealed class CursorMotionModel : IDisposable
{
    private const string HookOwner = nameof(CursorMotionModel);

    public const int FrameIntervalMs = 15;
    public const int WarpThresholdPx = 300;
    public const double MaxDtSec = 0.100;
    public const double TauSec = 0.030;

    public const double DormantSpeedEpsilon = 2.0;
    public const double DormantScaleEpsilon = 0.0005;
    public const double DormantVelocityEpsilon = 0.001;

    private const int WM_LBUTTONDOWN = 0x0201;
    private const int WM_LBUTTONUP = 0x0202;
    private const int WM_RBUTTONDOWN = 0x0204;
    private const int WM_RBUTTONUP = 0x0205;
    private const int WM_MBUTTONDOWN = 0x0207;
    private const int WM_MBUTTONUP = 0x0208;

    public delegate void MotionUpdateHandler(double scale, double speed, int x, int y, CursorMotionState state);

    public event MotionUpdateHandler? MotionUpdated;
    public event Action<CursorMotionState, CursorMotionState>? StateChanged;
    public event Action<int, int>? ClickOccurred;

    private static readonly Lazy<CursorMotionModel> SharedInstance = new(() => new CursorMotionModel());
    public static CursorMotionModel Instance => SharedInstance.Value;

    private readonly Dispatcher _dispatcher;
    private readonly Action _wakeAction;
    private readonly Action _clickAction;
    private readonly MouseHook.Handler _hookHandler;

    private DispatcherTimer? _timer;
    private long _packedCoords;
    private int _isButtonDownAtomic;
    private bool _isDormant = true;
    private bool _isSuspended;
    private bool _isExternalDrag;
    private bool _disposed;

    private int _lastX = int.MinValue;
    private int _lastY = int.MinValue;
    private long _lastTickTimestamp;
    private double _scaleVelocity;

    private double _idleDurationSec;
    private double _breathingElapsedSec;

    private double _idleThresholdSec = 0.500; // 500ms default idle threshold
    private bool _customIdleThresholdSet;

    public bool IsEnabled { get; private set; }

    /// <summary>Whether idle breathing (Priority 4) is allowed to activate when stationary.</summary>
    public bool IsBreathingEnabled { get; private set; } = true;

    /// <summary>Current state of the motion model and animation state machine.</summary>
    public CursorMotionState CurrentState { get; private set; } = CursorMotionState.Dormant;

    /// <summary>Current smoothed cursor scale factor (e.g. 1.000 to 1.060).</summary>
    public double CurrentScale { get; private set; } = 1.0;

    /// <summary>Target scale factor calculated from velocity or breathing oscillation.</summary>
    public double TargetScale { get; private set; } = 1.0;

    /// <summary>Smoothed horizontal velocity in physical pixels per second.</summary>
    public double VelocityX { get; private set; }

    /// <summary>Smoothed vertical velocity in physical pixels per second.</summary>
    public double VelocityY { get; private set; }

    /// <summary>Scalar cursor speed in physical pixels per second.</summary>
    public double Speed { get; private set; }

    /// <summary>Latest physical X desktop coordinate.</summary>
    public int CurrentX { get; private set; }

    /// <summary>Latest physical Y desktop coordinate.</summary>
    public int CurrentY { get; private set; }

    /// <summary>True when the motion model is parked and the timer is stopped.</summary>
    public bool IsDormant => Volatile.Read(ref _isDormant);

    /// <summary>True when a mouse button is held down or external drag is active.</summary>
    public bool IsDragging => Volatile.Read(ref _isButtonDownAtomic) != 0 || _isExternalDrag;

    /// <summary>Idle duration (seconds) required before entering breathing state (default 500 ms).</summary>
    public double IdleThresholdSec
    {
        get => _idleThresholdSec;
        set
        {
            _idleThresholdSec = value;
            _customIdleThresholdSet = true;
        }
    }

    public CursorMotionModel(Dispatcher? dispatcher = null)
    {
        _dispatcher = dispatcher ?? Application.Current?.Dispatcher ?? Dispatcher.CurrentDispatcher;
        _wakeAction = StartTimerFromHook;
        _clickAction = OnClickFromHook;
        _hookHandler = OnHookMouse;

        // Initialize coordinates to current OS cursor position
        NativeMethods.GetCursorPos(out NativeMethods.POINT pt);
        _packedCoords = PackCoords(pt.X, pt.Y);
        CurrentX = pt.X;
        CurrentY = pt.Y;
        _lastX = pt.X;
        _lastY = pt.Y;

        try
        {
            SystemEvents.SessionSwitch += OnSessionSwitch;
            SystemEvents.PowerModeChanged += OnPowerModeChanged;
        }
        catch
        {
            // Non-interactive or test runner environment
        }
    }

    public void SetEnabled(bool enabled)
    {
        if (_disposed) return;
        if (enabled == IsEnabled) return;
        IsEnabled = enabled;

        if (enabled)
        {
            Reset();
            MouseHook.Subscribe(HookOwner, MouseEvents.Move | MouseEvents.Buttons, _hookHandler);
        }
        else
        {
            MouseHook.Unsubscribe(HookOwner);
            StopTimer();
            Reset();
        }
    }

    public void SetBreathingEnabled(bool enabled)
    {
        IsBreathingEnabled = enabled;
        if (!enabled && CurrentState == CursorMotionState.Breathing)
        {
            TransitionTo(CursorMotionState.Dormant);
            CurrentScale = GetScaleMin();
            TargetScale = CurrentScale;
            _scaleVelocity = 0.0;
        }
    }

    public void SetExternalDrag(bool isDragging)
    {
        _isExternalDrag = isDragging;
        if (isDragging && CurrentState == CursorMotionState.Breathing)
        {
            // Preempt breathing immediately when external drag starts
            TransitionTo(CursorMotionState.Dragging);
            _idleDurationSec = 0.0;
            _breathingElapsedSec = 0.0;
        }
    }

    public void SetSuspended(bool suspended)
    {
        _isSuspended = suspended;
        if (suspended)
        {
            TransitionTo(CursorMotionState.Suspended);
            StopTimer();
            CurrentScale = GetScaleMin();
            TargetScale = CurrentScale;
            _scaleVelocity = 0.0;
            VelocityX = 0.0;
            VelocityY = 0.0;
            Speed = 0.0;
            _idleDurationSec = 0.0;
            _breathingElapsedSec = 0.0;
            MotionUpdated?.Invoke(CurrentScale, Speed, CurrentX, CurrentY, CurrentState);
        }
        else
        {
            TransitionTo(CursorMotionState.Dormant);
            Reset();
        }
    }

    public void Reset()
    {
        NativeMethods.GetCursorPos(out NativeMethods.POINT pt);
        Reset(pt.X, pt.Y);
    }

    public void Reset(int x, int y)
    {
        double scaleMin = GetScaleMin();
        CurrentScale = scaleMin;
        TargetScale = scaleMin;
        _scaleVelocity = 0.0;
        VelocityX = 0.0;
        VelocityY = 0.0;
        Speed = 0.0;
        _idleDurationSec = 0.0;
        _breathingElapsedSec = 0.0;

        CurrentX = x;
        CurrentY = y;
        _lastX = x;
        _lastY = y;
        _lastTickTimestamp = Stopwatch.GetTimestamp();
        Interlocked.Exchange(ref _packedCoords, PackCoords(x, y));

        TransitionTo(CursorMotionState.Dormant);
        Volatile.Write(ref _isDormant, true);
    }

    private void TransitionTo(CursorMotionState newState)
    {
        if (CurrentState == newState) return;
        CursorMotionState oldState = CurrentState;
        CurrentState = newState;
        StateChanged?.Invoke(oldState, newState);
    }

    private bool OnHookMouse(MouseHook.MouseEvent e)
    {
        if (e.IsInjected) return false;

        long packed = PackCoords(e.X, e.Y);
        Interlocked.Exchange(ref _packedCoords, packed);

        // Handle button transitions for Priority 1 (Click) and Priority 3 (Drag suppression)
        if (e.Message == WM_LBUTTONDOWN || e.Message == WM_RBUTTONDOWN || e.Message == WM_MBUTTONDOWN)
        {
            Interlocked.Exchange(ref _isButtonDownAtomic, 1);
            _dispatcher.BeginInvoke(_clickAction);
        }
        else if (e.Message == WM_LBUTTONUP || e.Message == WM_RBUTTONUP || e.Message == WM_MBUTTONUP)
        {
            Interlocked.Exchange(ref _isButtonDownAtomic, 0);
        }

        // Wake animation loop from dormant state if needed
        if (Volatile.Read(ref _isDormant))
        {
            Volatile.Write(ref _isDormant, false);
            _dispatcher.BeginInvoke(_wakeAction, DispatcherPriority.Render);
        }

        return false;
    }

    private void OnClickFromHook()
    {
        // Priority 1: Independent Click Event
        ClickOccurred?.Invoke(CurrentX, CurrentY);
    }

    private void StartTimerFromHook()
    {
        if (!IsEnabled || _disposed) return;

        if (_timer == null)
        {
            _timer = new DispatcherTimer(DispatcherPriority.Render, _dispatcher)
            {
                Interval = TimeSpan.FromMilliseconds(FrameIntervalMs)
            };
            _timer.Tick += OnFrameTick;
        }

        UnpackCoords(Interlocked.Read(ref _packedCoords), out int curX, out int curY);
        _lastX = curX;
        _lastY = curY;
        CurrentX = curX;
        CurrentY = curY;
        _lastTickTimestamp = Stopwatch.GetTimestamp();

        if (!_timer.IsEnabled)
        {
            _timer.Start();
        }
    }

    private void StopTimer()
    {
        try
        {
            _timer?.Stop();
        }
        catch
        {
        }
        Volatile.Write(ref _isDormant, true);
    }

    private void OnFrameTick(object? sender, EventArgs e)
    {
        if (!IsEnabled || _disposed)
        {
            StopTimer();
            return;
        }

        long now = Stopwatch.GetTimestamp();
        double dtSec = (now - _lastTickTimestamp) / (double)Stopwatch.Frequency;
        _lastTickTimestamp = now;

        UnpackCoords(Interlocked.Read(ref _packedCoords), out int curX, out int curY);
        bool isButtonDown = Volatile.Read(ref _isButtonDownAtomic) != 0 || _isExternalDrag;
        Step(dtSec, curX, curY, isButtonDown);
    }

    /// <summary>
    /// Core simulation step: evaluates state hierarchy arbitration, EMA velocity,
    /// critically damped spring physics, and idle breathing.
    /// </summary>
    public void Step(double dtSec, int curX, int curY, bool isButtonDown = false)
    {
        CurrentX = curX;
        CurrentY = curY;

        if (dtSec <= 0.0001) return;

        // Suspended Check: Screen lock, Display off, Full-screen Game Mode
        if (_isSuspended || IsGameModeOrFullScreenActive())
        {
            if (CurrentState != CursorMotionState.Suspended)
            {
                TransitionTo(CursorMotionState.Suspended);
            }
            CurrentScale = GetScaleMin();
            TargetScale = CurrentScale;
            _scaleVelocity = 0.0;
            VelocityX = 0.0;
            VelocityY = 0.0;
            Speed = 0.0;
            _idleDurationSec = 0.0;
            _breathingElapsedSec = 0.0;
            _lastX = curX;
            _lastY = curY;
            StopTimer();
            MotionUpdated?.Invoke(CurrentScale, Speed, curX, curY, CurrentState);
            return;
        }

        if (_lastX == int.MinValue)
        {
            _lastX = curX;
            _lastY = curY;
        }

        int dx = curX - _lastX;
        int dy = curY - _lastY;

        // Warp jump filtering
        bool isWarp = Math.Abs(dx) > WarpThresholdPx || Math.Abs(dy) > WarpThresholdPx || dtSec > MaxDtSec;
        if (isWarp)
        {
            _lastX = curX;
            _lastY = curY;
            dx = 0;
            dy = 0;
        }
        else
        {
            _lastX = curX;
            _lastY = curY;
        }

        // EMA velocity calculation
        double instVx = dx / dtSec;
        double instVy = dy / dtSec;
        double k = 1.0 - Math.Exp(-dtSec / TauSec);
        VelocityX += (instVx - VelocityX) * k;
        VelocityY += (instVy - VelocityY) * k;
        Speed = Math.Sqrt(VelocityX * VelocityX + VelocityY * VelocityY);

        bool hasDisplacement = (dx != 0 || dy != 0);
        bool isDragging = isButtonDown || _isExternalDrag;

        double scaleMin = GetScaleMin();
        double scaleMax = GetScaleMax();
        if (scaleMax < scaleMin) scaleMax = scaleMin;

        double sensitivity = GetSensitivity();
        double damping = GetDamping();

        // --- STATE PRIORITY ARBITRATION HIERARCHY ---

        if (isDragging)
        {
            // PRIORITY 3: Dragging Operation
            // Breathing is strictly SUPPRESSED.
            // Velocity tracking for Parallax Dragging is preserved.
            _idleDurationSec = 0.0;
            _breathingElapsedSec = 0.0;

            TransitionTo(CursorMotionState.Dragging);

            // Fix for duplicate cursor lag: disable movement scaling, restrict overlay to breathing
            TargetScale = scaleMin;

            SolveSpring(TargetScale, damping, dtSec);
        }
        else if (hasDisplacement || Speed >= DormantSpeedEpsilon)
        {
            // PRIORITY 2: Active Mouse Movement
            // Breathing is PREEMPTED INSTANTLY with zero latency.
            _idleDurationSec = 0.0;
            _breathingElapsedSec = 0.0;

            TransitionTo(CursorMotionState.Moving);

            // Fix for duplicate cursor lag: disable movement scaling, restrict overlay to breathing
            TargetScale = scaleMin;

            SolveSpring(TargetScale, damping, dtSec);
        }
        else
        {
            // Cursor is stationary on desk (dx=0, dy=0, Speed < DormantSpeedEpsilon, no buttons held)

            if (CurrentState == CursorMotionState.Moving)
            {
                TransitionTo(CursorMotionState.Dormant);
                _idleDurationSec = 0.0;
                _breathingElapsedSec = 0.0;
            }

            if (CurrentState == CursorMotionState.Breathing)
            {
                // PRIORITY 4: Active Idle Breathing
                _breathingElapsedSec += dtSec;

                double delta = GetBreatheScaleDelta();
                double period = GetBreatheCycleDurationSec();

                // Smooth cosine wave: starts at 1.000x at t=0, expands to (1.000 + delta) at t=T/2
                double phase = 2.0 * Math.PI * (_breathingElapsedSec / period);
                CurrentScale = scaleMin + delta * ((1.0 - Math.Cos(phase)) / 2.0);
                TargetScale = CurrentScale;
            }
            else
            {
                // CurrentState is Dormant (accumulating idle time)
                // If scale is still settling from previous motion, continue solving spring towards scaleMin
                if (Math.Abs(CurrentScale - scaleMin) >= DormantScaleEpsilon || Math.Abs(_scaleVelocity) >= DormantVelocityEpsilon)
                {
                    TargetScale = scaleMin;
                    SolveSpring(TargetScale, damping, dtSec);
                }
                else
                {
                    CurrentScale = scaleMin;
                    TargetScale = scaleMin;
                    _scaleVelocity = 0.0;
                }

                _idleDurationSec += dtSec;
                double idleThreshold = GetIdleThresholdSec();

                if (IsBreathingEnabled && _idleDurationSec >= idleThreshold)
                {
                    TransitionTo(CursorMotionState.Breathing);
                    _breathingElapsedSec = 0.0;
                    CurrentScale = scaleMin;
                    TargetScale = scaleMin;
                }
                else if (!IsBreathingEnabled && Math.Abs(CurrentScale - scaleMin) < DormantScaleEpsilon)
                {
                    StopTimer();
                }
            }
        }

        MotionUpdated?.Invoke(CurrentScale, Speed, curX, curY, CurrentState);
    }

    private void SolveSpring(double targetScale, double omega, double dtSec)
    {
        double y0 = CurrentScale - targetScale;
        double c2 = _scaleVelocity + omega * y0;
        double decay = Math.Exp(-omega * dtSec);

        CurrentScale = targetScale + (y0 + c2 * dtSec) * decay;
        _scaleVelocity = (c2 - omega * (y0 + c2 * dtSec)) * decay;
    }

    private double GetIdleThresholdSec()
    {
        if (_customIdleThresholdSet) return _idleThresholdSec;
        int secs = TuningRegistry.Int(TuningRegistry.CursorBreatheIdleSeconds);
        return secs > 0 ? secs : _idleThresholdSec;
    }

    private static double GetScaleMin()
    {
        int minPct = TuningRegistry.Int(TuningRegistry.CursorScaleMinPercent);
        return (minPct > 0 ? minPct : 100) / 100.0;
    }

    private static double GetScaleMax()
    {
        int maxPct = TuningRegistry.Int(TuningRegistry.CursorScaleMaxPercent);
        return (maxPct > 0 ? maxPct : 106) / 100.0;
    }

    private static double GetSensitivity()
    {
        double s = TuningRegistry.Int(TuningRegistry.CursorScaleSensitivity);
        return s > 0 ? s : 35.0;
    }

    private static double GetDamping()
    {
        double d = TuningRegistry.Int(TuningRegistry.CursorScaleDamping);
        return d > 0 ? d : 18.0;
    }

    private static double GetBreatheScaleDelta()
    {
        int deltaPct = TuningRegistry.Int(TuningRegistry.CursorBreatheScaleDelta);
        return (deltaPct > 0 ? deltaPct : 3) / 100.0;
    }

    private static double GetBreatheCycleDurationSec()
    {
        int ms = TuningRegistry.Int(TuningRegistry.CursorBreatheCycleDurationMs);
        return (ms > 0 ? ms : 3400) / 1000.0;
    }

    private static bool IsGameModeOrFullScreenActive()
    {
        IntPtr fg = NativeMethods.GetForegroundWindow();
        if (fg == IntPtr.Zero) return false;

        if (WindowFilter.IsOrdinaryAppWindow(fg) && WindowFilter.IsFullScreenOnItsMonitor(fg))
        {
            return true;
        }

        return false;
    }

    private void OnSessionSwitch(object sender, SessionSwitchEventArgs e)
    {
        if (e.Reason == SessionSwitchReason.SessionLock)
        {
            SetSuspended(true);
        }
        else if (e.Reason == SessionSwitchReason.SessionUnlock)
        {
            SetSuspended(false);
        }
    }

    private void OnPowerModeChanged(object sender, PowerModeChangedEventArgs e)
    {
        if (e.Mode == PowerModes.Suspend)
        {
            SetSuspended(true);
        }
        else if (e.Mode == PowerModes.Resume)
        {
            SetSuspended(false);
        }
    }

    private static long PackCoords(int x, int y)
    {
        return ((long)x << 32) | (long)(uint)y;
    }

    private static void UnpackCoords(long packed, out int x, out int y)
    {
        x = (int)(packed >> 32);
        y = (int)(uint)(packed & 0xFFFFFFFFL);
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        try
        {
            SystemEvents.SessionSwitch -= OnSessionSwitch;
            SystemEvents.PowerModeChanged -= OnPowerModeChanged;
        }
        catch
        {
        }

        SetEnabled(false);
        StopTimer();
        _timer = null;
    }
}

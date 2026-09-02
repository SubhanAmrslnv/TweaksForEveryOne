using System;
using System.Diagnostics;
using WindowTweaks.Core;

namespace WindowTweaks.Features;

/// <summary>
/// Hold the middle button and drag to pan any scrollable window, like the hand tool in an image
/// editor.
///
/// THE HARD PART IS NOT PANNING - IT IS NOT BREAKING THE MIDDLE BUTTON. The middle button already
/// means something almost everywhere: it opens a link in a new tab, closes a tab, pastes on X11
/// remote sessions, and starts autoscroll in Firefox. This feature has to swallow the button-down
/// (it cannot know yet whether a pan is coming) and then hand a plain click back if no pan happened.
///
/// HOW THE REPLAY USED TO BREAK, since it is the reported "middle click breaks opening and closing
/// Chrome tabs": the replayed click was recognised by COUNTING - "ignore the next two middle-button
/// events". Any unrelated event arriving in between shifted the count, after which a real click was
/// eaten and the browser never saw it. Now every synthetic event this app produces carries
/// NativeMethods.SyntheticTag in dwExtraInfo and arrives with MouseEvent.IsOurs set, so recognising
/// the replay is exact and cannot desynchronise.
///
/// THE GESTURE IS: hold, or move. A middle click shorter than the hold threshold that never moved is
/// replayed untouched, so tab-close and open-in-new-tab work exactly as they always did. Anything
/// longer, or anything that moves, is a pan and the click is never delivered.
/// </summary>
public class GrabPanFeature : IDisposable
{
    private const string HookOwner = nameof(GrabPanFeature);

    private const int VK_MBUTTON = 0x04;

    /// <summary>Movement beyond this many pixels declares a pan, however briefly the button was held.</summary>
    private const int MoveThresholdPx = 6;

    private bool _pressed;
    private bool _panning;
    private int _anchorX;
    private int _anchorY;
    private long _pressedAt;

    /// <summary>Captured at button-down, so a slider moved mid-gesture cannot change it halfway.</summary>
    private int _holdMs;
    private int _stepPx;

    public bool IsEnabled { get; private set; }

    public void SetEnabled(bool enabled)
    {
        if (enabled == IsEnabled) return;
        IsEnabled = enabled;

        if (enabled)
        {
            Reset();
            MouseHook.Subscribe(HookOwner, MouseEvents.Buttons | MouseEvents.Move, OnMouse);
        }
        else
        {
            MouseHook.Unsubscribe(HookOwner);
            Reset();
        }
    }

    public void Toggle() => SetEnabled(!IsEnabled);

    private void Reset()
    {
        _pressed = false;
        _panning = false;
    }

    private bool OnMouse(MouseHook.MouseEvent e)
    {
        // The app's own replayed click, on its way to the application. Never touch it, and above all
        // never swallow it - swallowing the replay is what made middle-click dead in the browser.
        if (e.IsOurs) return false;

        switch (e.Message)
        {
            case NativeMethods.WM_MBUTTONDOWN:
                _pressed = true;
                _panning = false;
                _anchorX = e.X;
                _anchorY = e.Y;
                _pressedAt = Stopwatch.GetTimestamp();

                _holdMs = TuningRegistry.Int(TuningRegistry.GrabPanHoldMs);
                _stepPx = Math.Max(1, TuningRegistry.Int(TuningRegistry.GrabPanStep));

                // Swallowed, and this is unavoidable: whether this is a click or the start of a pan
                // is not knowable yet, and a button-down already delivered cannot be recalled.
                return true;

            case NativeMethods.WM_MOUSEMOVE:
                if (!_pressed) return false;

                // The button can be released without this hook seeing it - a UAC prompt, a lock
                // screen, a session switch. Without this check the feature would stay in pan mode
                // and scroll every window the pointer crossed.
                if ((NativeMethods.GetAsyncKeyState(VK_MBUTTON) & 0x8000) == 0)
                {
                    Reset();
                    return false;
                }

                Pan(e.X, e.Y);

                // Moves are never swallowed: the cursor has to keep moving on screen, or the gesture
                // feels like the pointer is stuck.
                return false;

            case NativeMethods.WM_MBUTTONUP:
                if (!_pressed) return false;

                bool wasPanning = _panning;
                Reset();

                // A press that never panned was a plain middle click, HOWEVER LONG IT WAS HELD. Hand
                // it back, tagged, so the browser - and this app's own middle-click-to-close - sees a
                // real click.
                //
                // Duration deliberately does not enter into it. Gating the replay on "shorter than
                // the hold threshold" is the obvious rule and it is wrong: a deliberate, unhurried
                // middle click easily lasts longer than 180 ms, and it would then be swallowed
                // entirely - a middle button that silently does nothing some of the time, which is
                // worse than the bug this feature was fixing. Panning needs movement anyway, so
                // "never moved" is the honest test for "this was a click".
                if (!wasPanning) SyntheticInput.MiddleClick();

                // Either way the PHYSICAL release is swallowed, because its matching press was.
                // Delivering an up with no down confuses applications that track button state.
                return true;

            default:
                return false;
        }
    }

    private void Pan(int x, int y)
    {
        int dx = x - _anchorX;
        int dy = y - _anchorY;

        if (!_panning)
        {
            double heldMs = (Stopwatch.GetTimestamp() - _pressedAt) / (double)Stopwatch.Frequency * 1000.0;

            // Two ways in, which is what makes the gesture feel right in both styles: flick the
            // mouse with the button down and 6 px is enough, or hold the button first and then any
            // movement at all counts. Either way it takes MOVEMENT - holding still never pans, and
            // that is what leaves a plain middle click intact.
            bool moved = Math.Abs(dx) > MoveThresholdPx || Math.Abs(dy) > MoveThresholdPx;
            bool heldLongEnough = heldMs >= _holdMs && (dx != 0 || dy != 0);

            if (!moved && !heldLongEnough) return;

            _panning = true;

            // Re-anchor at the moment panning starts, so the pixels spent deciding are not also
            // spent scrolling - otherwise the content jumps on the first frame.
            _anchorX = x;
            _anchorY = y;
            return;
        }

        // One wheel notch per _stepPx of travel, with the remainder left on the anchor so slow
        // movement accumulates instead of being rounded away.
        if (Math.Abs(dy) >= _stepPx)
        {
            int notches = dy / _stepPx;

            // Dragging DOWN should pull the content down, which is scrolling up - the hand-tool
            // convention, and the opposite of dragging a scrollbar.
            SyntheticInput.Wheel(-notches * 120);
            _anchorY += notches * _stepPx;
        }

        if (Math.Abs(dx) >= _stepPx)
        {
            int notches = dx / _stepPx;

            // Horizontal wheel is the other way round again: positive is to the right.
            SyntheticInput.WheelHorizontal(notches * 120);
            _anchorX += notches * _stepPx;
        }
    }

    public void Dispose()
    {
        SetEnabled(false);
    }
}

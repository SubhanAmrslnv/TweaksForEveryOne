#!/usr/bin/env bash
#
# Structural checks for the Linux port - the analogue of scripts/Check-Split.ps1
# on the Windows side.
#
# These assert things the compiler cannot: that the layering holds, that the
# render pipeline still has exactly one mouth, and that CMake and the tree agree
# with each other. Run from linux/ (ctest does this for you).
#
# Every check prints what it found rather than only that it failed, because a
# layering violation is only actionable if you know which file caused it.

set -u

cd "$(dirname "$0")/.." || exit 1

fails=0
note() { printf '  %s\n' "$1"; }
ok()   { printf 'ok    %s\n' "$1"; }
bad()  { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }

# ---------------------------------------------------------------------------
# 1. Layering. core/ is platform-independent and must stay that way: it may use
#    QtCore, and nothing else that knows what a display server is.
# ---------------------------------------------------------------------------
hits=$(grep -rn -E '#include[[:space:]]*[<"](xcb/|wayland-|pipewire/|pulse/|QtGui|QtWidgets|QWidget|QGuiApplication|platform/)' src/core 2>/dev/null || true)
if [ -n "$hits" ]; then
    bad "core/ includes a platform or GUI header"
    printf '%s\n' "$hits" | while read -r line; do note "$line"; done
else
    ok "core/ is free of platform and GUI headers"
fi

# ---------------------------------------------------------------------------
# 2. The render pipeline has one mouth. Only RenderQueue may call an adapter
#    mutator; everything else queues desired state. This is the invariant that
#    makes priority arbitration mean anything.
# ---------------------------------------------------------------------------
mutators='setWindowGeometry|setWindowAlpha|clearWindowAlpha|setWindowRegion|setWindowZOrder|setWindowState'
hits=$(grep -rn -E "(->|\.)($mutators)\(" src \
        --include='*.cpp' --include='*.h' 2>/dev/null \
        | grep -v '^src/core/RenderQueue.cpp:' \
        | grep -v '^src/core/PlatformAdapter.h:' \
        | grep -v '^src/platform/' || true)
if [ -n "$hits" ]; then
    bad "an adapter mutator is called from outside RenderQueue"
    printf '%s\n' "$hits" | while read -r line; do note "$line"; done
else
    ok "only RenderQueue calls adapter mutators"
fi

# ---------------------------------------------------------------------------
# 3. Two kinds of producer, and they must be told apart. A per-frame animator
#    only queues and the scheduler flushes for it; a one-shot producer must call
#    commit() itself, because the scheduler parks when nothing is animating and
#    a queued change with nobody to flush it is simply never applied.
# ---------------------------------------------------------------------------
hits=$(grep -rn -E '(->|\.)flush\(\)' src --include='*.cpp' 2>/dev/null \
        | grep -v '^src/core/AnimationScheduler.cpp:' \
        | grep -v '^src/core/RenderQueue.cpp:' || true)
if [ -n "$hits" ]; then
    bad "flush() is called outside the scheduler - one-shot producers want commit()"
    printf '%s\n' "$hits" | while read -r line; do note "$line"; done
else
    ok "flush() is called only by the scheduler"
fi

# ---------------------------------------------------------------------------
# 4. No grab-bag modules. A module name has to state a responsibility; a
#    function with no obvious home means the module it belongs to has not been
#    named yet.
# ---------------------------------------------------------------------------
hits=$(find src -type f \( -iname 'Util*' -o -iname 'Helper*' -o -iname 'Common*' -o -iname 'Misc*' \) 2>/dev/null || true)
if [ -n "$hits" ]; then
    bad "a grab-bag module exists"
    printf '%s\n' "$hits" | while read -r line; do note "$line"; done
else
    ok "no Utils/Helpers/Common/Misc module"
fi

# ---------------------------------------------------------------------------
# 5. No underscore in a module filename. This constraint belongs to the Windows
#    installer - build/Setup.cs unflattens '_' to '\' on extract - and it does
#    not apply to linux/ today. It is asserted anyway so the two trees cannot
#    diverge on it silently if they are ever packaged together.
# ---------------------------------------------------------------------------
hits=$(find src -type f \( -name '*.cpp' -o -name '*.h' \) -name '*_*' 2>/dev/null || true)
if [ -n "$hits" ]; then
    bad "a module filename contains an underscore"
    printf '%s\n' "$hits" | while read -r line; do note "$line"; done
else
    ok "no underscore in any module filename"
fi

# ---------------------------------------------------------------------------
# 6. CMake and the tree agree, in both directions. Half of this check is what
#    would have caught src/ui/SettingsWindow.cpp, a source CMake named for a
#    file that never existed - a hard configure failure that shipped.
# ---------------------------------------------------------------------------
# Comments are stripped first. Without that, this check reports a file that a
# comment merely MENTIONS - and the comment explaining why src/ui/*.cpp was
# removed is exactly such a mention, so the check failed on the very commit that
# fixed the thing it was written to catch.
cmake_code=$(sed 's/#.*$//' CMakeLists.txt 2>/dev/null)

missing=""
while read -r src_file; do
    [ -z "$src_file" ] && continue
    [ -f "$src_file" ] || missing="$missing $src_file"
done <<< "$(echo "$cmake_code" | grep -oE 'src/[A-Za-z0-9/]+[.]cpp' | sort -u)"
if [ -n "$missing" ]; then
    bad "CMakeLists.txt names a source that does not exist:$missing"
else
    ok "every source CMakeLists.txt names exists"
fi

orphans=""
while read -r src_file; do
    [ -z "$src_file" ] && continue
    if ! echo "$cmake_code" | grep -q "$src_file"; then
        orphans="$orphans $src_file"
    fi
done <<< "$(find src -name '*.cpp' | sort)"
if [ -n "$orphans" ]; then
    bad "a source is in the tree but in no CMake target:$orphans"
else
    ok "every source under src/ belongs to a target"
fi

# ---------------------------------------------------------------------------
# 7. install.sh must stay LF. A CRLF shebang fails on Linux with
#    'bad interpreter: /usr/bin/env bash^M', and it fails ONLY on a real Linux
#    box - never on the machine that committed it. Check it where it is cheap.
# ---------------------------------------------------------------------------
if command -v git > /dev/null 2>&1; then
    eol=$(git ls-files --eol install.sh 2>/dev/null || true)
    case "$eol" in
        *"w/lf"*) ok "install.sh is LF in the working tree" ;;
        "")       note "install.sh is not tracked by git; skipping the EOL check" ;;
        *)        bad "install.sh is not LF: $eol" ;;
    esac
fi

# ---------------------------------------------------------------------------
# 8. Every header guards itself once.
# ---------------------------------------------------------------------------
hits=""
while read -r hdr; do
    [ -z "$hdr" ] && continue
    n=$(grep -c '#pragma once' "$hdr" 2>/dev/null || echo 0)
    guard=$(grep -c '#ifndef' "$hdr" 2>/dev/null || echo 0)
    if [ "$n" != "1" ] && [ "$guard" = "0" ]; then
        hits="$hits $hdr"
    fi
done <<< "$(find src tests -name '*.h' 2>/dev/null | sort)"
if [ -n "$hits" ]; then
    bad "a header has no include guard:$hits"
else
    ok "every header is guarded"
fi

echo
if [ "$fails" -eq 0 ]; then
    echo "check-layers: all checks passed"
    exit 0
fi
echo "check-layers: $fails check(s) failed"
exit 1

#!/usr/bin/env bash
set -e

echo "==========================================="
echo " Installing TweakForEveryone (Linux Native)"
echo "==========================================="

ask_yes_no() {
    while true; do
        read -p "$1 [y/N]: " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* | "" ) return 1;;
            * ) echo "Please answer y or n.";;
        esac
    done
}

# Detect the package manager to help install dependencies if missing
if command -v apt &> /dev/null; then
    echo "[*] Debian/Ubuntu detected. Checking dependencies..."
    if ! command -v cmake &> /dev/null; then
        echo "[!] CMake not found. Please run: sudo apt install build-essential cmake qt6-base-dev libxcb1-dev"
        exit 1
    fi
elif command -v dnf &> /dev/null; then
    echo "[*] Fedora/RHEL detected."
elif command -v pacman &> /dev/null; then
    echo "[*] Arch Linux detected."
fi

# Build
if ask_yes_no "[?] Do you want to configure and build the daemon now?"; then
    echo "[*] Configuring CMake..."
    mkdir -p build
    cd build
    cmake .. -DCMAKE_BUILD_TYPE=Release

    echo "[*] Building the daemon..."
    make -j$(nproc)

    if ask_yes_no "[?] Do you want to install the daemon system-wide? (Requires sudo)"; then
        echo "[*] Installing the daemon..."
        sudo make install
    else
        echo "[*] Skipping system-wide installation."
    fi
    cd ..
else
    echo "[*] Skipping build step."
fi

# Setup DE Extensions
if ask_yes_no "[?] Do you want to install the Wayland extension for your Desktop Environment? (Needed for GNOME/KDE Wayland)"; then
    echo "[*] Detecting Desktop Environment..."
    if [[ "$XDG_CURRENT_DESKTOP" == *"GNOME"* ]]; then
        echo "[*] Installing GNOME Shell Extension..."
        EXT_DIR="$HOME/.local/share/gnome-shell/extensions/tweakforeveryone@linux.local"
        mkdir -p "$EXT_DIR"
        cp -r src/platform/gnome/* "$EXT_DIR/"
        echo "[*] Enabling GNOME Shell Extension..."
        gnome-extensions enable tweakforeveryone@linux.local || echo "[!] Could not enable extension automatically. Please enable it in GNOME Extensions."
    elif [[ "$XDG_CURRENT_DESKTOP" == *"KDE"* ]]; then
        # Guarded, because this branch used to abort the whole script.
        # `cp -r src/platform/kde/*` on a directory that does not exist returns
        # non-zero, and `set -e` at the top turns that into an exit - so every
        # KDE user lost the autostart step too, for a script that was never
        # written. Skip loudly instead.
        if [ -d src/platform/kde ] && [ -n "$(ls -A src/platform/kde 2>/dev/null)" ]; then
            echo "[*] Installing KDE KWin Script..."
            SCRIPT_DIR="$HOME/.local/share/kwin/scripts/tweakforeveryone"
            mkdir -p "$SCRIPT_DIR"
            cp -r src/platform/kde/* "$SCRIPT_DIR/"

            # Plasma 6 renamed both tools. KDE Neon has kpackagetool6/qdbus6 and
            # NOT the 5 names; a Plasma 5 system is the other way round. Detect
            # rather than pick, so one script serves both.
            if command -v kpackagetool6 &> /dev/null; then KPKG=kpackagetool6; else KPKG=kpackagetool5; fi
            if command -v qdbus6 &> /dev/null; then QDBUS=qdbus6; else QDBUS=qdbus; fi

            "$KPKG" --type=KWin/Script -u "$SCRIPT_DIR" || "$KPKG" --type=KWin/Script -i "$SCRIPT_DIR"
            "$QDBUS" org.kde.KWin /KWin reconfigure || true
        else
            echo "[!] No KWin script exists yet (src/platform/kde is absent or empty)."
            echo "[!] KDE Wayland is therefore unsupported for now - log in to a"
            echo "[!] 'Plasma (X11)' session, which needs no compositor extension."
        fi
    else
        echo "[*] DE is neither GNOME nor KDE, assuming X11/Cinnamon (No Wayland extension needed)."
    fi
else
    echo "[*] Skipping extension installation."
fi

# Autostart
if ask_yes_no "[?] Do you want to set up autostart so the daemon runs on login?"; then
    echo "[*] Setting up autostart..."
    mkdir -p "$HOME/.config/autostart"
    cat <<EOF > "$HOME/.config/autostart/tweaksd.desktop"
[Desktop Entry]
Type=Application
Exec=tweaksd
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=TweakForEveryone Daemon
Comment=Native Linux daemon for window tweaks
EOF
else
    echo "[*] Skipping autostart setup."
fi

echo "==========================================="
echo " Installation process finished!"
echo " If installed, you can start the daemon manually by running 'tweaksd' or logging out and back in."
echo "==========================================="

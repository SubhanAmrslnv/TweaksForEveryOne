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
        echo "[*] Installing KDE KWin Script..."
        SCRIPT_DIR="$HOME/.local/share/kwin/scripts/tweakforeveryone"
        mkdir -p "$SCRIPT_DIR"
        cp -r src/platform/kde/* "$SCRIPT_DIR/"
        kpackagetool5 --type=KWin/Script -u "$SCRIPT_DIR" || kpackagetool5 --type=KWin/Script -i "$SCRIPT_DIR"
        qdbus org.kde.KWin /KWin reconfigure || true
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

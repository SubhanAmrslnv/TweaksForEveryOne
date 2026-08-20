cmake_minimum_required(VERSION 3.16)
project(TweakForEveryoneLinux VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

# Qt6 Gui/Widgets are deliberately NOT required here.
#
# They used to be, solely so a `TweakUI` target could be declared over
# src/ui/SettingsWindow.cpp and src/ui/TrayIcon.cpp - two files that do not
# exist, which was one of the two reasons `cmake -B build` failed at configure
# time. The target is gone until those sources are real; when the settings
# window lands, add `Gui Widgets` back here together with it. Until then a
# headless box needs only qt6-base-dev's Core/DBus/Network.
find_package(Qt6 REQUIRED COMPONENTS Core DBus Network)

# AnimationScheduler runs its own std::thread. Without this, several toolchains
# link fine on the developer's machine and fail with `undefined reference to
# pthread_create` on someone else's.
find_package(Threads REQUIRED)

# CMake ships no FindXCB.cmake and this repository provides none, so
# `find_package(XCB REQUIRED ...)` could never succeed - the second configure-time
# failure. pkg-config is how libxcb actually advertises itself.
#
# The component list is what the X11 backend needs, not what it uses today:
# ewmh/icccm for _NET_* and WM_CLASS, randr for monitors and work areas, shape
# for roll-up clipping, xtest for pointer warp (cursor wrap), xfixes for pointer
# queries.
find_package(PkgConfig REQUIRED)
pkg_check_modules(XCB REQUIRED IMPORTED_TARGET
    xcb
    xcb-ewmh
    xcb-icccm
    xcb-randr
    xcb-shape
    xcb-xtest
    xcb-xfixes
)

# ---------------------------------------------------------------------------
# Core library - platform-independent. Must never include a platform header or
# a Qt GUI header; see linux/CLAUDE.md.
# ---------------------------------------------------------------------------
add_library(TweakCore
    src/core/AnimationScheduler.cpp
    src/core/RenderQueue.cpp
    src/core/Physics.cpp
    src/core/SnapGeometry.cpp
    src/core/VelocitySampler.cpp
    src/core/WeatherFetcher.cpp
)

target_include_directories(TweakCore PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(TweakCore PUBLIC Qt6::Network Qt6::Core Threads::Threads)

# X11 Platform Adapter
add_library(TweakPlatformX11
    src/platform/x11/X11Adapter.cpp
)
target_link_libraries(TweakPlatformX11 PUBLIC TweakCore PkgConfig::XCB)
target_include_directories(TweakPlatformX11 PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)

# DBus Daemon (Wayland backend)
add_library(TweakPlatformWayland
    src/platform/wayland/DBusDaemon.cpp
)
target_link_libraries(TweakPlatformWayland PUBLIC TweakCore Qt6::DBus)
target_include_directories(TweakPlatformWayland PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)

# Main executable
add_executable(tweaksd
    src/main.cpp
)

target_link_libraries(tweaksd PRIVATE
    TweakCore
    TweakPlatformX11
    TweakPlatformWayland
    Qt6::Core
)

# ---------------------------------------------------------------------------
# Tests. The pure core is testable without a display, which is the only kind of
# test worth having here - everything else needs a real session.
# ---------------------------------------------------------------------------
enable_testing()
add_subdirectory(tests)

# ---------------------------------------------------------------------------
# Install rules.
#
# CMake DOES NOT EXPAND `~`. The rules here used to say
# `DESTINATION ~/.local/share/gnome-shell/extensions/...`, which creates a
# literal directory named `~` under the install prefix and installs nothing
# where anyone would look for it. Per-user files are install.sh's job; CMake
# only places the binary and the system-wide defaults.
#
# config/ and src/platform/kde/ are guarded rather than assumed: both are
# referenced by this file and by install.sh, and neither exists yet.
# ---------------------------------------------------------------------------
install(TARGETS tweaksd DESTINATION bin)

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/config")
    install(DIRECTORY config/ DESTINATION /etc/tweakforeveryone)
endif()

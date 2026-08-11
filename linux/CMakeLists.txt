cmake_minimum_required(VERSION 3.16)
project(TweakForEveryoneLinux VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

# Find packages
find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets DBus Network)
find_package(XCB REQUIRED COMPONENTS xcb composite damage render randr fixes)

# Core library
add_library(TweakCore
    src/core/AnimationScheduler.cpp
    src/core/RenderQueue.cpp
    src/core/Physics.cpp
    src/core/SnapGeometry.cpp
    src/core/WeatherFetcher.cpp
)

target_include_directories(TweakCore PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(TweakCore PUBLIC Qt6::Network Qt6::Core)

# X11 Platform Adapter
add_library(TweakPlatformX11
    src/platform/x11/X11Adapter.cpp
)
target_link_libraries(TweakPlatformX11 PUBLIC TweakCore XCB::xcb)
target_include_directories(TweakPlatformX11 PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)

# DBus Daemon (Wayland backend)
add_library(TweakPlatformWayland
    src/platform/wayland/DBusDaemon.cpp
)
target_link_libraries(TweakPlatformWayland PUBLIC TweakCore Qt6::DBus)
target_include_directories(TweakPlatformWayland PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)

# Settings UI
add_library(TweakUI
    src/ui/SettingsWindow.cpp
    src/ui/TrayIcon.cpp
)
target_link_libraries(TweakUI PUBLIC Qt6::Widgets Qt6::Gui)
target_include_directories(TweakUI PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)

# Main executable
add_executable(tweaksd
    src/main.cpp
)

target_link_libraries(tweaksd PRIVATE
    TweakCore
    TweakPlatformX11
    TweakPlatformWayland
    TweakUI
    Qt6::Core
)

# Install rules
install(TARGETS tweaksd DESTINATION bin)
install(DIRECTORY config/ DESTINATION /etc/tweakforeveryone)
install(DIRECTORY src/platform/gnome/ DESTINATION ~/.local/share/gnome-shell/extensions/tweakforeveryone@linux.local)
install(DIRECTORY src/platform/kde/ DESTINATION ~/.local/share/kwin/scripts/tweakforeveryone)

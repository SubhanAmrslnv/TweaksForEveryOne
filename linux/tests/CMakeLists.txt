# Headless unit tests for the pure core.
#
# Everything here runs with no display, no compositor and no network, which is
# the whole point: the Windows side has no test runner at all because AutoHotkey
# gives it none, and the parts of this engine that are pure maths are exactly the
# parts whose bugs were invisible until someone dragged a window.
#
# No FetchContent, deliberately. Pulling Catch2 at configure time would mean the
# tree stops building on a machine with no internet, and the first thing this
# port has to be is buildable on a fresh Mint box. TestHarness.h is 60 lines.

set(TWEAK_TESTS
    test_physics
    test_renderqueue
    test_scheduler
)

foreach(name IN LISTS TWEAK_TESTS)
    add_executable(${name} ${name}.cpp)
    target_link_libraries(${name} PRIVATE TweakCore)
    target_include_directories(${name} PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/../src
    )
    add_test(NAME ${name} COMMAND ${name})
endforeach()

# Structural checks - the Check-Split.ps1 analogue. Bash is already required to
# run install.sh, so this costs no new dependency.
find_program(BASH_EXECUTABLE bash)
if(BASH_EXECUTABLE)
    add_test(NAME check_layers
             COMMAND ${BASH_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/../scripts/check-layers.sh
             WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/..)
endif()

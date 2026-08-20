#pragma once

// A deliberately tiny assertion harness.
//
// Catch2 or GoogleTest via FetchContent would need the network at configure
// time, and the first thing this tree has to be is buildable on a fresh Mint box
// with no internet. The whole harness is 60 lines and the tests read the same as
// they would under Catch2, so the trade is cheap. Swap it out if the suite ever
// needs fixtures or parameterised cases.

#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

namespace TweakTest {

inline int& failureCount() {
    static int n = 0;
    return n;
}

inline const char*& currentCase() {
    static const char* name = "";
    return name;
}

inline void fail(const char* file, int line, const std::string& what) {
    ++failureCount();
    std::fprintf(stderr, "FAIL  %s\n      %s:%d\n      %s\n", currentCase(), file, line,
                 what.c_str());
}

inline void beginCase(const char* name) {
    currentCase() = name;
}

// Absolute tolerance, not relative: every value compared here is an opacity in
// [0,1], a normalised curve output, or a speed in px/s, and a relative epsilon
// is meaningless at zero - which is exactly where several of these curves are
// pinned.
inline bool nearly(double a, double b, double eps = 1e-4) {
    return std::fabs(a - b) <= eps;
}

inline int summarise(const char* suite) {
    if (failureCount() == 0) {
        std::printf("PASS  %s\n", suite);
        return 0;
    }
    std::fprintf(stderr, "\n%d failure(s) in %s\n", failureCount(), suite);
    return 1;
}

} // namespace TweakTest

#define CASE(name) ::TweakTest::beginCase(name)

#define CHECK(cond)                                                            \
    do {                                                                       \
        if (!(cond)) {                                                         \
            ::TweakTest::fail(__FILE__, __LINE__, "expected: " #cond);         \
        }                                                                      \
    } while (0)

#define CHECK_NEAR(a, b, eps)                                                  \
    do {                                                                       \
        const double lhs_ = (a);                                               \
        const double rhs_ = (b);                                               \
        if (!::TweakTest::nearly(lhs_, rhs_, eps)) {                           \
            ::TweakTest::fail(__FILE__, __LINE__,                              \
                              std::string(#a " == " #b " : got ") +            \
                                  std::to_string(lhs_) + " want " +            \
                                  std::to_string(rhs_));                       \
        }                                                                      \
    } while (0)

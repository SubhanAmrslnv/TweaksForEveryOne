---
description: Universal guidelines for writing robust, high-quality, and defensive code across all languages.
---

# Defensive Programming & Quality Guidelines

When writing new features, scripts, or modifying existing code in any language (Python, JavaScript, Go, AutoHotkey, C++, etc.), strictly adhere to the following principles to prevent edge-case bugs and ensure high quality:

1. **Defensive Code & Edge-Case Handling**: 
   - Always anticipate missing variables, null/undefined values, array/map out-of-bounds errors, and unexpected state changes.
   - Rely heavily on `try / catch` blocks, explicit null-checks, bounds checking, and type validation before executing critical logic.
   - Fail gracefully rather than allowing unhandled exceptions to crash the application.

2. **Simple and Robust Logic**: 
   - Avoid overly complex logic, deep nesting, or heavy loops unless strictly necessary for performance.
   - Prioritize readable, highly stable, and maintainable code over "clever" but fragile solutions.
   - Keep functions small and focused on a single responsibility.

3. **Non-Destructive Integration**: 
   - New features must be written in an isolated, modular way.
   - Ensure minimal interference with the core architecture, existing hooks, or global state.
   - Do not override or remove existing functionality unless explicitly requested by the user.

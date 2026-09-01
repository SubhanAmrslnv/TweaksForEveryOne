# Language Constraint: No AutoHotkey (AHK)

Do not suggest, write, or use AutoHotkey (AHK) scripts for this project. The user has explicitly banned AHK because it is frequently flagged by antivirus software (like Bitdefender) as a false positive.

Instead, always use native languages for system utilities and window management:
- **C++ (Win32 API)**: Preferred for the lowest overhead, smallest footprint, and fully native execution.
- **C# (.NET)**: Acceptable if a higher-level framework or WPF UI is needed.

When implementing system hooks (like `SetWindowsHookEx`) or window manipulation, write pure C++ or C# code.

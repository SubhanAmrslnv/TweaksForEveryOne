#include <windows.h>

void ToggleAlwaysOnTop() {
    HWND activeWindow = GetForegroundWindow();
    if (activeWindow != NULL) {
        SetWindowPos(activeWindow, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
    }
}

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow) {
    // Register Shift+Alt+O. MOD_ALT=1, MOD_SHIFT=4. 'O' = 0x4F.
    if (!RegisterHotKey(NULL, 1, MOD_ALT | MOD_SHIFT, 0x4F)) {
        MessageBox(NULL, L"Failed to register hotkey!", L"Error", MB_OK | MB_ICONERROR);
        return 1;
    }

    // Register a quit hotkey: Shift+Alt+Q to close the app ('Q' = 0x51)
    RegisterHotKey(NULL, 2, MOD_ALT | MOD_SHIFT, 0x51);

    MessageBox(NULL, 
        L"The C++ Window Manager is running in the background!\n\n"
        L"1. Open Notepad or any app.\n"
        L"2. Press Shift + Alt + O to pin it Always-on-Top.\n"
        L"3. Press Shift + Alt + Q to exit this test program.", 
        L"C++ Test", MB_OK | MB_ICONINFORMATION);

    // The Background Message Loop
    // This uses 0% CPU while waiting for Windows to send us a hotkey event.
    MSG msg = {0};
    while (GetMessage(&msg, NULL, 0, 0) != 0) {
        if (msg.message == WM_HOTKEY) {
            if (msg.wParam == 1) { // Shift+Alt+O was pressed
                ToggleAlwaysOnTop();
            }
            else if (msg.wParam == 2) { // Shift+Alt+Q was pressed
                break; // Exit the while loop and close the program
            }
        }
    }

    return 0;
}

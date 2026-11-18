// Checks keyboard input the way games read it: DirectInput 8, foreground and
// non-exclusive, polled every frame. Logs every key that goes down or up, and
// the WM_KEYDOWN messages the window receives, to dinputtest.log next to the
// executable. Runs for the number of seconds given (default 20).
//
// Build: i686-w64-mingw32-gcc -O2 -o dinputtest.exe dinputtest.c -ldinput8 -ldxguid -mwindows
#define DIRECTINPUT_VERSION 0x0800
#include <windows.h>
#include <dinput.h>
#include <stdio.h>
#include <stdlib.h>

static FILE *g_log;

static LRESULT CALLBACK window_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    if (msg == WM_KEYDOWN) { fprintf(g_log, "WM_KEYDOWN vk=0x%02x scan=0x%02x\n", (unsigned)wp, (unsigned)((lp >> 16) & 0xff)); fflush(g_log); }
    if (msg == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

int WINAPI WinMain(HINSTANCE instance, HINSTANCE prev, LPSTR cmd, int show) {
    (void)prev; (void)show;
    g_log = fopen("dinputtest.log", "w");
    int seconds = (cmd && *cmd) ? atoi(cmd) : 20;
    if (seconds <= 0) seconds = 20;

    WNDCLASSW wc = {0};
    wc.lpfnWndProc = window_proc;
    wc.hInstance = instance;
    wc.lpszClassName = L"dinputtest";
    RegisterClassW(&wc);
    HWND hwnd = CreateWindowW(L"dinputtest", L"DirectInput test", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                              100, 100, 640, 400, NULL, NULL, instance, NULL);
    SetForegroundWindow(hwnd);

    IDirectInput8W *di = NULL;
    IDirectInputDevice8W *keyboard = NULL;
    HRESULT hr = DirectInput8Create(instance, DIRECTINPUT_VERSION, &IID_IDirectInput8W, (void **)&di, NULL);
    fprintf(g_log, "DirectInput8Create 0x%08lx\n", (unsigned long)hr);
    hr = IDirectInput8_CreateDevice(di, &GUID_SysKeyboard, &keyboard, NULL);
    fprintf(g_log, "CreateDevice 0x%08lx\n", (unsigned long)hr);
    IDirectInputDevice8_SetDataFormat(keyboard, &c_dfDIKeyboard);
    hr = IDirectInputDevice8_SetCooperativeLevel(keyboard, hwnd, DISCL_FOREGROUND | DISCL_NONEXCLUSIVE);
    fprintf(g_log, "SetCooperativeLevel 0x%08lx\n", (unsigned long)hr);
    fflush(g_log);

    BYTE previous[256] = {0}, state[256];
    DWORD start = GetTickCount();
    MSG msg;
    while (GetTickCount() - start < (DWORD)seconds * 1000) {
        while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageW(&msg); }
        hr = IDirectInputDevice8_GetDeviceState(keyboard, sizeof state, state);
        if (hr == DIERR_INPUTLOST || hr == DIERR_NOTACQUIRED) {
            HRESULT a = IDirectInputDevice8_Acquire(keyboard);
            static HRESULT last = 1;
            if (a != last) {
                HWND fg = GetForegroundWindow();
                WCHAR title[128] = L"", cls[128] = L"";
                GetWindowTextW(fg, title, 128);
                GetClassNameW(fg, cls, 128);
                DWORD pid = 0;
                GetWindowThreadProcessId(fg, &pid);
                fprintf(g_log, "Acquire 0x%08lx (foreground %p class \"%ls\" title \"%ls\" pid %lu, ours %p) at %lu ms\n", (unsigned long)a, (void *)fg, cls, title, (unsigned long)pid, (void *)hwnd, (unsigned long)(GetTickCount() - start));
                fflush(g_log); last = a;
            }
        } else if (SUCCEEDED(hr)) {
            for (int i = 0; i < 256; i++) {
                if ((state[i] & 0x80) != (previous[i] & 0x80)) {
                    fprintf(g_log, "DIK 0x%02x %s\n", i, (state[i] & 0x80) ? "down" : "up");
                    fflush(g_log);
                }
            }
            memcpy(previous, state, sizeof state);
        }
        Sleep(5);
    }
    fprintf(g_log, "done\n");
    fclose(g_log);
    return 0;
}

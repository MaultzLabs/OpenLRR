// Self-contained Win32 DirectDraw4 smoke benchmark (no LEGO data).
// Intentionally measures API wall time only; not a displayed FPS claim.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <ddraw.h>
#include <chrono>
#include <cstdio>
#include <algorithm>

static int failed(const char *stage, HRESULT hr) {
    std::printf("OPENLRR_DDRAW stage=%s code=%lu ok=0\n",
        stage, static_cast<unsigned long>(hr));
    return 2;
}

int main() {
    HINSTANCE h = GetModuleHandleA(nullptr);
    WNDCLASSA wc = {};
    wc.lpfnWndProc = DefWindowProcA;
    wc.hInstance = h;
    wc.lpszClassName = "OpenLRR_CI_DirectDraw4";
    if (!RegisterClassA(&wc)) return failed("register", HRESULT_FROM_WIN32(GetLastError()));
    HWND window = CreateWindowA(wc.lpszClassName, "CI-only DirectDraw smoke",
        WS_OVERLAPPEDWINDOW, 40, 40, 520, 420,
        nullptr, nullptr, h, nullptr);
    if (!window) return failed("window", HRESULT_FROM_WIN32(GetLastError()));
    ShowWindow(window, SW_SHOW);
    UpdateWindow(window);

    LPDIRECTDRAW dd1 = nullptr;
    HRESULT hr = DirectDrawCreate(nullptr, &dd1, nullptr);
    if (FAILED(hr)) return failed("create", hr);
    LPDIRECTDRAW4 dd4 = nullptr;
    hr = dd1->QueryInterface(IID_IDirectDraw4, reinterpret_cast<void **>(&dd4));
    dd1->Release();
    if (FAILED(hr)) return failed("query4", hr);
    hr = dd4->SetCooperativeLevel(window, DDSCL_NORMAL);
    if (FAILED(hr)) return failed("cooperative", hr);

    DDSURFACEDESC2 surface_desc = {};
    surface_desc.dwSize = sizeof(surface_desc);
    surface_desc.dwFlags = DDSD_CAPS;
    surface_desc.ddsCaps.dwCaps = DDSCAPS_PRIMARYSURFACE;
    LPDIRECTDRAWSURFACE4 primary = nullptr;
    hr = dd4->CreateSurface(&surface_desc, &primary, nullptr);
    if (FAILED(hr)) return failed("primary", hr);

    LPDIRECTDRAWCLIPPER clipper = nullptr;
    hr = dd4->CreateClipper(0, &clipper, nullptr);
    if (FAILED(hr)) return failed("clipper", hr);
    hr = clipper->SetHWnd(0, window);
    if (FAILED(hr)) return failed("clipper_hwnd", hr);
    hr = primary->SetClipper(clipper);
    if (FAILED(hr)) return failed("clipper_set", hr);

    DDSURFACEDESC2 back_desc = {};
    back_desc.dwSize = sizeof(back_desc);
    back_desc.dwFlags = DDSD_CAPS | DDSD_WIDTH | DDSD_HEIGHT;
    back_desc.dwWidth = 320;
    back_desc.dwHeight = 240;
    back_desc.ddsCaps.dwCaps = DDSCAPS_OFFSCREENPLAIN;
    LPDIRECTDRAWSURFACE4 back = nullptr;
    hr = dd4->CreateSurface(&back_desc, &back, nullptr);
    if (FAILED(hr)) return failed("offscreen", hr);

    POINT top = { 0, 0 };
    ClientToScreen(window, &top);
    RECT dst = {top.x, top.y, top.x + 320, top.y + 240};
    RECT src = {0, 0, 320, 240};
    int slow100 = 0, slow1000 = 0, successful = 0;
    double total_ms = 0.0, worst_ms = 0.0;
    const int attempts = 120;

    for (int i = 0; i < attempts; ++i) {
        MSG msg;
        while (PeekMessageA(&msg, nullptr, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessageA(&msg);
        }
        DDBLTFX fill = {};
        fill.dwSize = sizeof(fill);
        fill.dwFillColor = static_cast<DWORD>(i & 0xFF);
        hr = back->Blt(nullptr, nullptr, nullptr,
            DDBLT_WAIT | DDBLT_COLORFILL, &fill);
        if (FAILED(hr)) return failed("backfill", hr);
        auto begin = std::chrono::steady_clock::now();
        hr = primary->Blt(&dst, back, &src, DDBLT_WAIT, nullptr);
        auto end = std::chrono::steady_clock::now();
        const double ms = std::chrono::duration<double, std::milli>(end - begin).count();
        if (FAILED(hr)) return failed("present_blt", hr);
        ++successful;
        total_ms += ms;
        worst_ms = std::max(worst_ms, ms);
        if (ms > 100.0) ++slow100;
        if (ms > 1000.0) ++slow1000;
    }
    std::printf("OPENLRR_DDRAW ok=1 calls=%d mean_ms=%.4f worst_ms=%.4f slow100=%d slow1000=%d\n",
        successful, total_ms / successful, worst_ms, slow100, slow1000);
    back->Release();
    clipper->Release();
    primary->Release();
    dd4->Release();
    DestroyWindow(window);
    return 0;
}

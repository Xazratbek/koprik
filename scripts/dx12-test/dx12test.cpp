// A minimal Direct3D 12 program for checking a DirectX 12 path (D3DMetal)
// end to end: device, command queue, swap chain, render target views, a
// clear and a present every frame. It reports the adapter and the frame rate
// in the window title and in dx12test.log next to the executable, then exits.
//
// Build: x86_64-w64-mingw32-g++ -O2 -static dx12test.cpp -o dx12test.exe -ld3d12 -ldxgi -mwindows
// Run:   dx12test.exe [seconds]   (default 15)
#include <windows.h>
#include <d3d12.h>
#include <dxgi1_4.h>
#include <cmath>
#include <cstdio>
#include <cstdlib>

static const UINT kFrames = 2;
static FILE *g_log;

static void log_line(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vfprintf(g_log, fmt, args);
    va_end(args);
    fputc('\n', g_log);
    fflush(g_log);
}

static LRESULT CALLBACK window_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    if (msg == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

#define CHECK(expr) do { HRESULT hr_ = (expr); if (FAILED(hr_)) { log_line("FAILED %s: 0x%08lx", #expr, (unsigned long)hr_); return 1; } } while (0)

int WINAPI WinMain(HINSTANCE instance, HINSTANCE, LPSTR cmd, int) {
    g_log = fopen("dx12test.log", "w");
    if (!g_log) g_log = stderr;
    int seconds = (cmd && *cmd) ? atoi(cmd) : 15;
    if (seconds <= 0) seconds = 15;

    WNDCLASSW wc = {};
    wc.lpfnWndProc = window_proc;
    wc.hInstance = instance;
    wc.lpszClassName = L"dx12test";
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    RegisterClassW(&wc);
    HWND hwnd = CreateWindowW(L"dx12test", L"DX12 test", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                              CW_USEDEFAULT, CW_USEDEFAULT, 1280, 720, nullptr, nullptr, instance, nullptr);

    IDXGIFactory4 *factory = nullptr;
    CHECK(CreateDXGIFactory1(IID_PPV_ARGS(&factory)));
    IDXGIAdapter1 *adapter = nullptr;
    CHECK(factory->EnumAdapters1(0, &adapter));
    DXGI_ADAPTER_DESC1 desc;
    adapter->GetDesc1(&desc);
    char name[128];
    WideCharToMultiByte(CP_UTF8, 0, desc.Description, -1, name, sizeof name, nullptr, nullptr);
    log_line("adapter: %s, %llu MB video memory", name, (unsigned long long)(desc.DedicatedVideoMemory >> 20));

    ID3D12Device *device = nullptr;
    CHECK(D3D12CreateDevice(adapter, D3D_FEATURE_LEVEL_12_0, IID_PPV_ARGS(&device)));
    D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_12_2, D3D_FEATURE_LEVEL_12_1, D3D_FEATURE_LEVEL_12_0};
    D3D12_FEATURE_DATA_FEATURE_LEVELS fl = {3, levels, D3D_FEATURE_LEVEL_12_0};
    device->CheckFeatureSupport(D3D12_FEATURE_FEATURE_LEVELS, &fl, sizeof fl);
    log_line("device created, max feature level 0x%x", (unsigned)fl.MaxSupportedFeatureLevel);
    D3D12_FEATURE_DATA_D3D12_OPTIONS5 opt5 = {};
    if (SUCCEEDED(device->CheckFeatureSupport(D3D12_FEATURE_D3D12_OPTIONS5, &opt5, sizeof opt5)))
        log_line("raytracing tier: %d", (int)opt5.RaytracingTier);

    D3D12_COMMAND_QUEUE_DESC qd = {};
    ID3D12CommandQueue *queue = nullptr;
    CHECK(device->CreateCommandQueue(&qd, IID_PPV_ARGS(&queue)));

    DXGI_SWAP_CHAIN_DESC1 sd = {};
    sd.Width = 1280;
    sd.Height = 720;
    sd.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.SampleDesc.Count = 1;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.BufferCount = kFrames;
    sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
    IDXGISwapChain1 *sc1 = nullptr;
    CHECK(factory->CreateSwapChainForHwnd(queue, hwnd, &sd, nullptr, nullptr, &sc1));
    IDXGISwapChain3 *swap = nullptr;
    CHECK(sc1->QueryInterface(IID_PPV_ARGS(&swap)));

    D3D12_DESCRIPTOR_HEAP_DESC hd = {};
    hd.NumDescriptors = kFrames;
    hd.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV;
    ID3D12DescriptorHeap *heap = nullptr;
    CHECK(device->CreateDescriptorHeap(&hd, IID_PPV_ARGS(&heap)));
    UINT stride = device->GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_RTV);
    D3D12_CPU_DESCRIPTOR_HANDLE base = heap->GetCPUDescriptorHandleForHeapStart();
    ID3D12Resource *targets[kFrames];
    for (UINT i = 0; i < kFrames; i++) {
        CHECK(swap->GetBuffer(i, IID_PPV_ARGS(&targets[i])));
        D3D12_CPU_DESCRIPTOR_HANDLE h = {base.ptr + i * stride};
        device->CreateRenderTargetView(targets[i], nullptr, h);
    }

    ID3D12CommandAllocator *allocator = nullptr;
    CHECK(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&allocator)));
    ID3D12GraphicsCommandList *list = nullptr;
    CHECK(device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, allocator, nullptr, IID_PPV_ARGS(&list)));
    list->Close();
    ID3D12Fence *fence = nullptr;
    CHECK(device->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&fence)));
    HANDLE event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    UINT64 fence_value = 0;

    LARGE_INTEGER freq, start, last, now;
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&start);
    last = start;
    unsigned long frames = 0, total = 0;
    double best = 0, worst = 1e9, sum = 0;
    int samples = 0;
    MSG msg = {};
    for (;;) {
        while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) goto done;
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        QueryPerformanceCounter(&now);
        double t = double(now.QuadPart - start.QuadPart) / freq.QuadPart;
        if (t > seconds) break;

        UINT index = swap->GetCurrentBackBufferIndex();
        allocator->Reset();
        list->Reset(allocator, nullptr);
        D3D12_RESOURCE_BARRIER barrier = {};
        barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
        barrier.Transition.pResource = targets[index];
        barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
        barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_PRESENT;
        barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_RENDER_TARGET;
        list->ResourceBarrier(1, &barrier);
        float color[4] = {0.5f + 0.5f * (float)sin(t * 2.0), 0.3f, 0.5f + 0.5f * (float)cos(t * 1.3), 1.0f};
        D3D12_CPU_DESCRIPTOR_HANDLE rtv = {base.ptr + index * stride};
        list->ClearRenderTargetView(rtv, color, 0, nullptr);
        barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_RENDER_TARGET;
        barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_PRESENT;
        list->ResourceBarrier(1, &barrier);
        list->Close();
        ID3D12CommandList *lists[] = {list};
        queue->ExecuteCommandLists(1, lists);
        CHECK(swap->Present(0, 0));
        queue->Signal(fence, ++fence_value);
        if (fence->GetCompletedValue() < fence_value) {
            fence->SetEventOnCompletion(fence_value, event);
            WaitForSingleObject(event, INFINITE);
        }
        frames++;
        total++;

        double since = double(now.QuadPart - last.QuadPart) / freq.QuadPart;
        if (since >= 1.0) {
            double fps = frames / since;
            if (t > 2.0) {  // skip warm-up
                if (fps > best) best = fps;
                if (fps < worst) worst = fps;
                sum += fps;
                samples++;
            }
            wchar_t title[128];
            swprintf(title, 128, L"DX12 test - %.0f FPS", fps);
            SetWindowTextW(hwnd, title);
            log_line("fps %.1f", fps);
            frames = 0;
            last = now;
        }
    }
done:
    log_line("result: %lu frames, average %.1f FPS, min %.1f, max %.1f", total, samples ? sum / samples : 0.0,
             samples ? worst : 0.0, best);
    fclose(g_log);
    return 0;
}

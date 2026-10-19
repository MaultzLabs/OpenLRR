// Optional performance sampling for the 1999 main-menu DirectDraw path.
// Diagnostic-only unless 'menuperf.optimize' exists in the working directory.
// Uses no new libraries and produces no files unless 'menuperf.enable' exists.
#pragma once

#include "../../platform/windows.h"
#include <cstdint>
#include <cstdio>

namespace MenuPerf {

enum class Metric : unsigned { FlicLock, FlicDecode, FlicUnlock, FlicBlt, ImageBlt, Flip, MovieUpdate, WindowCoordinate, WindowBlt, FullscreenFlip, GdiAcquire, GdiStretch, GdiRelease, WindowPresentAccepted, WindowPresentBusy, WindowPresentError, GdiWindowAttempt, GdiPresentAccepted, GdiPresentFallback,
    FrameStartGap, FrameOutsideFlip, WindowBltSlow100ms, WindowBltSlow1000ms,
    OutsideFlipSlow100ms, OutsideFlipSlow1000ms,
    WindowBltThreadCpu, WindowBltSlowThreadCpu, WindowBltCpuUnavailable,
    WindowBltSlowLowCpu, Count };
struct Stat { std::uint64_t calls = 0; std::uint64_t ticks = 0; std::uint64_t maxTicks = 0; };

inline bool HasMarker(const char* name) {
    std::FILE* f = std::fopen(name, "rb");
    if (f) { std::fclose(f); return true; }
    return false;
}

// Absence of this marker keeps normal gameplay completely unchanged.
// The file can contain a whole number of seconds; default is 210, range 15..600.
inline unsigned ReadAutoTestSeconds() {
    std::FILE* f = std::fopen("menuperf.autotest", "rb");
    if (!f) return 0;
    unsigned requested = 210;
    if (std::fscanf(f, "%u", &requested) != 1) requested = 210;
    std::fclose(f);
    if (requested < 15) requested = 15;
    if (requested > 600) requested = 600;
    return requested;
}

struct State {
    unsigned autoTestSeconds = ReadAutoTestSeconds();
    LARGE_INTEGER autoTestStart = {};
    bool autoTestExitIssued = false;
    bool enabled = HasMarker("menuperf.enable");
    bool optimizeStaticFlic = HasMarker("menuperf.optimize");
    // Optional reversible Windows blit experiment; disabled unless explicitly enabled.
    bool nonblockingWindowBlt = HasMarker("menuperf.nowait");
    // Alternative 2D window presenter test. Original DirectDraw blit stays the default.
    bool gdiWindowPresent = HasMarker("menuperf.gdi");
    std::FILE* output = nullptr;
    LARGE_INTEGER frequency = {};
    LARGE_INTEGER intervalStart = {};
    // Flip-entry cadence and time outside DirectDraw_Flip. Both are sampled
    // only in diagnostic mode; neither proves what reached the display.
    LARGE_INTEGER lastFlipEntry = {};
    LARGE_INTEGER lastFlipExit = {};
    Stat counters[static_cast<unsigned>(Metric::Count)] = {};

    State() {
        if (!enabled) return;
        if (!::QueryPerformanceFrequency(&frequency) || frequency.QuadPart <= 0) {
            enabled = false;
            return;
        }
        ::QueryPerformanceCounter(&intervalStart);
        output = std::fopen("menuperf.csv", "w");
        if (!output) { enabled = false; return; }
        std::fprintf(output, "seconds,optimization,nowait,gdi,operation,calls,total_ms,max_ms\n");
        std::fflush(output);
    }
    ~State() { if (output) std::fclose(output); }
};

// One state per OpenLRR DLL, shared by all translation units (C++17).
inline State& Get() { static State state; return state; }
inline bool OptimizeStaticFlic() { return Get().optimizeStaticFlic; }
inline bool NonblockingWindowBlt() { return Get().nonblockingWindowBlt; }
inline bool GdiWindowPresent() { return Get().gdiWindowPresent; }
inline bool AutoTestEnabled() { return Get().autoTestSeconds != 0; }

// A completed sample is held in memory until the existing one-second CSV
// flush. Long operations get separate CALL counters (not interval maxima).
inline void RecordTickSample(Metric metric, std::uint64_t ticks) {
    State& state = Get();
    if (!state.enabled) return;
    Stat& stat = state.counters[static_cast<unsigned>(metric)];
    ++stat.calls;
    stat.ticks += ticks;
    if (ticks > stat.maxTicks) stat.maxTicks = ticks;
    if (metric == Metric::WindowBlt || metric == Metric::FrameOutsideFlip) {
        const double ms = static_cast<double>(ticks) * 1000.0 / state.frequency.QuadPart;
        const bool outside = metric == Metric::FrameOutsideFlip;
        if (ms > 100.0) {
            const Metric counter = outside ? Metric::OutsideFlipSlow100ms : Metric::WindowBltSlow100ms;
            ++state.counters[static_cast<unsigned>(counter)].calls;
        }
        if (ms > 1000.0) {
            const Metric counter = outside ? Metric::OutsideFlipSlow1000ms : Metric::WindowBltSlow1000ms;
            ++state.counters[static_cast<unsigned>(counter)].calls;
        }
    }
}

// Tracks two disjoint boundaries: entry-to-entry cadence, and previous Flip
// exit to current Flip entry (other work, scheduling, or waiting). Called
// only from DirectDraw_Flip; normal rendering behavior stays unchanged.
struct FrameBoundary {
    bool active;
    FrameBoundary() : active(Get().enabled) {
        if (!active) return;
        LARGE_INTEGER now = {};
        if (!::QueryPerformanceCounter(&now)) return;
        State& state = Get();
        if (state.lastFlipEntry.QuadPart > 0 && now.QuadPart >= state.lastFlipEntry.QuadPart)
            RecordTickSample(Metric::FrameStartGap,
                static_cast<std::uint64_t>(now.QuadPart - state.lastFlipEntry.QuadPart));
        if (state.lastFlipExit.QuadPart > 0 && now.QuadPart >= state.lastFlipExit.QuadPart)
            RecordTickSample(Metric::FrameOutsideFlip,
                static_cast<std::uint64_t>(now.QuadPart - state.lastFlipExit.QuadPart));
        state.lastFlipEntry = now;
    }
    ~FrameBoundary() {
        if (!active) return;
        ::QueryPerformanceCounter(&Get().lastFlipExit);
    }
};

// Correlate API-call wall duration with calling-thread CPU consumption.
// A low CPU fraction during a long call suggests a wait/deschedule, but
// does not identify the Wine, driver or compositor layer responsible.
inline bool ReadThreadCpu100ns(std::uint64_t& total) {
    FILETIME created = {}, exited = {}, kernel = {}, user = {};
    if (!::GetThreadTimes(::GetCurrentThread(), &created, &exited, &kernel, &user))
        return false;
    const std::uint64_t kernelTime =
        (static_cast<std::uint64_t>(kernel.dwHighDateTime) << 32) | kernel.dwLowDateTime;
    const std::uint64_t userTime =
        (static_cast<std::uint64_t>(user.dwHighDateTime) << 32) | user.dwLowDateTime;
    total = kernelTime + userTime;
    return true;
}

struct WindowBltCpuScope {
    bool active = Get().enabled;
    bool sampled = false;
    std::uint64_t firstCpu100ns = 0;
    LARGE_INTEGER begin = {};
    WindowBltCpuScope() {
        if (!active) return;
        sampled = ::QueryPerformanceCounter(&begin) != 0 &&
                  ReadThreadCpu100ns(firstCpu100ns);
    }
    ~WindowBltCpuScope() {
        if (!active) return;
        LARGE_INTEGER end = {};
        std::uint64_t lastCpu100ns = 0;
        if (!sampled || !::QueryPerformanceCounter(&end) ||
            !ReadThreadCpu100ns(lastCpu100ns) ||
            lastCpu100ns < firstCpu100ns || end.QuadPart < begin.QuadPart) {
            RecordTickSample(Metric::WindowBltCpuUnavailable, 0);
            return;
        }
        State& s = Get();
        const double wallMs = static_cast<double>(end.QuadPart - begin.QuadPart) *
                              1000.0 / s.frequency.QuadPart;
        const double cpuMs = static_cast<double>(lastCpu100ns - firstCpu100ns) / 10000.0;
        if (cpuMs > wallMs * 1.5 + 5.0) {
            RecordTickSample(Metric::WindowBltCpuUnavailable, 0);
            return;
        }
        const std::uint64_t cpuTicks = static_cast<std::uint64_t>(
            cpuMs * s.frequency.QuadPart / 1000.0);
        RecordTickSample(Metric::WindowBltThreadCpu, cpuTicks);
        if (wallMs > 1000.0) {
            RecordTickSample(Metric::WindowBltSlowThreadCpu, cpuTicks);
            if (cpuMs <= wallMs * 0.20)
                RecordTickSample(Metric::WindowBltSlowLowCpu, 0);
        }
    }
};

struct Scope {
    Metric metric;
    bool active;
    LARGE_INTEGER start = {};
    explicit Scope(Metric m) : metric(m), active(Get().enabled) {
        if (active) ::QueryPerformanceCounter(&start);
    }
    ~Scope() {
        if (!active) return;
        LARGE_INTEGER stop;
        ::QueryPerformanceCounter(&stop);
        const std::uint64_t ticks = stop.QuadPart >= start.QuadPart ?
            static_cast<std::uint64_t>(stop.QuadPart - start.QuadPart) : 0;
        RecordTickSample(metric, ticks);
    }
};

// Track the result of the actual DirectDraw window Blt. In nowait mode,
// logical frames may advance even when Wine declines a busy presentation.
inline void RecordWindowPresentOutcome(bool accepted, bool busy) {
    State& s = Get();
    if (!s.enabled) return;
    const Metric metric = accepted ? Metric::WindowPresentAccepted :
                          (busy ? Metric::WindowPresentBusy : Metric::WindowPresentError);
    ++s.counters[static_cast<unsigned>(metric)].calls;
}

// GDI success is recorded separately from attempted presentations and any
// DirectDraw fallback. A model must not infer smoothness from flip counts alone.
inline void RecordGdiWindowOutcome(bool succeeded) {
    State& s = Get();
    if (!s.enabled) return;
    const Metric metric = succeeded ? Metric::GdiPresentAccepted : Metric::GdiPresentFallback;
    ++s.counters[static_cast<unsigned>(metric)].calls;
}

// Called after each full frame presentation, so only one disk write per second.
inline void FlushIfDue() {
    State& s = Get();
    if (!s.enabled || !s.output) return;
    LARGE_INTEGER now;
    ::QueryPerformanceCounter(&now);
    const std::int64_t elapsed = now.QuadPart - s.intervalStart.QuadPart;
    if (elapsed < s.frequency.QuadPart) return;
    static const char* names[] = {
        "flic_surface_lock", "flic_decode", "flic_surface_unlock",
        "flic_backbuffer_blt", "image_blt", "frame_flip", "movie_update",
        "window_coordinate", "window_present_blt", "fullscreen_flip",
        "gdi_surface_getdc", "gdi_stretchblt", "gdi_surface_releasedc",
        "window_present_accepted", "window_present_busy", "window_present_error",
        "gdi_window_attempt", "gdi_present_accepted", "gdi_present_fallback",
        "frame_start_gap", "frame_outside_flip", "window_blt_over_100ms",
        "window_blt_over_1000ms", "frame_outside_over_100ms", "frame_outside_over_1000ms",
        "window_blt_thread_cpu", "window_blt_slow_thread_cpu",
        "window_blt_cpu_unavailable", "window_blt_slow_low_cpu"
    };
    const double seconds = static_cast<double>(elapsed) / s.frequency.QuadPart;
    const double factor = 1000.0 / s.frequency.QuadPart;
    for (unsigned i = 0; i < static_cast<unsigned>(Metric::Count); ++i) {
        const Stat& c = s.counters[i];
        std::fprintf(s.output, "%.3f,%d,%d,%d,%s,%llu,%.4f,%.4f\n",
                     seconds, s.optimizeStaticFlic ? 1 : 0,
                     s.nonblockingWindowBlt ? 1 : 0,
                     s.gdiWindowPresent ? 1 : 0, names[i],
                     static_cast<unsigned long long>(c.calls),
                     c.ticks * factor, c.maxTicks * factor);
        s.counters[i] = {};
    }
    std::fflush(s.output);
    s.intervalStart = now;
}

// Called on completed presentation frames. Benchmark mode starts timing on the
// first frame (not during graphics-device selection) and requests an ordinary
// window close on expiration. No process killing or registry changes.
inline void MaybeFinishAutoTest(HWND hwnd) {
    State& s = Get();
    if (s.autoTestSeconds == 0 || s.autoTestExitIssued || hwnd == nullptr || !s.enabled || s.frequency.QuadPart <= 0) return;
    LARGE_INTEGER now;
    if (!::QueryPerformanceCounter(&now)) return;
    // The Mac supervisor may request an early, graceful stop. This only
    // posts WM_CLOSE; it does not assert that Wine or the wrapper has exited.
    if (HasMarker("menuperf.stop")) {
        FlushIfDue();
        if (::PostMessageA(hwnd, WM_CLOSE, 0, 0)) {
            s.autoTestExitIssued = true;
            std::FILE* done = std::fopen("menuperf.finished", "w");
            if (done) {
                std::fprintf(done, "close_requested_by=supervisor_stop\n");
                std::fclose(done);
            }
        }
        return;
    }
    if (s.autoTestStart.QuadPart == 0) {
        s.autoTestStart = now;
        return;
    }
    const std::int64_t elapsed = now.QuadPart - s.autoTestStart.QuadPart;
    if (elapsed < static_cast<std::int64_t>(s.autoTestSeconds) * s.frequency.QuadPart) return;

    FlushIfDue();
    // The sentinel indicates the close request was successfully posted,
    // NOT necessarily that the entire Wine wrapper process exited.
    if (::PostMessageA(hwnd, WM_CLOSE, 0, 0)) {
        s.autoTestExitIssued = true;
        std::FILE* done = std::fopen("menuperf.finished", "w");
        if (done) {
            std::fprintf(done, "close_requested_after_seconds=%u\n", s.autoTestSeconds);
            std::fclose(done);
        }
    }
}

} // namespace MenuPerf

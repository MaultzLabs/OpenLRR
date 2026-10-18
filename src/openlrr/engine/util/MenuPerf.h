// Optional performance sampling for the 1999 main-menu DirectDraw path.
// Diagnostic-only unless 'menuperf.optimize' exists in the working directory.
// Uses no new libraries and produces no files unless 'menuperf.enable' exists.
#pragma once

#include "../../platform/windows.h"
#include <cstdint>
#include <cstdio>

namespace MenuPerf {

enum class Metric : unsigned { FlicLock, FlicDecode, FlicUnlock, FlicBlt, ImageBlt, Flip, MovieUpdate, WindowCoordinate, WindowBlt, FullscreenFlip, Count };
struct Stat { std::uint64_t calls = 0; std::uint64_t ticks = 0; std::uint64_t maxTicks = 0; };

inline bool HasMarker(const char* name) {
    std::FILE* f = std::fopen(name, "rb");
    if (f) { std::fclose(f); return true; }
    return false;
}

struct State {
    bool enabled = HasMarker("menuperf.enable");
    bool optimizeStaticFlic = HasMarker("menuperf.optimize");
    // Optional reversible Windows blit experiment; disabled unless explicitly enabled.
    bool nonblockingWindowBlt = HasMarker("menuperf.nowait");
    std::FILE* output = nullptr;
    LARGE_INTEGER frequency = {};
    LARGE_INTEGER intervalStart = {};
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
        std::fprintf(output, "seconds,optimization,nowait,operation,calls,total_ms,max_ms\n");
        std::fflush(output);
    }
    ~State() { if (output) std::fclose(output); }
};

// One state per OpenLRR DLL, shared by all translation units (C++17).
inline State& Get() { static State state; return state; }
inline bool OptimizeStaticFlic() { return Get().optimizeStaticFlic; }
inline bool NonblockingWindowBlt() { return Get().nonblockingWindowBlt; }

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
        Stat& s = Get().counters[static_cast<unsigned>(metric)];
        ++s.calls;
        s.ticks += ticks;
        if (ticks > s.maxTicks) s.maxTicks = ticks;
    }
};

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
        "window_coordinate", "window_present_blt", "fullscreen_flip"
    };
    const double seconds = static_cast<double>(elapsed) / s.frequency.QuadPart;
    const double factor = 1000.0 / s.frequency.QuadPart;
    for (unsigned i = 0; i < static_cast<unsigned>(Metric::Count); ++i) {
        const Stat& c = s.counters[i];
        std::fprintf(s.output, "%.3f,%d,%d,%s,%llu,%.4f,%.4f\n",
                     seconds, s.optimizeStaticFlic ? 1 : 0,
                     s.nonblockingWindowBlt ? 1 : 0, names[i],
                     static_cast<unsigned long long>(c.calls),
                     c.ticks * factor, c.maxTicks * factor);
        s.counters[i] = {};
    }
    std::fflush(s.output);
    s.intervalStart = now;
}
} // namespace MenuPerf

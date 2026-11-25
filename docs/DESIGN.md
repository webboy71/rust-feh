# Design Rationale: Building feh-rs From Scratch

Why a clean-room Rust clone instead of porting feh to Windows — and how to
approach it. This is background/context, not a task list. See `MVP.md` for scope.

## Why not port feh?

feh is ~30–40k lines of C, but most of that is option parsing and edge cases.
The deeper problem is coupling: feh is built around **X11** and Unix
conventions. A faithful port would require:

- Replacing the X11 layer (window creation, event loop, key/mouse handling,
  fullscreen, overlays) with Win32/GDI+/Direct2D or a cross-platform toolkit.
- Porting or adapting Imlib2 image loading/rendering on Windows.
- Handling path/terminal/config differences (`~/.fehbg`, shell scripts,
  signals, etc.).
- Rewriting or stubbing Unix-specific features: Xinerama/multi-monitor
  handling, wallpaper setting via `feh --bg-*`, IPC/command behaviours.
- Reworking the build system (Makefile assumptions, libcurl, libpng, …).

That is a real porting project, not a rebuild. A from-scratch clone gives a
cleaner codebase, native Windows behaviour, and no Cygwin/X-server baggage —
and lets us reinterpret Unix-isms idiomatically (see below).

## What "feh functionality" actually means

Split the surface into three waves:

### Core (MVP)
- Open an image; fit-to-window / 1:1 / free zoom
- Next/prev within a file list (args, globs, directories, `-r` recursive)
- Slideshow with `--slideshow-delay`
- Basic transforms: rotate L/R, flip, zoom, pan
- Fullscreen / borderless / fixed geometry
- Format support (PNG, JPEG, GIF, BMP, WebP, TIFF)

### Second wave
- Thumbnail/montage grid mode (`-t`, `-m`)
- Info overlay (`-I`), captions (`-c`)
- Sort options (`-S name|mtime|size`)
- EXIF orientation
- Reload on file change (`-R`)
- Custom key bindings from a config file
- Thumbnail cache

### Reinterpret for Windows (don't port literally)
- `--bg-*` wallpaper → `SystemParametersInfo(SPI_SETDESKWALLPAPER, …)` —
  actually *easier* on Windows.
- `--action` shell scripts → spawn `.bat` / `.ps1` / `.exe` with env vars
  (`FEH_FILE`, etc.).
- Xinerama multi-monitor → `EnumDisplayMonitors`.
- `~/.fehbg` → `%APPDATA%\…\config`.

## Stack choice: why Rust

| Goal | Pick |
|------|------|
| "Fast and light" ethos, safe | **Rust**: `winit` + `image` + `softbuffer` |
| Most native, minimal deps | C++: Win32 + WIC + Direct2D |
| Fastest to feature-complete | C#/.NET: WinUI 3 or WPF |
| Prototype only | Python + PySide6 |

For a feh-like feel we chose **Rust + winit + image + softbuffer**:
small binaries, no runtime, memory safety, and a CPU render path we fully
control. C++ Win32+WIC+Direct2D is the alternative if the absolute smallest
binary mattered more than development speed.

## Architecture sketch

```
main.rs
├── cli        // parse feh-compatible flags
├── filelist   // expand args, globs, dirs; sorting; recursion
├── decode     // format sniffing + decode (thread pool)
├── cache      // decoded frames, LRU
├── render     // fit/zoom/pan math, blit to surface
├── window     // winit event loop, fullscreen, geometry
├── input      // key/mouse → actions (bindable)
├── overlay    // (future) info text, captions, index numbers
└── actions    // (future) external command spawning
```

The key design point: **decouple the event loop from decoding** with a small
worker pool + LRU cache, so next/prev feels instant, like feh.

## Milestones (high level)

1. CLI + single image + fit/zoom/pan — proves the render path
2. File-list navigation + slideshow — the core UX
3. Transforms + fullscreen + keybindings
4. Thumbnail grid mode
5. Overlays, EXIF, cache, reload
6. Wallpaper + external actions (Windows reinterpretations)

Steps 1–3 are the "real" feh and are very achievable — roughly 3–6k lines.
(Detailed acceptance criteria live in `MVP.md`.)

## Gotchas worth knowing up front

- **Animated GIF/WebP:** feh shows the first frame by default; decide early
  whether to animate. MVP: first frame only.
- **Huge images:** decode-on-demand and downscale before blit, or you'll
  stutter on 50 MP files.
- **Zoom quality:** feh uses nearest-neighbour; match it for the same look.
- **CLI compatibility:** `feh --help` is large. Support the common flags and
  stub the rest with clear errors (never silently misinterpret).
- **Licensing:** feh's licence is permissive, but a clean-room clone sidesteps
  the question entirely — just don't copy code. License the new project
  MIT OR Apache-2.0.

## Non-goals of this document

This is rationale, not a spec. For flags, keybindings, acceptance criteria,
and repo layout, see `MVP.md`.

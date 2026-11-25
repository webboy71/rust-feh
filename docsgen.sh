#!/usr/bin/env bash
# bootstrap-feh-rs.sh — write the feh-rs repo scaffold.
# Usage: ./bootstrap-feh-rs.sh [target-dir]   (default: current directory)
set -euo pipefail

ROOT="${1:-.}"
mkdir -p "$ROOT/docs" "$ROOT/src" "$ROOT/tests/fixtures"
cd "$ROOT"

# ---------------------------------------------------------------- docs/MVP.md
cat > docs/MVP.md <<'MDEOF'
# feh-rs — MVP Specification

A fast, light image viewer for Windows, inspired by [feh](https://feh.finalrewind.org/).
This document defines the **minimum viable product**: the smallest build that is
genuinely useful day-to-day and proves the core architecture.

- **Status:** Draft
- **Target:** Windows 10/11, x86_64 (Linux/macOS bonus, not required for MVP)
- **Language:** Rust (edition 2021)

---

## 1. Goals

1. Open an image or a directory of images and page through them instantly.
2. Fit-to-window, 1:1, and free zoom with pan — the core viewing loop.
3. Slideshow mode.
4. Keyboard-driven, feh-like feel: no menus, no chrome, fast startup.
5. Clean architecture that later supports thumbnail grids, overlays, and
   external actions without rework.

## 2. Non-goals (MVP)

Explicitly **out of scope** for the first release — do not let these creep in:

- Thumbnail/montage grid mode (`-t`, `-m`)
- Info/caption overlays (`-I`, `-c`)
- Animated GIF/WebP playback (show first frame only, like feh)
- EXIF orientation and metadata display
- File-change reload (`-R`)
- Wallpaper setting (`--bg-*`)
- External action scripts (`-x`, `--action`)
- User keybinding config file
- Multiple windows
- GUI settings, menus, toolbars
- Network/URL loading

## 3. CLI surface

### Supported flags

| Flag | Long | Behaviour |
|------|------|-----------|
| `-r` | `--recursive` | Recurse into directories |
| `-f` | `--filelist <FILE>` | Read newline-separated paths from file (`-` = stdin) |
| `-S` | `--sort <KEY>` | `name` \| `mtime` \| `size` (default: arg order) |
| `-z` | `--randomize` | Shuffle file list at startup |
| `-D` | `--slideshow-delay <SECS>` | Auto-advance every N seconds |
| `-F` | `--fullscreen` | Start fullscreen |
| `-Z` | `--auto-zoom` | Zoom to fit small images up (default: fit-down only) |
| `-g` | `--geometry <WxH+X+Y>` | Initial window geometry |
| `-q` | `--quiet` | Suppress non-error output |
| `-h` | `--help` | Usage |
| `-V` | `--version` | Version |

### Positional arguments

- Files: opened directly.
- Directories: expanded to contained image files (non-recursive unless `-r`).
- Globs: expanded by the shell; if the shell doesn't expand (Windows), expand
  `*`/`?` internally on the final segment.
- Mixing is allowed: `feh-rs a.jpg dir/ b*.png`.

### Behaviour rules

- Unsupported/undecodable files are **skipped with a warning** to stderr,
  not fatal (matches feh).
- If the list is empty after expansion → exit code 1 with a clear message.
- Exit code 0 on normal quit.
- `--help` / `--version` exit 0 without opening a window.

### Recognised-but-unimplemented flags

Parse common feh flags we don't yet support and exit with:
`error: -x/--action is not yet implemented in feh-rs`
This avoids silent misinterpretation. Maintain the list in `cli.rs`.

## 4. Formats (MVP)

Via the `image` crate features:

- **Required:** JPEG, PNG, BMP, GIF (first frame), WebP (static), TIFF
- **Nice-to-have:** ICO, QOI (add if the crate features are cheap)

Format is detected by **content sniffing**, not extension.

## 5. Keybindings (default)

Chosen to match feh where known; verify against `man feh` before release and
adjust for parity. All bindings live in one table in `input.rs`.

| Key | Action |
|-----|--------|
| `n`, `Space`, `Right`, `Down`, `PageDown` | Next image |
| `p`, `Backspace`, `Left`, `Up`, `PageUp` | Previous image |
| `Home` / `End` | First / last image |
| `q`, `Esc` | Quit |
| `f` | Toggle fullscreen |
| `+` / `=` | Zoom in |
| `-` / `_` | Zoom out |
| `0` | Fit to window |
| `1` | Zoom to 100% (1:1) |
| Arrow keys (with Ctrl) | Pan |
| Mouse drag | Pan |
| Mouse wheel | Zoom in/out at cursor |
| Mouse double-click | Toggle fullscreen |
| `<` / `>` | Rotate left / right (90°) |
| `h` / `v` | Flip horizontal / vertical |
| `r` | Reset zoom, pan, rotation, flips |

> Note: arrow keys are dual-purpose (nav vs. pan). Resolution: arrows navigate
> by default; **Ctrl+arrows pan**. Document this clearly in `--help`.

## 6. Behaviour details

### Image list
- Built once at startup from CLI args + expansion + sorting + shuffle.
- Cursor wraps at both ends.
- For MVP, the list is static (no watch/reload).

### Zoom model
```rust
enum Zoom { Fit, OneToOne, Factor(f32) }
```
- `Fit`: smallest scale so the whole image is visible. Clamped to ≤1.0
  unless `-Z` (`--auto-zoom`).
- `OneToOne`: 1 image pixel = 1 screen pixel (accounting for DPI scale).
- `Factor(f)`: manual zoom; clamped to `[1/64, 64]`.
- Zoom in/out from `Fit` switches to `Factor` seeded at the current fit scale.
- **Nearest-neighbour scaling** for parity with feh's look (configurable later).

### Pan
- Only meaningful when scaled image exceeds viewport.
- Clamped so the image can't be dragged off-screen entirely.
- Reset to centre on: fit, 1:1, next/prev.

### Window
- Default: fit image, window sized to image (capped to ~90% of work area).
- Title: `filename — feh-rs` (or just `filename` in fullscreen).
- Background: black by default.
- DPI-aware (per-monitor v2).
- Fullscreen uses borderless fullscreen on the current monitor.

### Slideshow
- `-D SECS` starts a timer; advances forward, wrapping.
- Any navigation key resets the timer.
- Pause/resume is not in MVP. Keep it simple: timer runs, keys reset it,
  quit to stop.

### Rendering pipeline
- Decode → downscale-to-viewport (if larger) → blit to back buffer → present.
- Decoding runs on a small worker pool; the event loop never blocks on I/O.
- Adjacent images (prev/next) are **prefetched** into an LRU cache.
- Cache: decoded RGBA, budget ~256 MB or N=5 images, whichever is smaller.

## 7. Architecture

```
src/
├── main.rs        // wire-up: parse → build list → run app
├── cli.rs         // clap definition, flag validation, unimplemented-flag errors
├── filelist.rs    // expansion, globbing, recursion, sorting, shuffle
├── decode/
│   ├── mod.rs     // sniff format, decode to RGBA, orientation stub
│   └── worker.rs  // thread pool + request/response channels
├── cache.rs       // LRU of decoded images, budgeted
├── view.rs        // Zoom, pan, rotation, flip → viewport rect math
├── render.rs      // CPU blit into a softbuffer, nearest-neighbour
├── window.rs      // winit App, event loop, fullscreen, DPI, title
├── input.rs       // key/mouse → Action table
├── slideshow.rs   // timer tick → next
└── actions.rs     // enum Action + apply()
```

### Crate choices

| Concern | Crate | Why |
|---------|-------|-----|
| CLI | `clap` (derive) | Robust, good help output |
| Windowing | `winit` | Mature, cross-platform event loop |
| Present | `softbuffer` | CPU blit, nearest-neighbour, feh-like and simple |
| Decode | `image` | Broad format coverage behind features |
| Threads | `crossbeam-channel` + `std::thread` | Simple request/response pool |
| Cache | `lru` | Tiny, well-tested |
| Glob | `glob` | Windows-side expansion |
| Recurse | `walkdir` | Correct, symlink-safe |
| Errors | `anyhow` (app) + `thiserror` (lib) | Ergonomic |
| Logging | `log` + `env_logger` | `RUST_LOG=debug` |
| Shuffle | `rand` | `-z` |

> `softbuffer` keeps the render path under our control and trivially portable
> to Linux/macOS later. Swap in `pixels`/`wgpu` only if CPU blit proves too slow.

### Core types (sketch)

```rust
struct ImageList { items: Vec<PathBuf>, cursor: usize }
impl ImageList {
    fn current(&self) -> Option<&Path>;
    fn next(&mut self);      // wraps
    fn prev(&mut self);      // wraps
}

struct DecodedImage {
    rgba: Vec<u8>,           // straight RGBA for MVP
    width: u32,
    height: u32,
}

enum Zoom { Fit, OneToOne, Factor(f32) }

struct ViewState {
    zoom: Zoom,
    pan: (i32, i32),
    rotation: Rotation,      // R0 | R90 | R180 | R270
    flipped_h: bool,
    flipped_v: bool,
}

// Pure function — heavily unit-tested
fn viewport_rect(
    img: (u32, u32),
    win: (u32, u32),
    view: &ViewState,
    dpi_scale: f32,
) -> Rect;
```

`viewport_rect` is the heart of correctness and must be a **pure, testable**
function with no windowing dependency.

## 8. Milestones & acceptance criteria

### M0 — Scaffold
- `cargo run -- --help` prints full usage; `--version` works.
- CI: `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test`.

### M1 — Single image, fit/zoom/pan
- `feh-rs photo.jpg` opens a window showing the image fit to the window.
- `+`/`-`/`0`/`1` change zoom; result matches expected scale exactly.
- Ctrl+arrows and mouse-drag pan; image cannot be dragged fully off-screen.
- Resizing the window re-fits when zoom == Fit.
- **Acceptance:** viewport math covered by unit tests; manual smoke on
  landscape, portrait, tiny (16×16), and huge (8000×6000) images.

### M2 — Navigation & file list
- `feh-rs dir/` pages through images with `n`/`p`, wrapping.
- `feh-rs a.jpg b.png dir/` works; unsupported files skipped with warning.
- `-r`, `-f`, `-S`, `-z` behave as specified.
- Next/prev is perceptibly instant (prefetch working).
- **Acceptance:** integration test builds a temp dir, expands, asserts order
  for each `-S` mode and for `-r`.

### M3 — Fullscreen, transforms, slideshow
- `-F` and `f` toggle borderless fullscreen on current monitor.
- `<`/`>` rotate, `h`/`v` flip, `r` resets; all compose correctly.
- `-D 2` advances every 2s; nav keys reset the timer.
- **Acceptance:** rotation/flip math unit-tested against fixed matrices;
  slideshow verified with a 3-image fake clock test.

### M4 — Polish
- DPI-correct on 100%/125%/150%/200% displays.
- `-g WxH+X+Y` honoured.
- Clean stderr messages for: missing file, unreadable file, undecodable file,
  empty list, unimplemented flag.
- Binary builds in release with `#![windows_subsystem = "windows"]` gated on
  a feature so CLI errors still print from a console.

## 9. Testing strategy

- **Unit:** `viewport_rect` (all zoom modes, rotations, flips, clamping);
  `filelist` expansion/sorting/recursion; zoom factor clamping.
- **Integration:** headless — decode a fixture, compute viewport, assert
  rects; no window needed. Run in CI on Linux.
- **Golden image (optional):** render a fixed image+state to a buffer and
  compare against a checked-in PNG with a small tolerance.
- **Manual smoke checklist** in `docs/SMOKE.md`, run before each release.

## 10. Repository layout

```
feh-rs/
├── Cargo.toml
├── README.md
├── LICENSE-MIT
├── LICENSE-APACHE
├── docs/
│   ├── MVP.md         # this file
│   ├── DESIGN.md      # from-scratch rationale
│   ├── SETUP.md       # bootstrap + open decisions
│   └── SMOKE.md       # manual test checklist
├── src/               # as per §7
└── tests/
    ├── fixtures/      # tiny images (<4 KB each)
    └── viewport.rs
```

## 11. Open questions

1. Arrow keys: navigate or pan by default? *(Proposed: navigate; Ctrl+pan.)*
2. Nearest-neighbour vs. bilinear at fit — feh uses NN; match it?
3. Prefetch depth: prev+next only, or a sliding window of ±2?
4. Cache budget: fixed bytes (256 MB) or fraction of RAM?
5. License: MIT OR Apache-2.0 dual (recommended) — confirm before M1.
6. Working title: keep `feh-rs` or rename? *(Affects crate name + repo URL.)*
MDEOF

# ------------------------------------------------------------- docs/DESIGN.md
cat > docs/DESIGN.md <<'MDEOF'
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
MDEOF

# -------------------------------------------------------------- docs/SETUP.md
cat > docs/SETUP.md <<'MDEOF'
# Setup & Open Decisions

## Kickstarting the repo

```bash
./bootstrap-feh-rs.sh feh-rs
cd feh-rs
cargo run -- --version
git add . && git commit -m "docs: add MVP spec and design rationale"
```

## Decisions to lock before M1

- **Working title** — `feh-rs` is clear but ties you to feh's name. If you
  want an original name later, now is the cheapest time to decide (crate
  name, repo URL, binary name).
- **Arrow-key semantics** (nav vs. pan) — the one UX decision users will
  argue about. Flagged as Open Question #1 in `MVP.md`.
- **License** — scaffold assumes MIT OR Apache-2.0 dual; confirm before M1
  since it affects contribution terms.

## Suggested first code

`viewport_rect` in `src/view.rs`, with its unit tests. Everything renders
through it, and it needs no windowing dependency, so it can be built and
tested headless in CI before any GUI code exists.

## Still to be drafted

- `cli.rs` — clap definitions matching `MVP.md` §3.
- `filelist.rs` — expansion, recursion, `-S`, `-z`.
- `tests/viewport.rs` — the viewport math test suite.
MDEOF

# -------------------------------------------------------------- docs/SMOKE.md
cat > docs/SMOKE.md <<'MDEOF'
# Manual Smoke Checklist

Run before every release. Tick each row; note the build/commit in the header.

- **Version / commit:**
- **Tester / date:**
- **Platform / DPI:**

## Startup & CLI

| # | Check | Pass |
|---|-------|------|
| 1 | `--help` prints full usage, exits 0 | |
| 2 | `--version` prints version, exits 0, no window | |
| 3 | No args → clear error, exit 1 | |
| 4 | Missing file → clear error, exit 1 | |
| 5 | Unimplemented flag (`-x`) → clear error, exit 1 | |
| 6 | Directory with mixed file types → images load, junk skipped with warning | |

## Viewing

| # | Check | Pass |
|---|-------|------|
| 7 | Landscape, portrait, 16×16, 8000×6000 all open correctly | |
| 8 | Fit-to-window shows the whole image | |
| 9 | `1` gives exact 1:1 (count pixels if unsure) | |
| 10 | `+`/`-` zoom smoothly; clamps at limits | |
| 11 | Ctrl+arrows and mouse drag pan; can't lose the image off-screen | |
| 12 | Window resize re-fits when zoom == Fit | |
| 13 | Huge image is responsive (prefetch/cache working) | |

## Navigation

| # | Check | Pass |
|---|-------|------|
| 14 | `n`/`p` page through a directory, wrap at both ends | |
| 15 | `Home`/`End` jump correctly | |
| 16 | Next/prev feels instant on a large folder | |
| 17 | `-r`, `-S name\|mtime\|size`, `-z` produce expected order | |
| 18 | `-f -` reads paths from stdin | |

## Fullscreen, transforms, slideshow

| # | Check | Pass |
|---|-------|------|
| 19 | `-F` and `f` toggle borderless fullscreen on current monitor | |
| 20 | `<`/`>`/`h`/`v`/`r` behave and compose correctly | |
| 21 | `-D 2` advances every 2s; nav keys reset the timer | |

## Polish

| # | Check | Pass |
|---|-------|------|
| 22 | DPI-correct at 100/125/150/200% | |
| 23 | `-g WxH+X+Y` honoured | |
| 24 | Release binary has no console window, but CLI errors still print | |
| 25 | Memory stays bounded paging through a 1000-image folder | |
MDEOF

# ----------------------------------------------------------------- README.md
cat > README.md <<'MDEOF'
# feh-rs

A fast, light image viewer for Windows, inspired by [feh](https://feh.finalrewind.org/).

> **Status:** pre-alpha. The spec is written; no viewer yet.

## Why

feh is excellent, but it is built around X11 and Unix conventions, so a
Windows port would be a rewrite anyway. feh-rs is a clean-room Rust clone
that keeps feh's keyboard-driven, zero-chrome feel and reinterprets its
Unix-isms idiomatically on Windows (wallpaper via `SystemParametersInfo`,
actions via `.ps1`/`.exe`, and so on).

## Docs

- [`docs/MVP.md`](docs/MVP.md) — MVP spec: scope, CLI, keybindings, milestones
- [`docs/DESIGN.md`](docs/DESIGN.md) — why from-scratch, stack choice, gotchas
- [`docs/SETUP.md`](docs/SETUP.md) — bootstrap, open decisions, next steps
- [`docs/SMOKE.md`](docs/SMOKE.md) — manual test checklist

## Build

```bash
cargo run -- --help
```

## License

MIT OR Apache-2.0, at your option.
MDEOF

# ---------------------------------------------------------------- Cargo.toml
cat > Cargo.toml <<'TOMLEOF'
[package]
name = "feh-rs"
version = "0.1.0"
edition = "2021"
description = "A fast, light image viewer for Windows, inspired by feh"
license = "MIT OR Apache-2.0"
repository = "https://github.com/OWNER/feh-rs"
readme = "README.md"

[dependencies]
clap = { version = "4", features = ["derive"] }
anyhow = "1"
log = "0.4"
env_logger = "0.11"

# Uncomment as you reach each milestone (see docs/MVP.md §7).
# winit             = "0.30"   # M1: window + event loop
# softbuffer        = "0.4"    # M1: CPU blit
# image             = { version = "0.25", default-features = false, features = ["jpeg", "png", "bmp", "gif", "webp", "tiff"] }
# crossbeam-channel = "0.5"    # M2: decode worker pool
# lru               = "0.12"   # M2: image cache
# glob              = "0.3"    # M2: Windows-side glob expansion
# walkdir           = "2"      # M2: -r recursion
# rand              = "0.8"    # M2: -z shuffle
# thiserror         = "1"      # as needed, for library-style errors

[profile.release]
lto = true
codegen-units = 1
TOMLEOF

# ---------------------------------------------------------------- src/main.rs
cat > src/main.rs <<'RSEOF'
//! feh-rs — a fast, light image viewer for Windows, inspired by feh.
//!
//! Scaffold only. See `docs/MVP.md` for the target scope and milestones.

use anyhow::Result;

fn main() -> Result<()> {
    env_logger::init();

    // M0: replace with the clap definition from docs/MVP.md §3.
    println!("feh-rs {} — not yet implemented", env!("CARGO_PKG_VERSION"));
    log::debug!("scaffold running; next milestone is M1 (single image view)");

    Ok(())
}
RSEOF

# ----------------------------------------------------------------- .gitignore
cat > .gitignore <<'TXTEOF'
# Rust build output
/target

# Editor / OS noise
.vscode/
.idea/
*.swp
.DS_Store
Thumbs.db
TXTEOF

# -------------------------------------------------------------------- licenses
if command -v curl >/dev/null 2>&1; then
  curl -fsSL https://www.apache.org/licenses/LICENSE-2.0.txt -o LICENSE-APACHE \
    || echo "warning: could not fetch LICENSE-APACHE — add it manually" >&2
else
  echo "warning: curl not found — add LICENSE-APACHE manually" >&2
fi

cat > LICENSE-MIT <<'TXTEOF'
MIT License

Copyright (c) 2026 feh-rs contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
TXTEOF

# --------------------------------------------------------------------- git init
if [ ! -d .git ]; then
  git init -q
  echo "initialised git repository"
fi

# ---------------------------------------------------------------------- summary
echo
echo "Scaffold written to: $(pwd)"
echo
find . -path ./.git -prune -o -type f -print | sed 's|^\./||' | sort
echo
echo "Next steps:"
echo "  cargo fmt"
echo "  cargo run -- --version"
echo "  git add . && git commit -m 'docs: add MVP spec, design rationale, scaffold'"


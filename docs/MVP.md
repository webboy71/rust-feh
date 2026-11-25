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

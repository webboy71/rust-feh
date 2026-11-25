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

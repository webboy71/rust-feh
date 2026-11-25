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

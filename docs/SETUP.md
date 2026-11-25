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

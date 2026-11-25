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

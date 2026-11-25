//! feh-rs — a fast, light image viewer for Windows, inspired by feh.
//!
//! See `docs/MVP.md` for the target scope and milestones.

mod cli;

use anyhow::{bail, Result};
use clap::Parser;

use crate::cli::Cli;

fn main() -> Result<()> {
    let cli = Cli::parse();

    if !cli.quiet {
        env_logger::init();
    }

    if let Err(msg) = cli.check_unimplemented() {
        bail!("{msg}");
    }

    // M1+: build image list and launch window event loop.
    log::debug!("parsed CLI: {cli:?}");
    println!(
        "feh-rs {} — viewer not yet implemented",
        env!("CARGO_PKG_VERSION")
    );

    Ok(())
}

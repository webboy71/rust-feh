//! Command-line interface definition matching `docs/MVP.md` §3.

use std::path::PathBuf;

use clap::{Parser, ValueEnum};

/// Sort key for the image file list (`-S` / `--sort`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum SortKey {
    /// Sort lexicographically by file name.
    Name,
    /// Sort by last-modified timestamp.
    Mtime,
    /// Sort by file size in bytes.
    Size,
}

/// A fast, light image viewer for Windows, inspired by feh.
#[derive(Debug, Parser)]
#[command(
    name = "feh-rs",
    version,
    about = "A fast, light image viewer for Windows, inspired by feh",
    after_help = "Navigation: arrows/Space/n/p move between images; Ctrl+arrows or mouse drag pan."
)]
pub struct Cli {
    /// Files, directories, or glob patterns to view.
    #[arg(value_name = "PATH")]
    pub paths: Vec<PathBuf>,

    /// Recurse into directories.
    #[arg(short = 'r', long = "recursive")]
    pub recursive: bool,

    /// Read newline-separated paths from FILE ('-' for stdin).
    #[arg(short = 'f', long = "filelist", value_name = "FILE")]
    pub filelist: Option<PathBuf>,

    /// Sort the image list (default: argument order).
    #[arg(short = 'S', long = "sort", value_enum, value_name = "KEY")]
    pub sort: Option<SortKey>,

    /// Shuffle the file list at startup.
    #[arg(short = 'z', long = "randomize")]
    pub randomize: bool,

    /// Auto-advance slideshow every N seconds.
    #[arg(short = 'D', long = "slideshow-delay", value_name = "SECS")]
    pub slideshow_delay: Option<f64>,

    /// Start in fullscreen mode.
    #[arg(short = 'F', long = "fullscreen")]
    pub fullscreen: bool,

    /// Zoom to fit small images up (default: fit-down only).
    #[arg(short = 'Z', long = "auto-zoom")]
    pub auto_zoom: bool,

    /// Initial window geometry (WxH+X+Y).
    #[arg(short = 'g', long = "geometry", value_name = "WxH+X+Y")]
    pub geometry: Option<String>,

    /// Suppress non-error output.
    #[arg(short = 'q', long = "quiet")]
    pub quiet: bool,

    // --- Recognised-but-unimplemented feh flags (MVP.md §3) ---
    #[arg(short = 'x', long = "action", hide = true, value_name = "CMD")]
    pub unimpl_action: Option<String>,

    #[arg(short = 't', long = "thumbnails", hide = true)]
    pub unimpl_thumbnails: bool,

    #[arg(short = 'm', long = "montage", hide = true)]
    pub unimpl_montage: bool,

    #[arg(short = 'I', long = "info", hide = true, value_name = "CMD")]
    pub unimpl_info: Option<String>,

    #[arg(short = 'c', long = "caption-path", hide = true, value_name = "DIR")]
    pub unimpl_caption_path: Option<String>,

    #[arg(short = 'R', long = "reload", hide = true, value_name = "SECS")]
    pub unimpl_reload: Option<String>,

    #[arg(long = "bg-fill", hide = true)]
    pub unimpl_bg_fill: bool,

    #[arg(long = "bg-scale", hide = true)]
    pub unimpl_bg_scale: bool,

    #[arg(long = "bg-center", hide = true)]
    pub unimpl_bg_center: bool,

    #[arg(long = "bg-tile", hide = true)]
    pub unimpl_bg_tile: bool,

    #[arg(long = "bg-max", hide = true)]
    pub unimpl_bg_max: bool,
}

impl Cli {
    /// Returns an error message if a recognised-but-unimplemented feh flag was passed.
    pub fn check_unimplemented(&self) -> Result<(), String> {
        let checks: [(&str, bool); 11] = [
            ("-x/--action", self.unimpl_action.is_some()),
            ("-t/--thumbnails", self.unimpl_thumbnails),
            ("-m/--montage", self.unimpl_montage),
            ("-I/--info", self.unimpl_info.is_some()),
            ("-c/--caption-path", self.unimpl_caption_path.is_some()),
            ("-R/--reload", self.unimpl_reload.is_some()),
            ("--bg-fill", self.unimpl_bg_fill),
            ("--bg-scale", self.unimpl_bg_scale),
            ("--bg-center", self.unimpl_bg_center),
            ("--bg-tile", self.unimpl_bg_tile),
            ("--bg-max", self.unimpl_bg_max),
        ];

        for (flag, used) in checks {
            if used {
                return Err(format!("{flag} is not yet implemented in feh-rs"));
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_core_flags_and_paths() {
        let cli = Cli::try_parse_from([
            "feh-rs",
            "-r",
            "-z",
            "-F",
            "-Z",
            "-q",
            "-S",
            "mtime",
            "-D",
            "3.5",
            "-g",
            "1280x720+10+20",
            "a.jpg",
            "dir/",
        ])
        .expect("should parse valid flags");

        assert!(cli.recursive);
        assert!(cli.randomize);
        assert!(cli.fullscreen);
        assert!(cli.auto_zoom);
        assert!(cli.quiet);
        assert_eq!(cli.sort, Some(SortKey::Mtime));
        assert_eq!(cli.slideshow_delay, Some(3.5));
        assert_eq!(cli.geometry.as_deref(), Some("1280x720+10+20"));
        assert_eq!(
            cli.paths,
            vec![PathBuf::from("a.jpg"), PathBuf::from("dir/")]
        );
        assert!(cli.check_unimplemented().is_ok());
    }

    #[test]
    fn rejects_unimplemented_feh_flags_clearly() {
        let cli = Cli::try_parse_from(["feh-rs", "-x", "echo %f", "a.jpg"])
            .expect("flag should be recognised");
        let err = cli
            .check_unimplemented()
            .expect_err("should report unimplemented");
        assert_eq!(err, "-x/--action is not yet implemented in feh-rs");
    }
}

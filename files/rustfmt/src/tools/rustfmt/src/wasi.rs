use std::{ffi::OsStr, path::Path};

use anyhow::{bail, Result};

use crate::{cli, load_config, EmitMode, Input, Session, Verbosity};

pub fn format_text(
    source: String,
    dir: &Path,
    args: impl IntoIterator<Item = impl AsRef<OsStr>>,
) -> Result<Option<String>> {
    let matches = cli::make_opts().parse(args)?;
    if !matches.free.is_empty()
        || ["check", "help", "version", "print-config"]
            .iter()
            .any(|arg| matches.opt_present(arg))
        || matches.opt_str("emit").is_some_and(|mode| mode != "stdout")
    {
        bail!("in-process formatting requires stdin and formatted stdout");
    }
    let mut options = cli::GetOptsOptions::from_matches(&matches)?;
    if let Some(path) = options.config_path.as_mut() {
        if path.is_relative() {
            *path = dir.join(&*path);
        }
    }
    let (mut config, _) = load_config(Some(dir), Some(options))?;
    config.set().emit_mode(EmitMode::Stdout);
    config.set().verbose(Verbosity::Quiet);
    let mut output = Vec::new();
    {
        let mut session = Session::new(config, Some(&mut output));
        let result = session.format(Input::Text(source));
        if session.has_parsing_errors() {
            return Ok(None);
        }
        result.map_err(|err| anyhow::anyhow!("{err}"))?;
        if session.has_operational_errors() {
            bail!("rustfmt failed to format the document");
        }
    }
    Ok(Some(String::from_utf8(output)?))
}

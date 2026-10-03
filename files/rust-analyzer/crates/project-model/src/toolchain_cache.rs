use std::{collections::HashMap, path::Path, process::Command, sync::OnceLock};

use cargo_metadata::{Metadata, MetadataCommand};

fn table() -> &'static HashMap<String, String> {
    static TABLE: OnceLock<HashMap<String, String>> = OnceLock::new();
    TABLE.get_or_init(|| {
        std::fs::read_to_string("/toolchain.json")
            .ok()
            .and_then(|json| serde_json::from_str(&json).ok())
            .unwrap_or_default()
    })
}

pub(crate) fn lookup(cmd: &Command) -> Option<String> {
    let program = Path::new(cmd.get_program()).file_name()?.to_string_lossy();
    let key = std::iter::once(program)
        .chain(cmd.get_args().map(|arg| arg.to_string_lossy()))
        .collect::<Vec<_>>()
        .join(" ");
    table().get(&key).cloned()
}

pub(crate) fn metadata(command: &MetadataCommand) -> Result<Metadata, cargo_metadata::Error> {
    match lookup(&command.cargo_command()) {
        Some(json) => MetadataCommand::parse(json),
        None => command.exec(),
    }
}

//! Exercise the maintained parser through the APIs used by age's macros.

use std::{error::Error, fs};

#[test]
fn age_localization_config_and_manifest() -> Result<(), Box<dyn Error>> {
    let directory = tempfile::tempdir()?;
    fs::write(
        directory.path().join("Cargo.toml"),
        concat!(
            "[package]\nname = 'localization-fixture'\nversion = '0.1.0'\n",
            "[package.metadata]\nreleased = 2026-01-01T00:00:00Z\n",
        ),
    )?;
    fs::write(
        directory.path().join("i18n.toml"),
        "fallback_language = 'en-US'\n[fluent]\nassets_dir = 'i18n'\n",
    )?;
    let configuration = i18n_config::Crate::from(directory.path(), None, "i18n.toml")?;
    assert_eq!(configuration.name, "localization-fixture");
    let configuration = configuration.config_or_err()?;
    assert_eq!(configuration.fallback_language.to_string(), "en-US");
    assert!(configuration.subcrates.is_empty());
    assert_eq!(
        configuration
            .fluent
            .as_ref()
            .map(|fluent| fluent.assets_dir.as_path()),
        Some(std::path::Path::new("i18n")),
    );
    Ok(())
}

#[test]
fn malformed_localization_config_fails_with_path() -> Result<(), Box<dyn Error>> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("i18n.toml");
    let nested = format!(
        "fallback_language = 'en-US'\nunknown = {}0{}\n",
        "[".repeat(256),
        "]".repeat(256),
    );
    for malformed in [
        "[fluent]\nassets_dir = 'i18n'",
        "fallback_language = 'en-US'\n[fluent]",
        "fallback_language = 'not_a_language_identifier'",
        "fallback_language = 42",
        "fallback_language = 'en-US'\nfallback_language = 'fr'",
        "fallback_language = 'unterminated",
        nested.as_str(),
    ] {
        fs::write(&path, malformed)?;
        let result = i18n_config::I18nConfig::from_file(&path);
        assert!(
            matches!(result, Err(i18n_config::I18nConfigError::CannotDeserializeToml(ref source, _)) if source == &path),
            "malformed input must fail with its source path: {result:?}",
        );
    }
    Ok(())
}

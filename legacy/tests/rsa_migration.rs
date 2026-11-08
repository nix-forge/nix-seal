//! Exercise the separately resolved executable with disposable generated keys.

use secrecy::ExposeSecret;
use std::{
    error::Error,
    fs,
    io::Write,
    os::unix::fs::PermissionsExt,
    path::Path,
    process::{Command, Stdio},
};

fn migrate(
    binary: &Path,
    root: &Path,
    recipient: &str,
    destination: &str,
) -> std::io::Result<std::process::Output> {
    Command::new(binary)
        .args(["migrate", "ciphertext", "--repository-root"])
        .arg(root)
        .args([
            "--source",
            "old.age",
            "--destination",
            destination,
            "--identity",
        ])
        .arg(root.join("rsa"))
        .arg("--verification-identity")
        .arg(root.join("verify"))
        .args(["--recipient", recipient, "--execute"])
        .stdin(Stdio::null())
        .output()
}

fn normal_operations_reject_rsa(
    root: &Path,
    public: &str,
    ciphertext: &[u8],
    replacement: &str,
) -> Result<(), Box<dyn Error>> {
    let identity = secrecy::SecretString::from(fs::read_to_string(root.join("rsa"))?);
    assert!(nix_seal_crypto::normalize_recipient(public.trim()).is_err());
    let mut output = Vec::new();
    assert!(
        nix_seal_crypto::encrypt(
            b"rsa-rejection-canary".as_slice(),
            &mut output,
            &[public.trim().to_owned()]
        )
        .is_err()
    );
    assert!(output.is_empty());
    assert!(nix_seal_crypto::decrypt(ciphertext, &mut output, &identity).is_err());
    assert!(output.is_empty());
    assert!(
        nix_seal_crypto::rekey(
            ciphertext,
            &mut output,
            &identity,
            &[replacement.to_owned()]
        )
        .is_err()
    );
    assert!(output.is_empty());
    assert!(
        nix_seal_crypto::rekey_migration(
            ciphertext,
            &mut output,
            &identity,
            &[public.trim().to_owned()]
        )
        .is_err()
    );
    assert!(output.is_empty());
    Ok(())
}

#[test]
fn rsa_is_opt_in_and_migrates_both_private_key_formats() -> Result<(), Box<dyn Error>> {
    let normal = std::env::var_os("NIX_SEAL_NORMAL_TEST_BINARY").ok_or(
        "build the normal package and set NIX_SEAL_NORMAL_TEST_BINARY before legacy tests",
    )?;
    let legacy = Path::new(env!("CARGO_BIN_EXE_nix-seal-legacy"));
    for format in ["OpenSSH", "PEM"] {
        let directory = tempfile::tempdir()?;
        let root = directory.path();
        let mut generator = Command::new("ssh-keygen");
        generator.args(["-q", "-t", "rsa", "-b", "2048", "-N", ""]);
        if format == "PEM" {
            generator.args(["-m", "PEM"]);
        }
        let generated = generator
            .arg("-f")
            .arg(root.join("rsa"))
            .stdin(Stdio::null())
            .output()?;
        assert!(
            generated.status.success(),
            "could not generate disposable RSA key"
        );
        let public = fs::read_to_string(root.join("rsa.pub"))?;
        let (identity, recipient) = nix_seal_crypto::generate_x25519();
        fs::write(root.join("verify"), identity.expose_secret())?;
        fs::set_permissions(root.join("verify"), fs::Permissions::from_mode(0o600))?;
        let mut encryptor = Command::new("age")
            .args(["-r", public.trim()])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()?;
        encryptor
            .stdin
            .take()
            .ok_or("no age input")?
            .write_all(b"rsa-migration-canary")?;
        let encrypted = encryptor.wait_with_output()?;
        assert!(encrypted.status.success());
        fs::write(root.join("old.age"), &encrypted.stdout)?;
        normal_operations_reject_rsa(root, &public, &encrypted.stdout, &recipient)?;

        let rejected = migrate(Path::new(&normal), root, &recipient, "normal.age")?;
        assert!(!rejected.status.success());
        assert!(String::from_utf8_lossy(&rejected.stderr).contains("nix-seal-legacy"));
        assert!(!root.join("normal.age").exists());

        let migrated = migrate(legacy, root, &recipient, "new.age")?;
        assert!(
            migrated.status.success(),
            "legacy migration failed: {}",
            String::from_utf8_lossy(&migrated.stderr)
        );
        let mut plaintext = Vec::new();
        nix_seal_crypto::decrypt(
            fs::File::open(root.join("new.age"))?,
            &mut plaintext,
            &identity,
        )?;
        assert_eq!(plaintext, b"rsa-migration-canary");
        assert_eq!(fs::read(root.join("old.age"))?, encrypted.stdout);

        let encrypted_key = Command::new("ssh-keygen")
            .args([
                "-q",
                "-p",
                "-P",
                "",
                "-N",
                "disposable-test-passphrase",
                "-f",
            ])
            .arg(root.join("rsa"))
            .stdin(Stdio::null())
            .output()?;
        assert!(encrypted_key.status.success());
        let rejected = migrate(legacy, root, &recipient, "encrypted.age")?;
        assert!(!rejected.status.success());
        assert!(!root.join("encrypted.age").exists());
    }
    Ok(())
}

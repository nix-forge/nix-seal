{
  lib,
  root,
  legacy ? false,
}:
lib.fileset.toSource {
  inherit root;
  fileset = lib.fileset.unions (
    [
      (root + "/Cargo.toml")
      (root + "/Cargo.lock")
      (root + "/rust-toolchain.toml")
      (root + "/LICENSE-MIT")
      (root + "/LICENSE-APACHE")
      (root + "/crates")
      (root + "/schemas")
      (lib.fileset.maybeMissing (root + "/vendor"))
      (lib.fileset.maybeMissing (root + "/security/age-source.json"))
      (lib.fileset.maybeMissing (root + "/.cargo"))
    ]
    ++ lib.optionals legacy [
      (lib.fileset.maybeMissing (root + "/legacy/Cargo.toml"))
      (lib.fileset.maybeMissing (root + "/legacy/Cargo.lock"))
      (lib.fileset.maybeMissing (root + "/legacy/tests"))
    ]
  );
}

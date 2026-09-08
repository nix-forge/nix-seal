{ lib, root }:
lib.fileset.toSource {
  inherit root;
  fileset = lib.fileset.unions [
    (root + "/Cargo.toml")
    (root + "/Cargo.lock")
    (root + "/rust-toolchain.toml")
    (root + "/LICENSE-MIT")
    (root + "/LICENSE-APACHE")
    (root + "/crates")
    (root + "/schemas")
    (lib.fileset.maybeMissing (root + "/.cargo"))
  ];
}

# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
cp @nix_sealFixture@ nix-seal
cp @sudoFixture@ sudo
chmod +x nix-seal sudo
export FAIL_OWNER=root
if @pkgs_runtimeShell@ @pkgs_writeText_darwin_preactivation_script_integrated@ 2>error; then
  echo "Darwin accepted missing system artifacts" >&2
  exit 1
fi
grep -q 'target-local cache lacks verified artifacts' error
printf 'check:root\ncheck:tester\n' >expected
diff -u expected events
export FAIL_OWNER=tester
: >events
if @pkgs_runtimeShell@ @pkgs_writeText_darwin_preactivation_script_integrated@ 2>error; then
  echo "Darwin accepted missing home artifacts" >&2
  exit 1
fi
diff -u expected events
export FAIL_OWNER=none
: >events
@pkgs_runtimeShell@ @pkgs_writeText_darwin_preactivation_script_integrated@
printf 'runtime\n' >>expected
diff -u expected events
export FAIL_OWNER=tester
for script in @pkgs_writeText_darwin_persistent_preactivation_script_persis@ @pkgs_writeText_darwin_home_only_preactivation_script_homeOnly@; do
  : >events
  if @pkgs_runtimeShell@ "$script" 2>error; then
    echo "Darwin skipped readiness without a system volatile runtime" >&2
    exit 1
  fi
  grep -q 'check:tester' events
  if grep -q runtime events; then exit 1; fi
done
touch "$out"

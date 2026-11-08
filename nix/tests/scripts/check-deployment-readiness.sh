# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
cp @readiness_probeFixture@ readiness-probe
cp @runuser_probeFixture@ runuser-probe
chmod +x readiness-probe runuser-probe
grep -q -- '--default-configuration' @preflightScript@
grep -q -- '--configuration nixosConfigurations.fixture' @preflightScript@
grep -q -- '--configuration homeConfigurations.tester@fixture' @homePreflightScript@
if grep -q -- '--default-configuration' @homePreflightScript@; then
  echo "Standalone Home Manager incorrectly claimed the flake default" >&2
  exit 1
fi
printf 'root\ntester\n' >expected
for owner in root tester; do
  export FAIL_OWNER="$owner"
  : >events
  if @pkgs_runtimeShell@ @preflightScript@ 2>error; then
    echo "Readiness preflight accepted missing $owner artifacts" >&2
    exit 1
  fi
  diff -u expected events
done
export FAIL_OWNER=none
: >events
@pkgs_runtimeShell@ @preflightScript@
diff -u expected events

: >events
@pkgs_runtimeShell@ @homePreflightScript@
printf 'root\n' >expected-home
diff -u expected-home events

jq -e '.schema == "nix-seal.deployment.v1" and (.targets | length) == 2' @integrated_config_nixSeal_deploymentFile@
home_plan=$(jq -r '.targets[] | select(.target == "home/tester/fixture") | .plan' @integrated_config_nixSeal_deploymentFile@)
jq --arg executable @lib_escapeShellArg_expectedServiceExecutable@ -e \
  '.targets["home/tester/fixture"].serviceActions.executable == $executable' "$home_plan"
# The host may already have a private cache. Test an absent cache inside
# the sandbox so readiness diagnoses missing artifacts, not permissions.
jq --arg cache "$TMPDIR/empty-cache" '.artifactCacheRoot = $cache' \
  @configuration_config_nixSeal_activationSpecs_activation@ >activation.json
if nix-seal readiness --spec "$PWD/activation.json" \
  --deployment @configuration_config_nixSeal_deploymentFile@ \
  --default-configuration --json >report.json; then
  echo "readiness accepted an unprepared system" >&2
  exit 1
fi
if ! jq -e '.ready == false and (.errors | length) == 0 and (.artifacts[0].missing | length) > 0 and (.preparationCommand | contains("prepare --identity")) and (.preparationCommand | contains("--deployment") | not)' report.json; then
  jq . report.json >&2
  exit 1
fi
touch "$out"

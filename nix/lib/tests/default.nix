{ lib }:
let
  seal = import ../. { inherit lib; };
  templates = import ../templates.nix { inherit lib; };
  render = import ../render-text.nix;
  emptyPlan = {
    schema = "nix-seal.plan.v2";
    identities = { };
    groups = { };
    targets = { };
    secrets = { };
    generators = { };
    templates = { };
    approvalPolicies = { };
    backends = { };
  };
  raw = "{{nix-seal:token}} {{public:key}} {{public:key}}\n";
in
{
  plans = {
    testValidIds = {
      expr = map seal.validId [
        "service/token"
        "a-1_b.c"
        "../token"
        "a/./b"
        "Upper"
        ""
        42
      ];
      expected = [
        true
        true
        false
        false
        false
        false
        false
      ];
    };
    testEmptyPlan = {
      expr = builtins.fromJSON (seal.mkPlan { repositoryRoot = ./.; });
      expected = emptyPlan;
    };
    testCiphertextHash = {
      expr =
        (builtins.fromJSON (
          seal.mkPlan {
            repositoryRoot = ./.;
            secrets.token.source = "ciphertext.fixture";
          }
        )).secrets.token;
      expected = {
        source = "ciphertext.fixture";
        sourceCiphertextHash = "1060affdd0e67e786d854a79625092520b8bb51195a4cf5435c5e8da4eadf53c";
      };
    };
    testInvalidCollection = {
      expr = seal.mkPlan {
        repositoryRoot = ./.;
        identities = [ ];
      };
      expectedError.type = "ThrownError";
      expectedError.msg = ".*identities must be an attribute set keyed by IDs.*";
    };
    testInvalidId = {
      expr = seal.mkPlan {
        repositoryRoot = ./.;
        identities."../bad" = { };
      };
      expectedError.type = "ThrownError";
      expectedError.msg = ".*identities contains invalid ID.*";
    };
    testAuthorizationCollision = {
      expr = seal.mkPlan {
        repositoryRoot = ./.;
        identities.service = { };
        targets.service = { };
      };
      expectedError.type = "ThrownError";
      expectedError.msg = ".*authorization ID service is reused.*";
    };
    testUnsafeSource = {
      expr = seal.mkPlan {
        repositoryRoot = ./.;
        secrets.token.source = "../outside.age";
      };
      expectedError.type = "ThrownError";
      expectedError.msg = ".*unsafe canonical source.*";
    };
    testMissingSource = {
      expr = seal.mkPlan {
        repositoryRoot = ./.;
        secrets.token = { };
      };
      expectedError.type = "ThrownError";
      expectedError.msg = ".*repository-relative source string.*";
    };
    testBootstrapPlan = {
      expr = builtins.fromJSON (seal.mkBootstrapCreatePlan { secrets.token.source = "new.age"; });
      expected = emptyPlan // {
        schema = "nix-seal.bootstrap-create-plan.v1";
        secrets.token = {
          source = "new.age";
          sourceCiphertextHash = "0000000000000000000000000000000000000000000000000000000000000000";
        };
      };
    };
    testBootstrapUnsafeSource = {
      expr = seal.mkBootstrapCreatePlan { secrets.token.source = "/absolute.age"; };
      expectedError.type = "ThrownError";
      expectedError.msg = ".*unsafe canonical source.*";
    };
    testMigrationExport = {
      expr = builtins.fromJSON (
        seal.agenixRekeyMigrationExport {
          target = "service";
          masterRecipients = [ "recipient" ];
          secrets = {
            token.rekeyFile = "token.age";
          };
        }
      );
      expected = {
        schema = "nix-seal.agenix-rekey-export.v1";
        target = "service";
        masterRecipients = [ "recipient" ];
        secrets = {
          token.rekeyFile = "token.age";
        };
      };
    };
  };
  publicTemplates = {
    testRepeatedPublicValue = {
      expr = templates.renderPublic raw { key = "ssh-ed25519 fixture"; };
      expected = "{{nix-seal:token}} ssh-ed25519 fixture ssh-ed25519 fixture\n";
    };
    testSecretNames = {
      expr = templates.placeholderNames "{{nix-seal:z}} {{nix-seal:a}} {{nix-seal:z}}";
      expected = [
        "a"
        "z"
      ];
    };
    testMissingBinding = {
      expr = templates.renderPublic raw { };
      expectedError.type = "ThrownError";
      expectedError.msg = ".*missing bindings.*key.*";
    };
    testUnusedBinding = {
      expr = templates.renderPublic raw {
        key = "value";
        unused = "value";
      };
      expectedError.type = "ThrownError";
      expectedError.msg = ".*unused bindings.*unused.*";
    };
    testMalformedMarker = {
      expr = templates.renderPublic "{{public:invalid name}}" { };
      expectedError.type = "ThrownError";
      expectedError.msg = ".*malformed.*public:name.*";
    };
    testSecretInjection = {
      expr = templates.renderPublic raw { key = "{{nix-seal:pending}}"; };
      expectedError.type = "ThrownError";
      expectedError.msg = ".*cannot contain public or secret placeholder markers.*";
    };
    testPublicInjection = {
      expr = templates.renderPublic raw { key = "{{public:other}}"; };
      expectedError.type = "ThrownError";
      expectedError.msg = ".*cannot contain public or secret placeholder markers.*";
    };
    testBoundaryInjection = {
      expr = templates.renderPublic "{{public:key}}{nix-seal:pending}}" { key = "{"; };
      expectedError.type = "ThrownError";
      expectedError.msg = ".*cannot create or change placeholder markers.*";
    };
    testExpansionLimit = {
      expr = templates.renderPublic "{{public:key}}{{public:key}}{{public:key}}" {
        key = lib.concatStrings (lib.replicate (1024 * 1024) "x");
      };
      expectedError.type = "ThrownError";
      expectedError.msg = ".*expansion exceeds the 2 MiB limit.*";
    };
    testSecretPreservation = {
      expr = templates.renderPublic "{{nix-seal:token}}" { };
      expected = "{{nix-seal:token}}";
    };
    testEmptyPublicValue = {
      expr = templates.renderPublic "{{public:value}}" { value = ""; };
      expected = "";
    };
  };
  text = {
    testReplacement = {
      expr = render ./template.txt {
        value = "rendered";
        literal = null;
      };
      expected = "rendered @literal@ rendered\n";
    };
    testMissingReplacement = {
      expr = render ./template.txt { value = "rendered"; };
      expectedError.type = "ThrownError";
      expectedError.msg = ".*missing replacements.*literal.*";
    };
    testUnusedReplacement = {
      expr = render ./template.txt {
        value = "rendered";
        literal = null;
        extra = "unused";
      };
      expectedError.type = "ThrownError";
      expectedError.msg = ".*unused replacements.*extra.*";
    };
    testInvalidName = {
      expr = render ./template.txt { "bad-name" = "value"; };
      expectedError.type = "ThrownError";
      expectedError.msg = ".*invalid placeholder name.*";
    };
  };
}

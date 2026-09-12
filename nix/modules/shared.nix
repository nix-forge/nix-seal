{
  self,
  runtimeDirectory,
  runtimeStorage ? "persistent",
  serviceManager,
  serviceExecutable,
  supportsServiceCredentials,
  serviceCredentialConfig,
  homeManagerRuntimeIdentity,
  targetKind,
}:
args@{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf mkOption types;
  cfg = config.nixSeal;
  # Capture the complete module argument set so target metadata is used when
  # a framework supplies it, without making it mandatory for standalone users.
  targetName = args.targetName or null;
  # The host configuration owns the security-status diagnostic for an
  # embedded Home Manager profile. A standalone Home Manager profile has no
  # host layer and therefore remains responsible for showing it.
  warnExternalAudit = targetKind != "homeManager" || (args.osConfig or null) == null;
  defaultRuntimeGroup =
    if homeManagerRuntimeIdentity then
      (if pkgs.stdenv.hostPlatform.isDarwin then "staff" else config.home.username)
    else if pkgs.stdenv.hostPlatform.isDarwin then
      "wheel"
    else
      "root";
  privateModeType = types.strMatching "0[1-7]00";
  idIsValid =
    value:
    builtins.match "[a-z0-9._-]+(/[a-z0-9._-]+)*" value != null
    && !lib.hasInfix ".." value
    && lib.all (segment: segment != ".") (lib.splitString "/" value);
  idType = types.addCheck types.str idIsValid;
  localIdIsValid =
    value:
    idIsValid value
    && (
      cfg.administrator == null
      || (
        !(lib.any (administrator: lib.hasPrefix "${administrator}/" value) (
          builtins.attrNames administratorCatalog
        ))
        && !(lib.hasPrefix "host/" value)
        && !(lib.hasPrefix "home/" value)
        && !(lib.hasPrefix "hosts/" value)
        && !(lib.hasPrefix "users/" value)
      )
    );
  localIdType = types.addCheck types.str localIdIsValid;
  # Normalize each list entry before the ordinary module merge. Named option
  # sets keep priorities and conflicts, including overrides from other modules.
  declarationsType =
    elementType:
    types.coercedTo (types.listOf (types.either localIdType (types.attrsOf types.unspecified))) (
      entries:
      lib.zipAttrsWith (_: lib.mkMerge) (
        map (
          entry:
          if builtins.isString entry then
            if localIdIsValid entry then
              { ${entry} = { }; }
            else
              throw "nixSeal declaration '${entry}' is not a safe local name"
          else
            entry
        ) entries
      )
    ) (types.attrsOf elementType);
  activationPhaseType = types.enum [
    "partitioning"
    "users"
    "activation"
    "services"
  ];
  activationPhases = [
    "partitioning"
    "users"
    "activation"
    "services"
  ];
  privateIdentityPathIsSafe = value: lib.hasPrefix "/" value && !(lib.hasPrefix "/nix/store/" value);
  artifactCacheRootIsSafe =
    value:
    lib.hasPrefix "/" value
    && value != "/"
    && !(lib.hasPrefix "/nix/store/" value)
    && !lib.hasSuffix "/" value
    && !lib.hasInfix "/../" value
    && !lib.hasInfix "/./" value
    && !lib.hasSuffix "/.." value
    && !lib.hasSuffix "/." value
    && !(builtins.any (character: character < " " || character == "\u007f") (
      lib.stringToCharacters value
    ));
  unitType = types.strMatching "[A-Za-z0-9_.@:-]{1,256}";
  serviceUnitType = types.strMatching "[A-Za-z0-9_.@:-]{1,247}\\.service";
  credentialNameType = types.addCheck (types.strMatching "[A-Za-z0-9_.@-]{1,255}") (
    name: name != "." && name != ".."
  );
  compatibilitySymlinkType = types.nullOr (
    types.addCheck types.str (
      path:
      lib.hasPrefix "/" path
      && path != "/"
      && !lib.hasPrefix "/nix/store/" path
      && !lib.hasSuffix "/" path
      && !lib.hasInfix "/../" path
      && !lib.hasInfix "/./" path
      && !lib.hasSuffix "/.." path
      && !lib.hasSuffix "/." path
      && !(builtins.any (character: character < " " || character == "\u007f") (
        lib.stringToCharacters path
      ))
    )
  );
  administratorCatalog = cfg.administrators;
  templateLib = import ../lib/templates.nix { inherit lib; };
  selectedAdministrator =
    if cfg.administrator != null && builtins.hasAttr cfg.administrator administratorCatalog then
      administratorCatalog.${cfg.administrator}
    else
      { };
  targetScopeFromId =
    targetId:
    let
      parts = lib.splitString "/" targetId;
    in
    if lib.hasPrefix "home/" targetId && builtins.length parts >= 2 then
      "users/${builtins.elemAt parts 1}"
    else if lib.hasPrefix "host/" targetId then
      "hosts/${lib.removePrefix "host/" targetId}"
    else
      null;
  derivedTargetName =
    if targetName != null then
      targetName
    else if targetKind == "homeManager" then
      null
    else
      config.networking.hostName;
  derivedTargetId =
    if targetKind == "homeManager" && derivedTargetName == null then
      "home/${config.home.username}"
    else if derivedTargetName == null then
      null
    else if targetKind == "homeManager" then
      "home/${config.home.username}/${derivedTargetName}"
    else
      "host/${if targetKind == "nixOs" then "nixos" else "darwin"}/${derivedTargetName}";
  derivedSecretScope =
    if targetKind == "homeManager" then
      "users/${config.home.username}"
    else if targetName != null then
      "hosts/${if targetKind == "nixOs" then "nixos" else "darwin"}/${targetName}"
    else if cfg.targetId != null then
      targetScopeFromId cfg.targetId
    else
      null;
  canonicalSecretId =
    name: if cfg.administrator == null then name else "${cfg.administrator}/${cfg.secretScope}/${name}";
  canonicalTemplateId =
    name: if cfg.administrator == null then name else "${cfg.administrator}/${cfg.secretScope}/${name}";
  qualifyReference =
    kind: value:
    if cfg.administrator == null then
      value
    else
      let
        first = builtins.head (lib.splitString "/" value);
        selectedPrefix = "${cfg.administrator}/";
      in
      if lib.hasPrefix selectedPrefix value then
        value
      else if builtins.hasAttr first administratorCatalog && first != cfg.administrator then
        throw "nixSeal ${kind} '${value}' references administrator '${first}', but target follows '${cfg.administrator}'"
      else
        "${selectedPrefix}${value}";
  projectAdminGroups =
    if cfg.administrator == null then
      { }
    else
      lib.mapAttrs' (
        name: group:
        lib.nameValuePair "${cfg.administrator}/${name}" (
          group // { members = map (qualifyReference "administrator group member") (group.members or [ ]); }
        )
      ) (selectedAdministrator.groups or { });
  projectAdminApprovalPolicies =
    if cfg.administrator == null then
      { }
    else
      lib.mapAttrs' (
        name: policy:
        lib.nameValuePair "${cfg.administrator}/${name}" (
          policy // { signers = map (qualifyReference "approval signer") (policy.signers or [ ]); }
        )
      ) (selectedAdministrator.approvalPolicies or { });
  projectAdminIdentities =
    if cfg.administrator == null then
      { }
    else
      lib.mapAttrs' (name: identity: lib.nameValuePair "${cfg.administrator}/${name}" identity) (
        selectedAdministrator.identities or { }
      );
  projectLocalGroups =
    if cfg.administrator == null then
      cfg.groups
    else
      lib.mapAttrs' (
        name: group:
        lib.nameValuePair "${cfg.administrator}/${name}" (
          group // { members = map (qualifyReference "group member") (group.members or [ ]); }
        )
      ) cfg.groups;
  projectLocalApprovalPolicies =
    if cfg.administrator == null then
      cfg.approvalPolicies
    else
      lib.mapAttrs' (
        name: policy:
        lib.nameValuePair "${cfg.administrator}/${name}" (
          policy // { signers = map (qualifyReference "approval signer") (policy.signers or [ ]); }
        )
      ) cfg.approvalPolicies;
  defaultApprovalPolicy = selectedAdministrator.defaultApprovalPolicy or null;
  defaultAdministratorReferences =
    if cfg.administrator == null then
      [ ]
    else
      lib.filter (
        name:
        lib.elem
          (
            if builtins.hasAttr name (selectedAdministrator.identities or { }) then
              selectedAdministrator.identities.${name}.kind
            else
              null
          )
          [
            "administrator"
            "recovery"
          ]
      ) (builtins.attrNames (selectedAdministrator.identities or { }));
  sourceIsSafe =
    source:
    builtins.isString source
    && builtins.match "[a-z0-9._/-]+" source != null
    && !lib.hasPrefix "/" source
    && !lib.hasInfix ".." source
    && !lib.hasInfix "/./" source;
  sourceExists =
    secret:
    secret.source != null
    && sourceIsSafe secret.source
    && builtins.pathExists (cfg.repositoryRoot + "/${secret.source}");
  configuredSecrets = lib.filterAttrs (_: sourceExists) cfg.secrets;
  bootstrapSecrets = lib.filterAttrs (
    _: secret: secret.source != null && sourceIsSafe secret.source && !sourceExists secret
  ) cfg.secrets;
  missingSecretSources = lib.filterAttrs (_: secret: secret.source == null) cfg.secrets;
  invalidSecretSources = lib.filterAttrs (
    _: secret: secret.source != null && !sourceIsSafe secret.source
  ) cfg.secrets;
  bootstrapAuthorizers = lib.filterAttrs (_: identity: identity.kind == "authorizer") (
    projectAdminIdentities // cfg.identities
  );
  declaredTemplates = lib.mapAttrs (
    name: template:
    let
      fail = reason: throw "nixSeal template ${name}: ${reason}";
      names = templateLib.placeholderNames (builtins.readFile template.renderedSource);
      bindings = builtins.attrValues template.placeholders;
    in
    if template.source == null then
      fail "set a public source or content"
    else if
      template.content != null
      && toString template.source != toString (builtins.toFile "nix-seal-template" template.content)
    then
      fail "set source or content, not both"
    else if names == [ ] || builtins.length names > 256 then
      fail "use between 1 and 256 placeholders"
    else if builtins.attrNames template.placeholders != lib.sort builtins.lessThan names then
      fail "placeholder overrides must occur in the public text"
    else if !lib.all (placeholderDef: builtins.hasAttr placeholderDef.secret cfg.secrets) bindings then
      fail "every placeholder must reference a declared secret"
    else if
      !lib.all (placeholderDef: cfg.secrets.${placeholderDef.secret}.phase == template.phase) bindings
    then
      fail "every referenced secret must use the template's activation phase"
    else
      template
  ) cfg.templates;
  configuredTemplates = lib.filterAttrs (
    _: template:
    lib.all (placeholderDef: builtins.hasAttr placeholderDef.secret configuredSecrets) (
      builtins.attrValues template.placeholders
    )
  ) declaredTemplates;
  # A systemd credential consumer must restart after a successful generation
  # switch so it receives the new credential mount.  This is part of the
  # canonical target policy as well as the activation document; otherwise the
  # runtime correctly rejects an activation document that asks it to restart a
  # unit the policy did not authorize.
  restartUnitsForSecret =
    secret:
    lib.unique (secret.restartUnits ++ map (credential: credential.unit) secret.serviceCredentials);
  materializeTemplateSource =
    template:
    toString (
      builtins.path {
        path = template.renderedSource;
        name = "nix-seal-template-source";
      }
    );
  compiledPlanObjects = {
    # Delegated authorizers are deliberately absent from the normal plan: they
    # have no role in activation or target-artifact approval, and including
    # one would needlessly invalidate every existing artifact's plan hash.
    identities = lib.filterAttrs (_: identity: identity.kind != "authorizer") (
      projectAdminIdentities // cfg.identities
    );
    groups = projectAdminGroups // projectLocalGroups;
    approvalPolicies = projectAdminApprovalPolicies // projectLocalApprovalPolicies;
    targets = lib.optionalAttrs (cfg.targetId != null) {
      ${cfg.targetId} = cfg.target // {
        serviceActions = {
          executable = serviceExecutable;
          timeoutSeconds = cfg.serviceActionTimeout;
        };
      };
    };
    secrets = lib.mapAttrs' (
      name: secret:
      lib.nameValuePair (canonicalSecretId name) {
        inherit (secret)
          source
          delivery
          phase
          lifecycle
          ;
        administrators = map (qualifyReference "administrator") secret.administrators;
        consumers = lib.optional (cfg.targetId != null) cfg.targetId;
        approvalPolicy =
          if secret.approvalPolicy != null then
            qualifyReference "approval policy" secret.approvalPolicy
          else if defaultApprovalPolicy != null then
            qualifyReference "default approval policy" defaultApprovalPolicy
          else
            null;
        runtime = {
          inherit (secret)
            owner
            group
            mode
            compatibilitySymlink
            reloadUnits
            ;
          restartUnits = restartUnitsForSecret secret;
        };
      }
    ) configuredSecrets;
    templates = lib.mapAttrs' (
      name: template:
      lib.nameValuePair (canonicalTemplateId name) {
        source = materializeTemplateSource template;
        placeholders = lib.mapAttrs (_: placeholderDef: {
          secret = canonicalSecretId placeholderDef.secret;
          inherit (placeholderDef) encoding;
        }) template.placeholders;
        runtime = {
          inherit (template)
            owner
            group
            mode
            restartUnits
            reloadUnits
            ;
        };
      }
    ) configuredTemplates;
  };
  bootstrapPlanObjects = compiledPlanObjects // {
    # The ordinary plan's secrets are intentionally replaced rather than
    # extended: bootstrap plans can authorize creation only for declared
    # ciphertext sources that do not exist yet
    # secrets and can never be mistaken for an activation plan.
    # Bootstrap plans retain authorizers, but normal plans never do.
    identities = projectAdminIdentities // cfg.identities;
    # Templates are runtime outputs, never canonical creation destinations.
    templates = { };
    secrets = lib.mapAttrs' (
      name: secret:
      lib.nameValuePair (canonicalSecretId name) {
        inherit (secret)
          source
          delivery
          phase
          lifecycle
          ;
        administrators = map (qualifyReference "administrator") secret.administrators;
        consumers = lib.optional (cfg.targetId != null) cfg.targetId;
        approvalPolicy =
          if secret.approvalPolicy != null then
            qualifyReference "approval policy" secret.approvalPolicy
          else if defaultApprovalPolicy != null then
            qualifyReference "default approval policy" defaultApprovalPolicy
          else
            null;
        runtime = {
          inherit (secret)
            owner
            group
            mode
            compatibilitySymlink
            reloadUnits
            ;
          restartUnits = restartUnitsForSecret secret;
        };
      }
    ) bootstrapSecrets;
  };
  phaseRuntimeDirectory =
    phase: if phase == "activation" then cfg.runtimeDirectory else "${cfg.runtimeDirectory}/${phase}";
  configuredSecretsForPhase =
    phase: lib.filterAttrs (_: secret: secret.phase == phase) configuredSecrets;
  configuredTemplatesForPhase =
    phase: lib.filterAttrs (_: template: template.phase == phase) configuredTemplates;
  explicitReloadUnitsForPhase =
    phase:
    lib.unique (
      lib.concatMap (item: item.reloadUnits) (
        builtins.attrValues (configuredSecretsForPhase phase)
        ++ builtins.attrValues (configuredTemplatesForPhase phase)
      )
    );
  explicitRestartUnitsForPhase =
    phase:
    lib.unique (
      lib.concatMap (item: item.restartUnits) (
        builtins.attrValues (configuredSecretsForPhase phase)
        ++ builtins.attrValues (configuredTemplatesForPhase phase)
      )
    );
  serviceCredentialBindingsForPhase =
    phase:
    lib.concatMap (
      secretId:
      map (credential: {
        inherit secretId;
        inherit (credential) unit name;
        path = cfg.secrets.${secretId}.path;
      }) cfg.secrets.${secretId}.serviceCredentials
    ) (builtins.attrNames (configuredSecretsForPhase phase));
  serviceCredentialBindings = lib.concatMap serviceCredentialBindingsForPhase activationPhases;
  serviceCredentialKeys = map (binding: "${binding.unit}:${binding.name}") serviceCredentialBindings;
  reloadUnitsForPhase = explicitReloadUnitsForPhase;
  restartUnitsForPhase =
    phase:
    lib.unique (
      explicitRestartUnitsForPhase phase
      ++ map (binding: binding.unit) (serviceCredentialBindingsForPhase phase)
    );
  reloadUnits = lib.concatMap reloadUnitsForPhase activationPhases;
  activationDocumentFor =
    phase:
    let
      secrets = configuredSecretsForPhase phase;
      templates = configuredTemplatesForPhase phase;
      reloadUnits = reloadUnitsForPhase phase;
      restartUnits = restartUnitsForPhase phase;
    in
    {
      schema = "nix-seal.activation.v2";
      runtimeRoot = phaseRuntimeDirectory phase;
      inherit (cfg) runtimeStorage;
      plan = toString cfg.planFile;
      inherit (cfg) artifactCacheRoot;
      inherit (cfg) targetId;
      inherit phase;
      inherit (cfg) allowedClockSkew;
      artifacts = lib.mapAttrsToList (_name: secret: {
        secretId = secret.id;
        inherit (secret) phase;
        inherit (secret) mode;
        inherit (secret) owner;
        inherit (secret) group;
        inherit (secret) compatibilitySymlink;
      }) secrets;
      templates = lib.mapAttrsToList (_: template: {
        source = materializeTemplateSource template;
        templateId = template.id;
        placeholders = lib.mapAttrs (_: placeholderDef: {
          secretId = cfg.secrets.${placeholderDef.secret}.id;
          inherit (placeholderDef) encoding;
        }) template.placeholders;
        inherit (template) phase;
        inherit (template) mode owner group;
      }) templates;
      postSwitch =
        if reloadUnits == [ ] && restartUnits == [ ] then
          null
        else
          {
            executable = serviceExecutable;
            manager = serviceManager;
            inherit reloadUnits restartUnits;
            timeoutSeconds = cfg.serviceActionTimeout;
          };
    };
  activationDocument = activationDocumentFor "activation";
  activationSpecFor =
    phase:
    pkgs.writeText "nix-seal-activation-v2-${phase}.json" (
      builtins.toJSON (activationDocumentFor phase)
    );
  configuredPhases = lib.filter (phase: configuredSecretsForPhase phase != { }) activationPhases;
in
{
  options.nixSeal = {
    enable = lib.mkEnableOption "nix-seal pre-release integration" // {
      default = cfg.secrets != { } || cfg.templates != { };
      defaultText = lib.literalExpression "secrets or templates are declared";
    };
    package = mkOption {
      type = types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.nix-seal;
      defaultText = lib.literalExpression "nix-seal.packages.\${pkgs.stdenv.hostPlatform.system}.nix-seal";
      description = "nix-seal package used by activation tooling.";
    };
    administrator = mkOption {
      type = types.nullOr idType;
      default =
        let
          names = builtins.attrNames administratorCatalog;
        in
        if builtins.length names == 1 then
          builtins.head names
        else if names == [ ] then
          null
        else
          throw "nixSeal.administrator: select one of ${lib.concatStringsSep ", " names}, or set null for explicit identity mode";
      defaultText = "the sole administrator, or null without a catalog";
      description = "Administrator catalog followed by this target. A single entry is selected automatically; multiple entries require a choice. Explicit null retains unscoped identity mode.";
    };
    targetId = mkOption {
      type = types.nullOr idType;
      default = null;
      description = "Stable target ID bound into signed artifacts; derived from framework metadata when available.";
    };
    secretScope = mkOption {
      type = types.nullOr idType;
      default = null;
      description = "Administrator-relative secret namespace; derived from the target when available.";
    };
    administrators = mkOption {
      type = import ./catalog.nix { inherit lib; };
      default =
        (args.nixSealCatalog or (config._module.args.nixSealCatalog or { })).administrators or { };
      description = "Public administrator catalogs. Ordinary Nix modules can define these directly; the optional flake adapter supplies the default.";
    };
    pendingTemplates = mkOption {
      type = types.attrsOf (types.listOf types.str);
      readOnly = true;
      default = lib.mapAttrs (
        _: template:
        lib.unique (
          map (placeholderDef: placeholderDef.secret) (
            lib.filter (placeholderDef: builtins.hasAttr placeholderDef.secret bootstrapSecrets) (
              builtins.attrValues template.placeholders
            )
          )
        )
      ) (lib.filterAttrs (name: _: !(builtins.hasAttr name configuredTemplates)) declaredTemplates);
      description = "Templates waiting for declared ciphertexts, mapped to the missing local secret names. These templates are excluded from activation until every field exists.";
    };
    placeholder = mkOption {
      type = types.attrsOf types.str;
      readOnly = true;
      default = lib.mapAttrs (name: _: "{{nix-seal:${name}}}") (
        lib.filterAttrs (name: _: builtins.match "[a-z0-9][a-z0-9_.-]{0,127}" name != null) cfg.secrets
      );
      description = "Public placeholder strings for declared simple secret names. Interpolate these into a template's Nix content; they contain no secret values. Names containing slashes need an explicit simple placeholder alias instead.";
    };
    secretDirectory = mkOption {
      type = idType;
      default =
        if cfg.administrator != null && cfg.secretScope != null then
          "secrets/${cfg.administrator}/${cfg.secretScope}"
        else
          "secrets";
      defaultText = "secrets/<administrator>/<secretScope>";
      description = ''
        Repository-relative directory for automatically named canonical ciphertexts.
        Changing storage does not change secret IDs, recipients, or runtime paths.
        Each secret's explicit source overrides this directory.
      '';
    };
    templateDirectory = mkOption {
      type = idType;
      default = "templates";
      description = ''
        Repository-relative directory for public templates named <local-name>.template.
        Only declared templates are loaded. An explicit source or inline content
        overrides this default. Public templates can be reused across targets;
        each declaration still controls its own secret bindings and runtime policy.
      '';
    };
    sharedSecretDirectory = mkOption {
      type = idType;
      default =
        if cfg.administrator != null then "secrets/${cfg.administrator}/shared" else "secrets/shared";
      defaultText = "secrets/<administrator>/shared";
      description = ''
        Repository-relative directory used by secrets with shared = true.
        Configure the same directory on participating hosts and homes to reuse
        ciphertext. Each target retains its own policy and signed artifacts.
      '';
    };
    identityFile = mkOption {
      type = types.nullOr types.str;
      default =
        if homeManagerRuntimeIdentity then
          "${config.home.homeDirectory}/.ssh/id_ed25519"
        else
          "/etc/ssh/ssh_host_ed25519_key";
      defaultText = "~/.ssh/id_ed25519 for Home Manager; /etc/ssh/ssh_host_ed25519_key for systems";
      description = "Runtime path to the existing target age or SSH identity. Evaluation never reads or generates this private key; activation requires it to exist and match publicKey. Override this path for a dedicated age identity.";
    };
    publicKey = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Target age recipient or SSH public key. Expands to identities.target with kind = target. The public key must be supplied explicitly; evaluation never derives it from a private key.";
    };
    planFile = mkOption {
      type = types.nullOr types.path;
      default = pkgs.writeText "nix-seal-plan-v2.json" (
        self.lib.mkPlan (compiledPlanObjects // { inherit (cfg) repositoryRoot; })
      );
      description = "Canonical compiled plan.v2 JSON used to derive and verify target policy.";
    };
    bootstrapPlanFile = mkOption {
      type = types.nullOr types.path;
      readOnly = true;
      default =
        if bootstrapSecrets == { } then
          null
        else
          pkgs.writeText "nix-seal-bootstrap-create-plan-v1.json" (
            self.lib.mkBootstrapCreatePlan bootstrapPlanObjects
          );
      description = "Public, create-only plan for declared canonical sources that do not exist yet. It is never used by activation or provisioning.";
    };
    repositoryRoot =
      mkOption {
        type = types.path;
        description = "Repository root used to resolve canonical ciphertext and public template sources. The optional framework adapter supplies the calling flake root; standalone modules set this once.";
      }
      // lib.optionalAttrs (args ? nixSealRepositoryRoot) { default = args.nixSealRepositoryRoot; };
    identities = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = "Public administrator, recovery, signer, and target identity declarations used to compile plan.v2.";
    };
    groups = mkOption {
      type = types.attrs;
      default = { };
      description = "Public plan groups declared by this target or administrator projection.";
    };
    target = mkOption {
      type = types.attrs;
      default = { };
      description = "Public target declaration for this configuration, including its plan identity ID.";
    };
    approvalPolicies = mkOption {
      type = types.attrs;
      default = { };
      description = "Public artifact approval policies used to compile plan.v2.";
    };
    allowedClockSkew = mkOption {
      type = types.ints.between 0 86400;
      default = 300;
      description = "Maximum accepted artifact issue-time lead in seconds, capped at one day.";
    };
    artifactCacheRoot = mkOption {
      type = types.addCheck types.str artifactCacheRootIsSafe;
      default =
        if homeManagerRuntimeIdentity then
          "${config.home.homeDirectory}/${
            if pkgs.stdenv.hostPlatform.isDarwin then "Library/Caches" else ".cache"
          }/nix-seal/v1"
        else
          "/var/lib/nix-seal/cache/v1";
      description = "Absolute target-local ciphertext cache root. Activation discovers only cryptographically verified matching bundles here.";
    };
    serviceActionTimeout = mkOption {
      type = types.ints.between 1 60;
      default = 30;
      description = "Per-unit post-switch service action timeout in seconds.";
    };
    runtimeDirectory = mkOption {
      type = types.str;
      readOnly = true;
      default = runtimeDirectory;
      description = "Platform runtime directory for plaintext generations.";
    };
    runtimeStorage = mkOption {
      type = types.enum [
        "persistent"
        "volatile-tmpfs"
        "volatile-tmpfs-noswap"
      ];
      default = runtimeStorage;
      internal = true;
      description = "Internal activation storage requirement selected by the platform module.";
    };
    secrets = mkOption {
      default = { };
      type = declarationsType (
        types.submodule (
          { name, ... }: {
            options = {
              id = mkOption {
                type = idType;
                readOnly = true;
                default = canonicalSecretId name;
                description = "Canonical plan ID derived from the selected administrator and target scope.";
              };
              path = mkOption {
                type = types.str;
                readOnly = true;
                default = "${phaseRuntimeDirectory config.nixSeal.secrets.${name}.phase}/current/${
                  config.nixSeal.secrets.${name}.id
                }";
                description = "Runtime path of the activated secret.";
              };
              phase = mkOption {
                type = activationPhaseType;
                default = "activation";
                description = "Activation generation that materializes this secret.";
              };
              owner = mkOption {
                type = types.str;
                default = if homeManagerRuntimeIdentity then config.home.username else "root";
                description = "Existing runtime account that owns the activated file.";
              };
              group = mkOption {
                type = types.str;
                default = defaultRuntimeGroup;
                description = "Existing runtime group that owns the activated file.";
              };
              mode = mkOption {
                type = privateModeType;
                default = "0400";
              };
              compatibilitySymlink = mkOption {
                type = compatibilitySymlinkType;
                default = null;
                description = ''
                  Optional absolute compatibility symlink for legacy consumers.
                  Activation binds it to the stable current-generation path and
                  refuses to replace a mismatched existing filesystem entry.
                '';
              };
              shared = mkOption {
                type = types.bool;
                default = false;
                description = "Derive the default source from sharedSecretDirectory instead of secretDirectory. This does not grant other targets access.";
              };
              source = mkOption {
                type = types.nullOr types.str;
                default = "${
                  if cfg.secrets.${name}.shared then cfg.sharedSecretDirectory else cfg.secretDirectory
                }/${name}.age";
                description = "Repository-relative canonical .age ciphertext source; scoped targets derive this from the configured storage directory and local name. Explicit sources override both directories.";
              };
              delivery = mkOption {
                type = types.enum [
                  "rekeyed"
                  "direct"
                ];
                default = "rekeyed";
                description = "Ciphertext delivery model.";
              };
              administrators = mkOption {
                type = types.listOf idType;
                default = defaultAdministratorReferences;
                description = "Administrator or recovery identity IDs; scoped targets qualify local references under the selected administrator.";
              };
              approvalPolicy = mkOption {
                type = types.nullOr idType;
                default = null;
                description = "Approval policy ID required for this secret's artifacts.";
              };
              lifecycle = mkOption {
                type = types.attrs;
                default = { };
                description = "Public lifecycle metadata included in plan.v2.";
              };
              restartUnits = mkOption {
                type = types.listOf unitType;
                default = [ ];
              };
              reloadUnits = mkOption {
                type = types.listOf unitType;
                default = [ ];
              };
              serviceCredentials = mkOption {
                type = types.listOf (
                  types.submodule {
                    options = {
                      unit = mkOption {
                        type = serviceUnitType;
                        description = "Systemd service that receives this secret as a credential.";
                      };
                      name = mkOption {
                        type = credentialNameType;
                        description = "Filename exposed below the service's CREDENTIALS_DIRECTORY.";
                      };
                    };
                  }
                );
                default = [ ];
                description = ''
                  Per-service systemd credential mappings. Each mapping loads the
                  activated runtime file and automatically schedules a service
                  restart when the secret generation changes.
                '';
              };
            };
          }
        )
      );
      description = "Public runtime secret declarations. Accepts an attribute set or a list of names and named option sets. Values never enter Nix evaluation.";
    };
    templates = mkOption {
      default = { };
      type = declarationsType (
        types.coercedTo (types.addCheck types.path builtins.isPath) (source: { inherit source; }) (
          types.coercedTo types.str (content: { inherit content; }) (
            types.submodule (
              { name, ... }: {
                options = {
                  id = mkOption {
                    type = idType;
                    readOnly = true;
                    default = canonicalTemplateId name;
                    description = "Canonical plan ID derived from the selected administrator and target scope.";
                  };
                  path = mkOption {
                    type = types.str;
                    readOnly = true;
                    default = "${phaseRuntimeDirectory config.nixSeal.templates.${name}.phase}/current/templates/${
                      config.nixSeal.templates.${name}.id
                    }";
                    description = "Runtime path of the atomically rendered template.";
                  };
                  phase = mkOption {
                    type = activationPhaseType;
                    default =
                      let
                        phases = lib.unique (
                          map (
                            binding:
                            if builtins.hasAttr binding.secret cfg.secrets then
                              cfg.secrets.${binding.secret}.phase
                            else
                              throw "nixSeal template ${name}: every placeholder must reference a declared secret"
                          ) (builtins.attrValues cfg.templates.${name}.placeholders)
                        );
                      in
                      if phases == [ ] then
                        "activation"
                      else if builtins.length phases == 1 then
                        builtins.head phases
                      else
                        throw "nixSeal template ${name}: referenced secrets must share an activation phase";
                    defaultText = "the activation phase shared by its referenced secrets";
                    description = "Activation generation that renders this template. Defaults to the referenced secrets' common phase; it never moves a secret to another phase.";
                  };
                  source = mkOption {
                    type = types.nullOr types.path;
                    default =
                      if cfg.templates.${name}.content != null then
                        builtins.toFile "nix-seal-template" cfg.templates.${name}.content
                      else if !localIdIsValid name then
                        throw "nixSeal template ${name}: the local name is not a safe template ID"
                      else
                        let
                          source = cfg.repositoryRoot + "/${cfg.templateDirectory}/${name}.template";
                        in
                        if builtins.pathExists source then
                          source
                        else
                          throw "nixSeal template ${name}: create ${cfg.templateDirectory}/${name}.template or set source/content";
                    description = "Public template source, defaulting to <templateDirectory>/<name>.template. This file may enter the Nix store. Set either source or content to override the named file.";
                  };
                  content = mkOption {
                    type = types.nullOr types.lines;
                    default = null;
                    description = "Public template text with {{nix-seal:name}} placeholders. Never put secret values here.";
                  };
                  publicValues = mkOption {
                    type = types.attrsOf types.str;
                    default = { };
                    description = "Public strings substituted for {{public:name}} during Nix evaluation, before secret rendering at activation. These values enter the public Nix store. Missing or unused bindings and nested markers are rejected. Values are literal text, with no automatic escaping.";
                  };
                  renderedSource = mkOption {
                    type = types.nullOr types.path;
                    readOnly = true;
                    default =
                      let
                        template = cfg.templates.${name};
                        original = builtins.readFile template.source;
                        rendered = builtins.addErrorContext "while rendering public values for nixSeal.templates.${name}:" (
                          templateLib.renderPublic original template.publicValues
                        );
                      in
                      if template.source == null then
                        null
                      else if rendered == original then
                        template.source
                      else
                        builtins.toFile "nix-seal-template" rendered;
                    description = "Public template after publicValues substitution; secret markers remain unresolved. The plan and runtime use this generated source.";
                  };
                  placeholders = mkOption {
                    default = { };
                    type = types.attrsOf (
                      types.coercedTo localIdType (secret: { inherit secret; }) (
                        types.submodule {
                          options = {
                            secret = mkOption {
                              type = localIdType;
                              description = "Local ID of the secret inserted at this placeholder.";
                            };
                            encoding = mkOption {
                              type = types.enum [
                                "utf8"
                                "base64"
                                "hex"
                              ];
                              default = "utf8";
                              description = "Explicit transformation applied while streaming the secret.";
                            };
                          };
                        }
                      )
                    );
                    description = "Placeholder overrides. Names in the public text default to same-named declared secrets. Use a secret name string or an attribute set with secret and encoding.";
                  };
                  owner = mkOption {
                    type = types.str;
                    default = if homeManagerRuntimeIdentity then config.home.username else "root";
                    description = "Existing runtime account that owns the rendered file.";
                  };
                  group = mkOption {
                    type = types.str;
                    default = defaultRuntimeGroup;
                    description = "Existing runtime group that owns the rendered file.";
                  };
                  mode = mkOption {
                    type = privateModeType;
                    default = "0400";
                  };
                  restartUnits = mkOption {
                    type = types.listOf unitType;
                    default = [ ];
                  };
                  reloadUnits = mkOption {
                    type = types.listOf unitType;
                    default = [ ];
                  };
                };
                config.placeholders = lib.mkIf (cfg.templates.${name}.source != null) (
                  lib.genAttrs (templateLib.placeholderNames (builtins.readFile cfg.templates.${name}.renderedSource))
                    (placeholderDef: {
                      secret = lib.mkDefault placeholderDef;
                    })
                );
              }
            )
          )
        )
      );
      description = "Runtime-rendered template outputs. Accepts an attribute set or a list of names and named option sets. Each output accepts public text, a public file, or full options.";
    };
    deploymentTargets = mkOption {
      type = types.listOf types.attrs;
      internal = true;
      default = [ ];
      description = "Targets included in configuration-wide artifact preparation.";
    };
    deploymentFile = mkOption {
      type = types.path;
      readOnly = true;
      default = pkgs.writeText "nix-seal-deployment.json" (
        builtins.toJSON {
          schema = "nix-seal.deployment.v1";
          targets = cfg.deploymentTargets;
        }
      );
      description = "Public preparation description for the system and its embedded Home Manager targets. Bare nix-seal prepare uses the flake's saved default; private key paths are supplied only to that command.";
    };
    activationSpec = mkOption {
      type = types.path;
      readOnly = true;
      default = pkgs.writeText "nix-seal-activation-v2.json" (builtins.toJSON activationDocument);
      description = "Strict public activation document consumed by the Rust runtime.";
    };
    activationSpecs = mkOption {
      type = types.attrsOf types.path;
      readOnly = true;
      default = lib.genAttrs configuredPhases activationSpecFor;
      description = "Strict phase-isolated activation documents consumed by the Rust runtime.";
    };
  };

  config = mkIf cfg.enable (
    lib.mkMerge [
      {
        nixSeal.deploymentTargets = lib.mkBefore [
          {
            target = cfg.targetId;
            plan = toString cfg.planFile;
            cacheRoot = cfg.artifactCacheRoot;
            user = if homeManagerRuntimeIdentity then config.home.username else null;
            specs = map toString (builtins.attrValues cfg.activationSpecs);
          }
        ];
        nixSeal.identities = lib.mkIf (cfg.publicKey != null) {
          target = {
            kind = "target";
            public = cfg.publicKey;
          };
        };
        nixSeal.target = lib.mkDefault (
          {
            kind = targetKind;
            system = pkgs.stdenv.hostPlatform.system;
            identity = "target";
          }
          // lib.optionalAttrs (targetName != null) { configuration = targetName; }
          // lib.optionalAttrs (targetKind == "homeManager") { username = config.home.username; }
        );
        nixSeal.targetId = lib.mkDefault derivedTargetId;
        nixSeal.secretScope = lib.mkDefault derivedSecretScope;
        assertions = [
          {
            assertion = cfg.targetId != null && idIsValid cfg.targetId;
            message = "nixSeal.targetId must be a lowercase stable ID or be derivable from framework metadata";
          }
          {
            assertion = cfg.target != { } && cfg.target ? identity;
            message = "nixSeal.target must declare a target identity";
          }
          {
            assertion = lib.all localIdIsValid (
              builtins.attrNames cfg.secrets ++ builtins.attrNames cfg.templates
            );
            message = "nixSeal scoped secret and template names must be local lowercase stable IDs";
          }
          {
            assertion = cfg.administrator == null || builtins.hasAttr cfg.administrator administratorCatalog;
            message = "nixSeal.administrator must reference an administrator in the flake nixSeal catalog";
          }
          {
            assertion = cfg.administrator == null || cfg.secretScope != null;
            message = "nixSeal.secretScope must be derivable or explicitly set when nixSeal.administrator is selected";
          }
          {
            assertion = cfg.identityFile != null;
            message = "nixSeal.identityFile must name an out-of-store target identity when nix-seal is enabled";
          }
          {
            assertion = cfg.identityFile == null || privateIdentityPathIsSafe cfg.identityFile;
            message = "nixSeal.identityFile must be an absolute path outside /nix/store";
          }
          {
            assertion = cfg.planFile != null;
            message = "nixSeal.planFile must provide canonical compiled plan.v2 JSON";
          }
          {
            assertion = configuredSecrets != { } || bootstrapSecrets != { };
            message = "nixSeal requires at least one declared canonical source";
          }
          {
            assertion = missingSecretSources == { };
            message =
              let
                secret = builtins.head (builtins.attrNames missingSecretSources);
              in
              "nixSeal secret ${secret} is missing its canonical repository source";
          }
          {
            assertion = invalidSecretSources == { };
            message =
              let
                secret = builtins.head (builtins.attrNames invalidSecretSources);
              in
              "nixSeal secret ${secret} has an unsafe canonical repository source path";
          }
          {
            assertion = bootstrapSecrets == { } || bootstrapAuthorizers != { };
            message = "creating a missing nixSeal canonical ciphertext requires an authorizer identity";
          }
          {
            assertion =
              lib.intersectLists (builtins.attrNames configuredSecrets) (
                map (name: "templates/${name}") (builtins.attrNames configuredTemplates)
              ) == [ ];
            message = "a nixSeal template output cannot collide with a secret runtime path";
          }
          {
            assertion =
              serviceManager != "launchd-system" && serviceManager != "launchd-user" || reloadUnits == [ ];
            message = "nixSeal reloadUnits are unsupported by launchd; use restartUnits";
          }
          {
            assertion = lib.all (
              phase: lib.intersectLists (reloadUnitsForPhase phase) (restartUnitsForPhase phase) == [ ]
            ) configuredPhases;
            message = "a nixSeal unit cannot appear in both reloadUnits and restartUnits";
          }
          {
            assertion = supportsServiceCredentials || serviceCredentialBindings == [ ];
            message = "nixSeal serviceCredentials require a systemd platform";
          }
          {
            assertion =
              builtins.length serviceCredentialKeys == builtins.length (lib.unique serviceCredentialKeys);
            message = "a systemd service credential name may be mapped by only one nixSeal secret";
          }
        ];
        warnings =
          lib.optional warnExternalAudit "nix-seal is pre-1.0 and has not passed its required external security audit"
          ++ lib.mapAttrsToList (
            name: missing:
            "nixSeal template ${name} is pending creation of: ${lib.concatStringsSep ", " missing}"
          ) cfg.pendingTemplates;
      }
      (serviceCredentialConfig serviceCredentialBindings)
    ]
  );
}

{ lib }:
let
  limit = 2 * 1024 * 1024;
  # Inspect public text only. The Rust renderer remains the final grammar and
  # authorization check; inferred bindings never declare or authorize a secret.
  occurrences =
    namespace: content:
    let
      parts = lib.tail (lib.splitString "{{" content);
      names = lib.concatMap (
        part:
        if lib.hasPrefix namespace part then
          let
            matched = builtins.match "${namespace}:([a-z0-9][a-z0-9_.-]{0,127})}}(.*)" part;
          in
          if matched == null then
            throw "nixSeal template contains a malformed {{${namespace}:name}} placeholder"
          else
            [ (builtins.head matched) ]
        else
          [ ]
      ) parts;
    in
    if builtins.stringLength content > limit then
      throw "nixSeal public template exceeds the 2 MiB limit"
    else
      names;
  unique = names: builtins.attrNames (lib.genAttrs names (_: null));
in
{
  placeholderNames = content: unique (occurrences "nix-seal" content);
  renderPublic =
    content: values:
    let
      publicNames = occurrences "public" content;
      names = unique publicNames;
      missing = lib.filter (name: !(builtins.hasAttr name values)) names;
      unused = lib.filter (name: !(builtins.elem name names)) (builtins.attrNames values);
      marker = name: "{{public:${name}}}";
      # Calculate expansion before allocating the rendered text.
      renderedSize =
        builtins.stringLength content
        + lib.foldl' (
          size: name: size + builtins.stringLength values.${name} - builtins.stringLength (marker name)
        ) 0 publicNames;
      rendered = builtins.replaceStrings (map marker names) (map (name: values.${name}) names) content;
    in
    if names != builtins.attrNames values then
      throw "nixSeal template publicValues: missing bindings [${lib.concatStringsSep ", " missing}]; unused bindings [${lib.concatStringsSep ", " unused}]"
    else if builtins.length names > 256 then
      throw "nixSeal template exceeds 256 public placeholders"
    else if renderedSize > limit then
      throw "nixSeal public template expansion exceeds the 2 MiB limit"
    else if
      lib.any (value: lib.hasInfix "{{public" value || lib.hasInfix "{{nix-seal" value) (
        builtins.attrValues values
      )
    then
      throw "nixSeal publicValues cannot contain public or secret placeholder markers"
    else if
      occurrences "public" rendered != [ ]
      || occurrences "nix-seal" rendered != occurrences "nix-seal" content
    then
      throw "nixSeal publicValues cannot create or change placeholder markers"
    else
      rendered;
}

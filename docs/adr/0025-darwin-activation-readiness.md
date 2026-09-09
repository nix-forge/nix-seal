# Darwin activation readiness

Status: accepted

Darwin activation could prepare its volatile runtime and enter system activation
before discovering that signed artifacts belonged to a previous plan. Deployment
preparation already supports Darwin, but the module did not schedule readiness.

Run the existing public readiness command in `preActivation`, ordered before
nix-seal runtime preparation. Check every deployment target, including embedded
Home Manager targets when system nix-seal is disabled. System caches are checked
as root and home caches through the platform sudo executable as their owner.
Collect failures across targets, then exit explicitly before ordinary activation
phases. Include the configuration's package executable and deployment description
in the recovery command so an older installed CLI does not block recovery.

The check uses existing artifact verification without decrypting, importing, or
creating artifacts. It does not change cache trust, signing policy, or activation's
own verification. It remains enabled with persistent runtime storage. Existing
home accounts are required to inspect their private caches; first installations
must establish those accounts before preparing and activating their secrets.

Darwin lacks the NixOS pre-switch hook. This check runs inside activation and
cannot roll back a profile update already performed by the caller. Other modules
can also contribute early activation snippets. The ordering guarantee is relative
to nix-seal's runtime preparation and the ordinary nix-darwin activation phases.

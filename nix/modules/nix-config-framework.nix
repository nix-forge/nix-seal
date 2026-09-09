{ config, self, ... }: {
  nixConfigFramework.extraSpecialArgs = {
    nixSealCatalog = config.flake.nixSeal;
    nixSealRepositoryRoot = self.outPath;
  };
}

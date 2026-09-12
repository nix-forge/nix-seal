{ config, self, ... }: {
  nixConfigFramework.extraSpecialArgs = {
    nixSealCatalog = config.flake.nixSeal;
    nixSealDefaultConfiguration = config.flake.nixSeal.defaultConfiguration;
    nixSealRepositoryRoot = self.outPath;
  };
}

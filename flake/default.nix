{ config, inputs, self, ... }:
{
  flake = {
    nixvimModules.default = {
      imports = [
        ../modules/nixvim
      ];
      extraSpecialArgs = {
        mypkgs = self.packages;
      };
      config.nixpkgs.source = inputs.nixpkgs;
    };
    # The usual flake attributes can be defined here, including system-
    # agnostic ones like nixosModule and system-enumerating ones, although
    # those are more easily expressed in perSystem.

  };
}

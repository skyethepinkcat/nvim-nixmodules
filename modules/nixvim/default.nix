{
  mypkgs,
  lib,
}:
lib.nixvim.plugins.mkNeovimPlugin {
  name = "nixmodules";
  package = lib.mkPackageOption mypkgs "nixmodules";
  extraConfig = cfg: opts: {

  };
}

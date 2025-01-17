let defaultCustomConfig = import ./nix/custom-config.nix defaultCustomConfig;
# This file is used by nix-shell.
# It just takes the shell attribute from default.nix.
in
{ withHoogle ? defaultCustomConfig.withHoogle
, profileName ? "default"
, useCabalRun ? true
, customConfig ? {
    inherit withHoogle;
  }
, pkgs ? import ./nix customConfig
# to use profiled build of haskell dependencies:
, profiled ? false
, cardano-mainnet-mirror ? __getFlake "github:input-output-hk/cardano-mainnet-mirror/nix"
}:
with pkgs;
let
  inherit (pkgs) customConfig;
  inherit (customConfig) withHoogle localCluster;
  inherit (pkgs.haskell-nix) haskellLib;
  project = if profiled then qvf-generate-scripts-project.profiled else qvf-generate-scripts-project;

  ## The default shell is defined by flake.nix: (qvf-generate-scripts-project = flake.project.${final.system})
  inherit (project) shell;

  ## XXX: remove this once people retrain their muscle memory:
  dev = project.shell;
in

 shell // { inherit dev; }

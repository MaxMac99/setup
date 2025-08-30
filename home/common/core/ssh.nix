{
  hostSpec,
  lib,
  ...
}: {
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks =
      {
        "*" = {
          addKeysToAgent = "true";
          # useKeychain = true;
        };
        "kopf3.github.com" = lib.hm.dag.entryAfter ["*"] {
          hostname = "github.com";
          identitiesOnly = true;
          identityFile = "~/.ssh/id_kopf3_github";
        };
        "github.com" = lib.hm.dag.entryAfter ["kopf3.github.com"] {
          hostname = "github.com";
          identitiesOnly = true;
          identityFile = "~/.ssh/id_github";
        };
      }
      // lib.optionalAttrs (!hostSpec.isWork) {
        "ionos" = lib.hm.dag.entryAfter ["*"] {
          hostname = "212.132.82.102";
          user = "max";
          identityFile = "~/.ssh/id_ionos_vps";
        };
        "devpi" = lib.hm.dag.entryAfter ["*"] {
          hostname = "192.168.178.185";
          user = "pi";
          identityFile = "~/.ssh/id_devpi";
        };
        "borkenpi4" = lib.hm.dag.entryAfter ["*"] {
          hostname = "192.168.178.118";
          user = "pi";
          identityFile = "~/.ssh/id_borkenpi4";
        };
        "maxdata" = lib.hm.dag.entryAfter ["*"] {
          hostname = "192.168.178.97";
          user = "root";
          identityFile = "~/.ssh/id_maxdata";
        };
      };
  };
}

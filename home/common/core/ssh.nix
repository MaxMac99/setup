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
        "borkenpi4" = lib.hm.dag.entryAfter ["*"] {
          hostname = "192.168.178.118";
          user = "pi";
          identityFile = "~/.ssh/id_borkenpi4";
        };
        "maxdata" = lib.hm.dag.entryAfter ["*"] {
          hostname = "192.168.178.2";
          user = "max";
          identityFile = "~/.ssh/id_ed25519";
        };
        "hetzner" = lib.hm.dag.entryAfter ["*"] {
          hostname = "u499100.your-storagebox.de";
          user = "u499100";
          port = 23;
          identitiesOnly = true;
          identityFile = "~/.ssh/id_hetzner";
        };
      };
  };
}

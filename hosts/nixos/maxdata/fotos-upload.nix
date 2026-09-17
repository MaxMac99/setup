{
  config,
  lib,
  pkgs,
  ...
}: {
  # Photos dropped into the "Fotos Inbox" SMB share are pushed into Immich's
  # internal library by this timer. Uploads go over the API (photos.mvissing.de
  # resolves to Winkel's internal Traefik via the site AdGuard), so no NFS
  # export and no Pulumi change is involved — the inbox is plain storage that
  # only this host reads.
  #
  # ⚠️ The key is scoped deliberately: secrets/fotos-upload.yaml is encrypted
  # for the Mac and maxdata only, not for common.yaml, which every host
  # (including the k3s agents) can read.
  sops.secrets."immich_api_key" = {
    sopsFile = lib.custom.relativeToRoot "secrets/fotos-upload.yaml";
    owner = "max";
  };

  systemd.services.fotos-upload = {
    description = "Upload staged photos from /tank/fotos-inbox into Immich";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    path = [pkgs.immich-cli pkgs.findutils];
    serviceConfig = {
      Type = "oneshot";
      User = "max";
      Group = "users";
      WorkingDirectory = "/tank/fotos-inbox";
    };
    script = ''
      # Via the file path, never readFile: the path lands in the unit, the
      # value never reaches the nix store.
      export IMMICH_API_KEY="$(cat ${config.sops.secrets."immich_api_key".path})"
      export IMMICH_INSTANCE_URL="https://photos.mvissing.de/api"

      # Only files whose mtime is at least 5 minutes old. A copy still in
      # flight from the Mac keeps advancing its mtime, so this is what stops
      # the timer from uploading a half-written file — the CLI would import
      # the truncated bytes and --delete would then remove the original.
      find . -type f -mmin +5 -print0 |
        xargs -0 -r -n 200 immich upload --delete --delete-duplicates --no-progress

      # --delete removes files, not the directories they sat in.
      find . -mindepth 1 -type d -empty -delete
    '';
  };

  systemd.timers.fotos-upload = {
    description = "Upload photos staged in /tank/fotos-inbox every 10 minutes";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "10min";
    };
  };
}

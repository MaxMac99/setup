# kubectl access to the multi-site cluster, deployed declaratively.
#
# ## Why a template rather than one encrypted blob
#
# The obvious approach is to drop the whole `k3s.yaml` into sops and symlink it.
# That buries the API server addresses — which are **not secret** — inside an
# encrypted file, where they cannot be reviewed in a diff and silently duplicate
# `networkConfig`. So only the three credentials are encrypted, and the
# structure is rendered here from the same source of truth every other host
# uses.
#
# ## The three contexts, and why in-site access exists at all
#
# 7.1 scoped the k3s ports to the overlay interface, so a laptop on a site's LAN
# could not reach the API. Phase 8 re-opened **6443 only** on each server's LAN
# interface (`k3sCluster.lanInterface`) and added that LAN address to the API
# server's TLS SANs — both halves are needed, because the port alone gets you a
# certificate error rather than access.
#
#   brink   — on the Brink LAN, direct to brink-server
#   winkel  — on the Winkel LAN, direct to maxdata
#   overlay — at neither site; requires this machine to have joined the mesh
#
# ⚠️ `overlay` will not work until this Mac is actually enrolled in Headscale,
# which it is not. It is defined anyway so the context exists the moment it is,
# and because the SAN it relies on (100.64.0.2) is already in the cert.
{
  config,
  lib,
  pkgs,
  ...
}: let
  net = config.networkConfig;
  brinkApi = net.hosts.brink-server;
  winkelApi = net.hosts.maxdata;
in {
  home-manager.users.${config.hostSpec.username} = {config, ...}: {
    sops.secrets = {
      "kube/ca" = {sopsFile = lib.custom.relativeToRoot "secrets/kubeconfig.yaml";};
      "kube/client-cert" = {sopsFile = lib.custom.relativeToRoot "secrets/kubeconfig.yaml";};
      "kube/client-key" = {sopsFile = lib.custom.relativeToRoot "secrets/kubeconfig.yaml";};
    };

    # Rendered straight to ~/.kube/config so every tool that looks there —
    # kubectl, k9s, IDE plugins — finds it without a KUBECONFIG export.
    sops.templates."kubeconfig" = {
      path = "${config.home.homeDirectory}/.kube/config";
      content = ''
        apiVersion: v1
        kind: Config
        clusters:
          - name: brink
            cluster:
              server: https://${brinkApi.lanIPv4}:6443
              certificate-authority-data: ${config.sops.placeholder."kube/ca"}
          - name: winkel
            cluster:
              server: https://${winkelApi.lanIPv4}:6443
              certificate-authority-data: ${config.sops.placeholder."kube/ca"}
          - name: overlay
            cluster:
              server: https://${brinkApi.overlayIPv4}:6443
              certificate-authority-data: ${config.sops.placeholder."kube/ca"}
        users:
          - name: admin
            user:
              client-certificate-data: ${config.sops.placeholder."kube/client-cert"}
              client-key-data: ${config.sops.placeholder."kube/client-key"}
        contexts:
          - name: brink
            context: {cluster: brink, user: admin}
          - name: winkel
            context: {cluster: winkel, user: admin}
          - name: overlay
            context: {cluster: overlay, user: admin}
        current-context: brink
      '';
    };
  };
}

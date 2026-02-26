# Google Cloud SDK profile
{config, pkgs, ...}: let
  gcloud = pkgs.google-cloud-sdk.withExtraComponents [pkgs.google-cloud-sdk.components.gke-gcloud-auth-plugin];
in {
  home-manager.users.${config.hostSpec.username}.home.packages = [
    gcloud
  ];
}
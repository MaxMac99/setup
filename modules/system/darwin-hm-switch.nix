# `hm-switch` - apply the Home-Manager half of this host's config without sudo.
#
# HM is embedded in darwinConfigurations, so there is no `homeConfigurations`
# output and no `home-manager switch`. Instead this builds the very
# activationPackage darwin-rebuild would activate and runs it the way
# home-manager's nix-darwin module does (`activate --driver-version 1`, as the
# user). Rebuild and hm-switch can therefore alternate freely. Workflow and
# limits: docs/sudoless-workflow.md.
#
# Works only while home-manager.useUserPackages stays false (see base.nix):
# otherwise home.packages are installed by the root system activation.
{
  config,
  pkgs,
  ...
}: let
  inherit (config.hostSpec) username hostName home;

  hmSwitch = pkgs.writeShellApplication {
    name = "hm-switch";
    runtimeInputs = with pkgs; [coreutils];
    # `nix` deliberately comes from the user's PATH: it must match the daemon.
    text = ''
      flake="''${HM_SWITCH_FLAKE:-${home}/projects/private/setup}"
      host="${hostName}"
      dry_run=0
      build_args=()

      usage() {
        cat <<EOF
      usage: hm-switch [--flake <path>] [--host <name>] [-n|--dry-run] [-- <nix build args>]

      Builds darwinConfigurations.<host>'s Home-Manager activationPackage and
      activates it as the current user. No sudo.

        --flake    flake checkout (default: \$HM_SWITCH_FLAKE or $flake)
        --host     darwinConfiguration to build (default: $host)
        --dry-run  build, then show what activation would do without doing it
      EOF
      }

      while (( $# > 0 )); do
        case "$1" in
          --flake) flake="$2"; shift 2 ;;
          --host) host="$2"; shift 2 ;;
          -n|--dry-run) dry_run=1; shift ;;
          -h|--help) usage; exit 0 ;;
          --) shift; build_args+=("$@"); break ;;
          *) usage >&2; exit 1 ;;
        esac
      done

      if [ "$(id -u)" -eq 0 ]; then
        echo "hm-switch: run as ${username}, not root" >&2
        exit 1
      fi

      attr="darwinConfigurations.$host.config.home-manager.users.${username}.home.activationPackage"
      echo "hm-switch: building $flake#$host" >&2
      out="$(nix build --no-link --print-out-paths "$flake#$attr" "''${build_args[@]}" | tail -n 1)"

      if [ "$dry_run" -eq 1 ]; then
        DRY_RUN=1 exec "$out/activate" --driver-version 1
      fi
      exec "$out/activate" --driver-version 1
    '';
  };
in {
  home-manager.users.${username}.home.packages = [hmSwitch];
}

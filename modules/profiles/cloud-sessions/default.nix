# Cloud logins that live and die with one zsh session: `cloud-login`,
# `cloud-logout`, `cloud-status` and `ske-kube` (cloud-sessions.zsh).
#
# ## Why per-session at all
#
# Every CLI's default is a login in ~ (~/.config/gh, ~/.azure,
# ~/.config/gcloud, the login keychain) that every process of this user can
# read - including every AI agent and every shell it spawns. Here each login
# goes into a private per-shell directory under $TMPDIR instead, selected only
# by env vars that the logging-in shell exports. A shell that never ran
# `cloud-login` - an agent's, a new tab - has no credentials, and on exit the
# directory is deleted. A shell that dies without running zshexit is swept by
# the next shell that starts.
#
# ⚠️ This keeps credentials out of places anything finds by default. It is no
# barrier against a process that deliberately hunts: same uid means it can
# read the session directory while the session lives. And anything started
# *from* a logged-in shell inherits the env vars, agents included.
#
# ## stackit has no config-dir variable
#
# Its auth goes to the keychain, keyed by profile. So each session gets a
# throwaway profile (STACKIT_CLI_PROFILE) that is deleted, auth included, with
# the session. ⚠️ If that variable names a profile that does not exist, the CLI
# silently falls back to `default` and logs in globally - so the zsh code checks
# the profile exists before it logs in.
#
# Everything here is home-manager, so `hm-switch` installs it without sudo.
{
  config,
  lib,
  pkgs,
  ...
}: {
  home-manager.users.${config.hostSpec.username} = {
    home.packages = with pkgs; [
      stackit-cli
      kubectl
      # Already in other profiles; listed so the functions do not depend on
      # which ones a host imports. Not gcloud: gcloud.nix builds it with the
      # GKE auth plugin, and a second copy here would collide.
      gh
      azure-cli
      jq
      fzf
    ];

    programs.zsh.initContent = lib.mkAfter (builtins.readFile ./cloud-sessions.zsh);
  };
}

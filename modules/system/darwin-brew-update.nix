# User-context Homebrew auto-updates via launchd LaunchAgents.
#
# Runs entirely as the logged-in user - no sudo, no root. nix-homebrew owns
# /opt/homebrew for the user, and `brew upgrade` (without --greedy) skips
# casks with auto_updates, so app-own updaters stay authoritative ("eine App,
# ein Updater"). The .pkg casks among the shared hardware set (macfuse,
# displaylink) are skipped by the agent for the same reason; they keep
# updating through brew bundle at darwin-rebuild, which runs as root anyway.
#
# Trigger model (docs/update-strategy.md):
#   - calendar: fixed-time runs (launchd runs a missed slot on next wake).
#   - catchup:  RunAtLoad at login, skipped unless `minDays` have passed
#               since the last completed run, delayed 5-15 min so the Mac
#               can settle first.
# Both share one lock dir, so a login catch-up and a calendar slot never run
# concurrently.
#
# Version *supply* is Renovate: taps are store-pinned, so new versions reach
# the machine only via flake bumps + darwin-rebuild re-pointing the tap
# symlinks. This agent is the "apply" step that installs what the taps know.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.brewAutoupdate;

  script = pkgs.writeShellApplication {
    name = "brew-autoupdate";
    runtimeInputs = with pkgs; [coreutils];
    text = ''
      mode="''${1:-scheduled}"
      min_days="''${BAU_MIN_DAYS:-3}"

      export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

      state_dir="$HOME/Library/Application Support/brew-autoupdate"
      log_file="$HOME/Library/Logs/brew-autoupdate.log"
      stamp_file="$state_dir/last-run"
      lock_dir="''${TMPDIR:-/tmp}/brew-autoupdate.lock"
      mkdir -p "$state_dir" "$(dirname "$log_file")"

      notify() {
        /usr/bin/osascript -e "display notification \"$2\" with title \"Homebrew\" subtitle \"$1\"" >/dev/null 2>&1 || true
      }

      # Single-flight lock; a stale one (kill -9 mid-run) is ignored after 2 h.
      if ! mkdir "$lock_dir" 2>/dev/null; then
        if ! /usr/bin/find "$lock_dir" -maxdepth 0 -mmin +120 >/dev/null 2>&1; then
          exit 0
        fi
        rmdir "$lock_dir" 2>/dev/null || exit 0
        mkdir "$lock_dir"
      fi
      trap 'rmdir "$lock_dir" 2>/dev/null' EXIT

      if [ "$mode" = "catchup" ]; then
        # Skip inside the minimum-days window ...
        if [ -f "$stamp_file" ]; then
          last_run="$(cat "$stamp_file")"
          now="$(date +%s)"
          if [ -n "$last_run" ] && [ "$((now - last_run))" -lt "$((min_days * 86400))" ]; then
            exit 0
          fi
        fi
        # ... and let the machine settle after login (5-15 min).
        sleep $((RANDOM % 600 + 300))
      fi

      echo "=== $(date '+%Y-%m-%d %H:%M:%S') mode=$mode ===" >> "$log_file"

      rc=0
      names=""
      count=0

      outdated="$(brew outdated 2>&1)" && outdated_rc=0 || outdated_rc=$?
      {
        echo "--- outdated (rc=$outdated_rc) ---"
        [ -n "$outdated" ] && printf '%s\n' "$outdated"
      } >> "$log_file"

      if [ "$outdated_rc" -eq 0 ] && [ -n "$outdated" ]; then
        names="$(printf '%s\n' "$outdated" | awk '{print $1}')"
      fi

      if [ "$outdated_rc" -ne 0 ]; then
        rc=$outdated_rc
      elif [ -n "$names" ]; then
        upgrade_out="$(brew upgrade 2>&1)" && upgrade_rc=0 || upgrade_rc=$?
        {
          echo "--- upgrade (rc=$upgrade_rc) ---"
          printf '%s\n' "$upgrade_out"
        } >> "$log_file"
        [ "$upgrade_rc" -ne 0 ] && rc=$upgrade_rc
      fi

      cleanup_out="$(brew cleanup 2>&1)" && cleanup_rc=0 || cleanup_rc=$?
      {
        echo "--- cleanup (rc=$cleanup_rc) ---"
        printf '%s\n' "$cleanup_out"
      } >> "$log_file"
      if [ "$rc" -eq 0 ] && [ "$cleanup_rc" -ne 0 ]; then
        rc=$cleanup_rc
      fi

      date +%s > "$stamp_file"

      if [ -n "$names" ]; then
        count="$(printf '%s\n' "$names" | grep -c . || true)"
      fi

      if [ "$rc" -ne 0 ]; then
        notify "Update fehlgeschlagen" "brew beendet mit rc=$rc - Details: $log_file"
      elif [ "$count" -gt 0 ]; then
        preview="$(printf '%s\n' "$names" | head -n 4 | tr '\n' ' ')"
        more=""
        if [ "$count" -gt 4 ]; then
          more=", ..."
        fi
        notify "$count Updates installiert" "$preview$more"
      fi

      exit "$rc"
    '';
  };
in {
  options.brewAutoupdate = {
    enable = lib.mkEnableOption "user-context Homebrew auto-updates via LaunchAgent";

    catchup = {
      enable = lib.mkEnableOption ''
        a catch-up run at login (RunAtLoad), skipped unless `minDays` have
        passed since the last completed run
      '';
      minDays = lib.mkOption {
        type = lib.types.ints.positive;
        default = 3;
        description = ''
          Minimum days between runs. Applies to the login catch-up only -
          calendar runs always fire.
        '';
      };
    };

    calendar = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.int);
      default = [];
      example = [
        {
          Weekday = 2;
          Hour = 10;
          Minute = 0;
        }
      ];
      description = ''
        StartCalendarInterval entries (launchd plist keys, 0 and 7 = Sunday)
        for fixed-time upgrade runs. A slot missed while the Mac is off runs
        on next wake.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Plain `brew upgrade` already excludes casks with auto_updates; --greedy
    # would fight those apps' own updaters, so it must stay off.
    launchd.user.agents.brew-autoupdate = lib.mkIf (cfg.calendar != []) {
      path = ["/opt/homebrew/bin"];
      serviceConfig = {
        ProgramArguments = ["${script}/bin/brew-autoupdate" "scheduled"];
        StartCalendarInterval = cfg.calendar;
      };
    };

    launchd.user.agents.brew-autoupdate-catchup = lib.mkIf cfg.catchup.enable {
      path = ["/opt/homebrew/bin"];
      serviceConfig = {
        ProgramArguments = ["${script}/bin/brew-autoupdate" "catchup"];
        RunAtLoad = true;
        EnvironmentVariables = {
          BAU_MIN_DAYS = toString cfg.catchup.minDays;
        };
      };
    };
  };
}

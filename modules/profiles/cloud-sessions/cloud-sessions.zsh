# Session-scoped cloud logins - the why is in ./default.nix.
#
#   cloud-login                  pick providers with fzf (TAB marks several)
#   cloud-login gh stackit       those providers
#   cloud-login all              gh az gcloud stackit
#   cloud-login az --tenant X    one provider, extra args go to its login
#   cloud-status                 what this shell is logged into
#   cloud-logout                 wipe this shell's logins now (exit does too)
#   ske-kube [--idp]             pick STACKIT projects + SKE clusters (TAB marks
#                                several), add them to a session-only kubeconfig
#                                as <project>/<cluster> contexts

# Per-user ($TMPDIR is /var/folders/…/T on macOS). Session dirs are named
# <shell pid>.<random>, which is what lets a later shell spot dead ones.
typeset -g _CS_ROOT="${${TMPDIR:-/tmp}%/}/cloud-sessions"
# Deliberately not exported: a nested shell inherits the logins but must not
# delete its parent's directory when it exits.
typeset -g _CS_DIR=""
typeset -ga _CS_PROVIDERS=(gh az gcloud stackit)

_cs_ensure() {
  [[ -n $_CS_DIR && -d $_CS_DIR ]] && return 0
  mkdir -p -m 700 -- "$_CS_ROOT" || return 1
  _CS_DIR=$(mktemp -d "$_CS_ROOT/$$.XXXXXX") || return 1
  chmod 700 -- "$_CS_DIR"
}

# Delete one session dir, and the stackit profile (keychain auth included)
# that it recorded.
_cs_destroy() {
  local dir=$1 profile
  if [[ -r $dir/stackit-profile ]]; then
    profile=$(<"$dir/stackit-profile")
    env -u STACKIT_CLI_PROFILE stackit config profile delete "$profile" --assume-yes >/dev/null 2>&1
  fi
  rm -rf -- "$dir"
}

# Dirs whose shell is gone - closed window, crash, kill -9. Builtins only
# unless something is actually stale, so this is cheap at every shell start.
_cs_sweep() {
  local dir
  for dir in "$_CS_ROOT"/*(N/); do
    [[ $dir == "$_CS_DIR" ]] && continue
    kill -0 "${${dir:t}%%.*}" 2>/dev/null && continue
    _cs_destroy "$dir"
  done
}

_cs_login_gh() {
  export GH_CONFIG_DIR=$_CS_DIR/gh
  # Either would win over the session login.
  unset GH_TOKEN GITHUB_TOKEN
  # --insecure-storage: hosts.yml in the session dir rather than the login
  # keychain. ssh + --skip-ssh-key: no `gh auth setup-git` writing a credential
  # helper into the global ~/.gitconfig, no key upload.
  gh auth login --hostname github.com --web --insecure-storage \
    --git-protocol ssh --skip-ssh-key "$@"
}

_cs_login_az() {
  export AZURE_CONFIG_DIR=$_CS_DIR/azure
  az login "$@"
}

_cs_login_gcloud() {
  if (( ! $+commands[gcloud] )); then
    print -u2 "cloud-login: gcloud not installed (modules/profiles/gcloud.nix)"
    return 1
  fi
  export CLOUDSDK_CONFIG=$_CS_DIR/gcloud
  local adc=$CLOUDSDK_CONFIG/application_default_credentials.json project
  # --update-adc: the same browser round-trip also writes the
  # application-default credentials for SDKs, Terraform, Pulumi - into
  # $CLOUDSDK_CONFIG, not ~/.config/gcloud.
  gcloud auth login --update-adc "$@" || return 1
  if [[ ! -s $adc ]]; then
    print -u2 "cloud-login: gcloud wrote no application-default credentials ($adc)"
    return 1
  fi
  # Not every client library reads CLOUDSDK_CONFIG; all of them read this.
  # Only exported once the file exists: pointing it at a missing file is an
  # error, not a fallback.
  export GOOGLE_APPLICATION_CREDENTIALS=$adc

  # User ADC without a quota project is rejected by many APIs ("requires a
  # quota project, which is not set by default"). The session config starts
  # empty, so pick the project here; it becomes both the gcloud default and
  # the ADC quota project.
  project=$(gcloud config get project 2>/dev/null)
  if [[ -z $project ]]; then
    project=$(gcloud projects list --format='value(projectId,name)' 2>/dev/null |
      fzf --delimiter='\t' --height=~20 --prompt='gcloud project> ' \
        --header='ESC: kein Projekt' | cut -f1)
  fi
  if [[ -z $project ]]; then
    print -u2 "cloud-login: no gcloud project set - ADC has no quota project"
    return 0
  fi
  gcloud config set project "$project" --quiet >/dev/null 2>&1 &&
    gcloud auth application-default set-quota-project "$project" --quiet >/dev/null 2>&1 ||
    print -u2 "cloud-login: could not set quota project $project (needs serviceusage.services.use)"
}

_cs_login_stackit() {
  local profile
  if [[ -r $_CS_DIR/stackit-profile ]]; then
    profile=$(<"$_CS_DIR/stackit-profile")
  else
    # Profile names must match ^[a-z0-9][a-z0-9-]+$.
    profile="session-$$-${${_CS_DIR:t}#*.}"
    profile=${profile:l}
    # Without --empty the profile copies the default profile's settings
    # (endpoints, default project), never its auth.
    env -u STACKIT_CLI_PROFILE stackit config profile create "$profile" --no-set >/dev/null 2>&1
    print -r -- "$profile" > "$_CS_DIR/stackit-profile"
  fi
  # A missing profile means a silent login into `default`, i.e. globally.
  if ! env -u STACKIT_CLI_PROFILE stackit config profile list -o json 2>/dev/null |
    jq -e --arg p "$profile" 'any(.[]; .Name == $p)' >/dev/null; then
    print -u2 "cloud-login: stackit profile $profile missing, refusing to log in"
    return 1
  fi
  export STACKIT_CLI_PROFILE=$profile
  stackit auth login "$@"
}

cloud-login() {
  local -a chosen extra
  local p failed=0

  while (( $# )) && [[ $1 != -* ]]; do
    if [[ $1 == all ]]; then
      chosen+=($_CS_PROVIDERS)
    elif (( ${_CS_PROVIDERS[(Ie)$1]} )); then
      chosen+=($1)
    else
      print -u2 "cloud-login: unknown provider '$1' (${(j:, :)_CS_PROVIDERS}, all)"
      return 1
    fi
    shift
  done
  extra=("$@")
  if (( $#extra && $#chosen != 1 )); then
    print -u2 "cloud-login: extra arguments need exactly one provider"
    return 1
  fi
  if (( ! $#chosen )); then
    chosen=(${(f)"$(print -l $_CS_PROVIDERS |
      fzf --multi --height=~10 --prompt='login> ' --header='TAB: mehrere')"})
    (( $#chosen )) || return 1
  fi

  _cs_sweep
  _cs_ensure || return 1
  for p in ${(u)chosen}; do
    print -P "%B==> $p%b"
    "_cs_login_$p" "${extra[@]}" || { print -u2 "cloud-login: $p failed"; failed=1; }
  done
  return $failed
}

cloud-status() {
  if [[ -z $_CS_DIR ]]; then
    print "no cloud session in this shell"
    return 0
  fi
  print "session: $_CS_DIR"
  [[ -s $GH_CONFIG_DIR/hosts.yml ]] && print "  gh       logged in"
  [[ -s $AZURE_CONFIG_DIR/msal_token_cache.json ]] && print "  az       logged in"
  [[ -s $CLOUDSDK_CONFIG/credentials.db ]] && print "  gcloud   logged in"
  [[ -s $GOOGLE_APPLICATION_CREDENTIALS && $GOOGLE_APPLICATION_CREDENTIALS == $_CS_DIR/* ]] &&
    print "  gcloud   application-default credentials, quota project $(jq -r '.quota_project_id // "-"' "$GOOGLE_APPLICATION_CREDENTIALS")"
  [[ -n $STACKIT_CLI_PROFILE ]] && print "  stackit  profile $STACKIT_CLI_PROFILE"
  [[ $KUBECONFIG == $_CS_DIR/* ]] &&
    print "  kube     $(kubectl config current-context 2>/dev/null)"
  return 0
}

_cs_cleanup() {
  [[ -n $_CS_DIR ]] || return 0
  _cs_destroy "$_CS_DIR"
  _CS_DIR=""
}

cloud-logout() {
  local var
  _cs_cleanup
  for var in GH_CONFIG_DIR AZURE_CONFIG_DIR CLOUDSDK_CONFIG GOOGLE_APPLICATION_CREDENTIALS KUBECONFIG; do
    [[ ${(P)var} == "$_CS_ROOT"/* ]] && unset $var
  done
  [[ $STACKIT_CLI_PROFILE == session-* ]] && unset STACKIT_CLI_PROFILE
  print "cloud session wiped"
}

ske-kube() {
  local mode=--login line name tmp src
  local -a projects picks fields
  case ${1:-} in
    "") ;;
    # Non-admin kubeconfig via the STACKIT IDP, for clusters where the
    # project role does not grant admin.
    --idp) mode=--idp ;;
    *) print -u2 "usage: ske-kube [--idp]"; return 1 ;;
  esac

  if [[ -z $_CS_DIR || ! -r $_CS_DIR/stackit-profile ]]; then
    cloud-login stackit || return 1
  fi

  projects=(${(f)"$(stackit project list -o json |
    jq -r '(. // [])[] | [.name, .projectId] | @tsv' |
    fzf --multi --delimiter='\t' --with-nth=1 --height=~20 \
      --prompt='project> ' --header='TAB: mehrere')"})
  (( $#projects )) || return 1

  # One row per cluster: project, cluster, version, status, project id. A
  # project whose cluster list fails (SKE not enabled) just contributes none.
  picks=(${(f)"$(for line in $projects; do
      stackit ske cluster list --project-id "${line##*$'\t'}" -o json |
        jq -r --arg p "${line%%$'\t'*}" --arg id "${line##*$'\t'}" \
          '(. // [])[] | [$p, .name, (.kubernetes.version // "?"), (.status.aggregated // "?"), $id] | @tsv'
    done | fzf --multi --delimiter='\t' --with-nth=1..4 --height=~20 \
      --prompt='cluster> ' --header='TAB: mehrere')"})
  (( $#picks )) || return 1

  mkdir -p -m 700 -- "$_CS_DIR/kube" || return 1
  export KUBECONFIG=$_CS_DIR/kube/config
  tmp=$_CS_DIR/kube/new
  for line in $picks; do
    fields=("${(@ps:\t:)line}")
    # SKE names context, cluster and user all after the cluster, so the same
    # cluster name in two projects would overwrite each other on merge.
    # Prefixing the project keeps them apart in `k9s :ctx`.
    name="${${fields[1]:l}// /-}/$fields[2]"
    rm -f -- "$tmp".{yaml,json}
    # --login: no credential in the file. kubectl calls back into
    # `stackit ske kubeconfig login`, i.e. into this session's profile, so the
    # kubeconfig dies with the session. Its credential cache in
    # ~/Library/Caches/stackit is encrypted with a key held by that profile,
    # so it is unreadable once the profile is gone.
    if ! stackit ske kubeconfig create "$fields[2]" --project-id "$fields[5]" "$mode" \
      --filepath "$tmp.yaml" --assume-yes >/dev/null; then
      print -u2 "ske-kube: $name failed"
      continue
    fi
    # Renaming the entries is safe: the login plugin finds the cluster through
    # the exec extension on the cluster entry, not through its name.
    kubectl config view --raw -o json --kubeconfig "$tmp.yaml" |
      jq --arg n "$name" '
        .clusters |= map(.name = $n) | .users |= map(.name = $n)
        | .contexts |= map(.name = $n | .context.cluster = $n | .context.user = $n)
        | ."current-context" = $n' > "$tmp.json" || continue
    # New file first: it wins on a re-fetch of the same cluster, and its
    # current-context becomes the active one.
    src=$tmp.json
    [[ -e $KUBECONFIG ]] && src+=":$KUBECONFIG"
    KUBECONFIG=$src kubectl config view --raw --flatten > "$KUBECONFIG.next" &&
      chmod 600 -- "$KUBECONFIG.next" && mv -- "$KUBECONFIG.next" "$KUBECONFIG"
  done
  rm -f -- "$tmp".{yaml,json} "$KUBECONFIG.next"

  [[ -e $KUBECONFIG ]] || return 1
  print "KUBECONFIG=$KUBECONFIG"
  kubectl config get-contexts
}

compdef '_arguments "*:provider:(gh az gcloud stackit all)"' cloud-login
compdef '_arguments "1:mode:(--idp)"' ske-kube

autoload -Uz add-zsh-hook
add-zsh-hook zshexit _cs_cleanup
_cs_sweep

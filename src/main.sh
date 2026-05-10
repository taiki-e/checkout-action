#!/bin/false
# SPDX-License-Identifier: Apache-2.0 OR MIT
# shellcheck shell=bash # not executable, must be called with `--noprofile --norc --posix`
set -CeEuo pipefail
IFS=$'\n\t'

g() {
  IFS=' '
  builtin local cmd="$*"
  IFS=$'\n\t'
  printf '::group::%s\n' "${cmd#retry }"
  "$@" 2>&1
  printf '::endgroup::\n'
}
g_for_hw_info() {
  IFS=' '
  builtin local cmd="$*"
  IFS=$'\n\t'
  printf '::group::Show hardware information (%s)\n' "${cmd#retry }"
  "$@" 2>&1 || :
  printf '::endgroup::\n'
}
retry() {
  for i in {1..10}; do
    if "$@"; then
      return 0
    else
      sleep "${i}"
    fi
  done
  "$@"
}
bail() {
  printf '::error::checkout-action: %s\n' "$*"
  exit 1
}
warn() {
  printf '::warning::checkout-action: %s\n' "$*"
}
# Use binaries available at standard location to prevent path interception.
# See resolve_path in action.yml for more.
# NB: Sync with it.
resolve_path() {
  for dir in /bin /usr/bin /sbin /usr/sbin; do
    if [[ -x "${dir}/$1" ]]; then
      printf '%s/%s\n' "${dir}" "$1"
      return
    fi
  done
  if [[ -e /etc/NIXOS ]] && [[ -x /run/current-system/sw/bin/"$1" ]]; then
    printf '/run/current-system/sw/bin/%s\n' "$1"
  elif [[ -e /etc/NIXOS ]] && [[ -x /run/wrappers/bin/"$1" ]]; then
    printf '/run/wrappers/bin/%s\n' "$1"
  elif [[ -e /etc/nix ]] && [[ -x /root/.nix-profile/bin/"$1" ]]; then
    printf '/root/.nix-profile/bin/%s\n' "$1"
  fi
}

token="${INPUT_TOKEN}"
# This prevents tokens from being exposed to subprocesses via environment variables.
# Note that this does not prevent token leaks via reading `/proc/*/environ` on Linux or
# via `ps -Eww` on macOS. It only reduces the risk of leaks.
unset INPUT_TOKEN
# This prevents tokens from being exposed to log when tracing is activated.
unset GIT_TRACE_REDACT GIT_TRACE2_REDACT GIT_CURL_VERBOSE GIT_TRACE_CURL

repository_url="${INPUT_SERVER_URL}/${INPUT_REPOSITORY}"

# Since we currently do not support checking out other repositories, this should always be enforced.
# https://github.blog/security/application-security/improving-git-protocol-security-github/
export GIT_ALLOW_PROTOCOL=https:ssh

if [[ -n "${HAS_TOKEN}" ]]; then
  protocol="${INPUT_SERVER_URL%%://*}"
  hostname="${INPUT_SERVER_URL#*://}"
  hostname="${hostname%%/*}"
  # Sanitize inputs and runner-provided environment variables for credential helper which uses line-separated format.
  # Also sanitize encoded newline (%0a) and carriage return (\r, %0d) for old git affected by CVE-2020-5260/CVE-2024-52006.
  for c in $'\n' '%0a' '%0A' $'\r' '%0d' '%0D'; do
    if [[ "${protocol}" == *"${c}"* ]] || [[ "${hostname}" == *"${c}"* ]] || [[ "${token}" == *"${c}"* ]]; then
      bail "github.server_url and 'token' input option must not contain newline"
    fi
  done
fi

sleep=$(resolve_path sleep)
if [[ -n "${sleep}" ]]; then
  sleep() { "${sleep}" "$1"; }
else
  # Fallback to non-sleep when sleep is unavailable at standard location.
  # bash read has -t option, but use non-sleep to match src/install-required-tools for now.
  sleep() { :; }
fi
is_fake_home=''
git=$(resolve_path git)
case "${RUNNER_OS}" in
  Linux)
    lscpu=$(resolve_path lscpu)
    if [[ -n "${lscpu}" ]]; then
      # Output CPU information to make it easier to debug the runner issues.
      g_for_hw_info "${lscpu}"
    fi
    if [[ -z "${git}" ]]; then
      git=$(builtin type -P git || :)
      if [[ -z "${git}" ]]; then
        bail "this action requires git"
      elif [[ -n "${HAS_TOKEN}" ]]; then
        bail "git is unavailable at standard location; found ${git}; aborting due to security reasons because 'token' input option is set"
      else
        warn "git is unavailable at standard location; using ${git}, but this may be blocked for security reasons in the future"
      fi
    fi
    ;;
  macOS)
    # Output CPU information to make it easier to debug the runner issues.
    g_for_hw_info /usr/sbin/sysctl hw.optional machdep.cpu
    if [[ -z "${git}" ]]; then
      git=$(builtin type -P git || :)
      if [[ -z "${git}" ]]; then
        bail "this action requires git"
      elif [[ -n "${HAS_TOKEN}" ]]; then
        bail "git is unavailable at standard location; found ${git}; aborting due to security reasons because 'token' input option is set"
      else
        warn "git is unavailable at standard location; using ${git}, but this may be blocked for security reasons in the future"
      fi
    fi
    ;;
  Windows)
    if [[ "${HOME}" == "/home/"* ]]; then
      is_fake_home=1
    fi
    # See action.yml.
    printf '' >|"${USERPROFILE}/.checkout-action-init"
    # Output CPU information to make it easier to debug the runner issues.
    g_for_hw_info 'C:\Windows\system32\systeminfo.exe'
    if [[ -z "${git}" ]]; then
      git=$(builtin type -P git || :)
      case "${git}" in
        /mingw64/bin/git) ;;                        # x86_64 runner default
        /clangarm64/bin/git) ;;                     # aarch64 runner default
        '/c/Program Files/Git/bin/git') ;;          # MSYS2
        '/cygdrive/c/Program Files/Git/bin/git') ;; # Cygwin
        *)
          if [[ -x /mingw64/bin/git ]]; then
            git=/mingw64/bin/git
          elif [[ -x /clangarm64/bin/git ]]; then
            git=/clangarm64/bin/git
          elif [[ -x '/c/Program Files/Git/bin/git' ]]; then
            git='/c/Program Files/Git/bin/git'
          elif [[ -x '/cygdrive/c/Program Files/Git/bin/git' ]]; then
            git='/cygdrive/c/Program Files/Git/bin/git'
          elif [[ -x 'C:\Program Files\Git\bin\git.exe' ]]; then
            git='C:\Program Files\Git\bin\git.exe'
          elif [[ -z "${git}" ]]; then
            bail "this action requires git"
          elif [[ -n "${HAS_TOKEN}" ]]; then
            bail "git is unavailable at standard location; found ${git}; aborting due to security reasons because 'token' input option is set"
          else
            warn "git is unavailable at standard location; using ${git}, but this may be blocked for security reasons in the future"
          fi
          ;;
      esac
    fi
    ;;
  *) bail "unrecognized OS '${RUNNER_OS}'" ;;
esac

wd="${PWD}"

# Since we disable template at git init, they normally do nothing, and in compromised environments
# (or environments that were previously compromised and only incompletely repaired) they can lead to
# arbitrary code execution.
common_args=(-c core.hooksPath=/dev/null -c core.fsmonitor=false)

git_version=$("${git}" "${common_args[@]}" version)
git_version="${git_version#git version }"
printf 'git version: %s\n' "${git_version}"
printf 'bash version: %s\n' "${BASH_VERSION:-}"
# --local and --no-recurse-submodules require git 1.8.
if [[ "${git_version}" == '1.'* ]] && [[ "${git_version}" != '1.8.'* ]] && [[ "${git_version}" != '1.9.'* ]]; then
  warn "this action requires git 1.8+"
fi
if [[ -n "${HAS_TOKEN}" ]]; then
  # Setting empty value via -c requires git 2.0.
  # We use local config to mitigate the impact of their absence, but using git 2.0+ is best.
  if [[ "${git_version}" == '1.'* ]]; then
    warn "when using 'token' input option, it is recommended using git 2.0+ for security reasons"
    has_c_flag_with_empty_val=''
  else
    has_c_flag_with_empty_val=1
  fi
fi

# Disable template to avoid needless copy of sample hooks and reduce risk of hook injections in
# compromised environments. This option takes precedence, so there is no need to modify environment
# variables or configs: https://git-scm.com/docs/git-init#_template_directory
g "${git}" "${common_args[@]}" -c advice.defaultBranchName=false init --template=''

# error: could not lock config file C:/tools/cygwin/home/runneradmin/.gitconfig: No such file or directory
# error: could not lock config file C:/msys64/home/runneradmin/.gitconfig: No such file or directory
if [[ -n "${is_fake_home}" ]]; then
  g "${git}" "${common_args[@]}" config --global --add safe.directory "${wd}" || :
else
  g "${git}" "${common_args[@]}" config --global --add safe.directory "${wd}"
fi

g "${git}" "${common_args[@]}" remote add origin "${repository_url}"

g "${git}" "${common_args[@]}" config --local gc.auto 0

# Disable askPass to prevent arbitrary code execution if authentication fails.
# Enforce sslVerify to ensure security of https.
unset GIT_ASKPASS GIT_SSL_NO_VERIFY
fetch_args=(
  -c core.askPass=/dev/null
  -c "http.${repository_url}.sslVerify=true"
  -c "https.${repository_url}.sslVerify=true"
)
checkout_args=()
fetch_args+=(fetch --no-tags --prune --no-recurse-submodules --depth=1 origin)
checkout_args+=(checkout --force)
if [[ "${INPUT_REF}" == "refs/heads/"* ]]; then
  branch="${INPUT_REF#refs/heads/}"
  remote_ref="refs/remotes/origin/${branch}"
  fetch_args+=("+${INPUT_SHA}:${remote_ref}")
  checkout_args+=(-B "${branch}" "${remote_ref}")
else
  fetch_args+=("+${INPUT_SHA}:${INPUT_REF}")
  checkout_args+=("${INPUT_REF}")
fi

IFS=' '
cmd="${git} ${common_args[*]} ${fetch_args[*]}"
IFS=$'\n\t'
printf '::group::%s\n' "${cmd}"
if [[ -n "${HAS_TOKEN}" ]]; then
  # The first credential.helper= is needed to ignore existing credential helpers.
  if [[ -n "${has_c_flag_with_empty_val}" ]]; then
    first_credential_helper=(-c credential.helper=)
  else
    "${git}" "${common_args[@]}" config --local credential.helper ''
    first_credential_helper=()
  fi
  # https://git-scm.com/docs/gitcredentials#_custom_helpers
  # NB: Sync credential helper function with tools/ci/test-bash-func.sh.
  # shellcheck disable=SC2016
  INPUT_PROTOCOL="${protocol}" \
    INPUT_HOSTNAME="${hostname}" \
    INPUT_TOKEN="${token}" \
    retry "${git}" "${common_args[@]}" \
    ${first_credential_helper[@]+"${first_credential_helper[@]}"} \
    -c credential."${repository_url}".helper='!f() {
protocol=""
host=""
while IFS= read -r line || [ -n "${line}" ]; do
  case "${line}" in
    protocol=*) protocol="${line#protocol=}" ;;
    host=*) host="${line#host=}" ;;
  esac
done
if [ "${protocol}" = "${INPUT_PROTOCOL}" ] && [ "${host}" = "${INPUT_HOSTNAME}" ]; then
  printf "protocol=%s\nhost=%s\nusername=x-access-token\npassword=%s\n" "${INPUT_PROTOCOL}" "${INPUT_HOSTNAME}" "${INPUT_TOKEN}"
fi
}; f' \
    "${fetch_args[@]}" 2>&1
else
  retry "${git}" "${common_args[@]}" "${fetch_args[@]}" 2>&1
fi
printf '::endgroup::\n'

if [[ -n "${HAS_TOKEN}" ]]; then
  if [[ -z "${has_c_flag_with_empty_val}" ]]; then
    "${git}" "${common_args[@]}" config --unset --local credential.helper
  fi
fi

g retry "${git}" "${common_args[@]}" "${checkout_args[@]}"

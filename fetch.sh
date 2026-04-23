#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -CeEuo pipefail
IFS=$'\n\t'

# "fetch" step of checkout-action.
#
# "checkout" step is separated into a different step that does not handle sensitive data (checkout.sh),
# because it does not require tokens.
#
# "prepare" step, which includes installing Git, is also separated into a different step that does not
# handle sensitive data (pre.sh), because it does not require tokens and may take some time (i.g., the time
# the token remains exposed in `/proc/*/environ` becomes longer.

g() {
  IFS=' '
  local cmd="$*"
  IFS=$'\n\t'
  printf '::group::%s\n' "${cmd#retry }"
  "$@" 2>&1
  printf '::endgroup::\n'
}
retry() {
  for i in {1..10}; do
    if "$@"; then
      return 0
    else
      "${sleep}" "${i}"
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
resolve_path() {
  if [[ -x /bin/"$1" ]]; then
    printf '/bin/%s\n' "$1"
  elif [[ -x /usr/bin/"$1" ]]; then
    printf '/usr/bin/%s\n' "$1"
  fi
}

if [[ $# -gt 0 ]]; then
  bail "internal error: invalid argument '$1'"
fi

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
if [[ -z "${sleep}" ]]; then
  sleep=$(type -P sleep)
  if [[ -n "${HAS_TOKEN}" ]]; then
    bail "sleep is unavailable at standard location; found ${sleep}"
  fi
fi
case "${RUNNER_OS}" in
  Windows)
    git=$(type -P git)
    case "${git}" in
      /mingw64/bin/git) ;;                        # x86_64 runner default
      /clangarm64/bin/git) ;;                     # aarch64 runner default
      '/c/Program Files/Git/bin/git') ;;          # msys64
      '/cygdrive/c/Program Files/Git/bin/git') ;; # cygwin
      *)
        if [[ -x /mingw64/bin/git ]]; then
          git=/mingw64/bin/git
        elif [[ -x /clangarm64/bin/git ]]; then
          git=/clangarm64/bin/git
        elif [[ -x '/c/Program Files/Git/bin/git' ]]; then
          git='/c/Program Files/Git/bin/git'
        elif [[ -x /clangarm64/bin/git ]]; then
          git='/cygdrive/c/Program Files/Git/bin/git'
        elif [[ -x 'C:\Program Files\Git\bin\git.exe' ]]; then
          git='C:\Program Files\Git\bin\git.exe'
        elif [[ -n "${HAS_TOKEN}" ]]; then
          bail "git is unavailable at standard location; found ${git}"
        fi
        ;;
    esac
    home="${HOME}"
    if [[ "${home}" == "/home/"* ]]; then
      if [[ -d "${home/\/home\///c/Users/}" ]]; then
        # MSYS2 https://github.com/taiki-e/install-action/pull/518#issuecomment-2160736760
        home="${home/\/home\///c/Users/}"
      elif [[ -d "${home/\/home\///cygdrive/c/Users/}" ]]; then
        # Cygwin https://github.com/taiki-e/install-action/issues/224#issuecomment-1720196288
        home="${home/\/home\///cygdrive/c/Users/}"
      fi
    fi
    # See action.yml.
    printf '' >|"${home}/.checkout-action-init"
    ;;
  *)
    git=$(resolve_path git)
    if [[ -z "${git}" ]]; then
      git=$(type -P git)
      if [[ -n "${HAS_TOKEN}" ]]; then
        bail "git is unavailable at standard location; found ${git}"
      fi
    fi
    ;;
esac

# Since we disable template at git init, they normally do nothing, and in compromised environments
# (or environments that were previously compromised and only incompletely repaired) they can lead to
# arbitrary code execution.
# NB: Sync with pre.sh and checkout.sh.
common_args=(-c core.hooksPath=/dev/null -c core.fsmonitor=false)

if [[ -n "${HAS_TOKEN}" ]]; then
  git_version=$("${git}" "${common_args[@]}" version)
  # Setting empty value via -c requires git 2.0.
  # We use local config to mitigate the impact of their absence, but using git 2.0+ is best.
  if [[ "${git_version}" == 'git version 1.'* ]]; then
    warn "when using 'token' input option, it is recommended using git 2.0+ for security reasons"
    has_c_flag_with_empty_val=''
  else
    has_c_flag_with_empty_val=1
  fi
fi

# Disable askPass to prevent arbitrary code execution if authentication fails.
# Enforce sslVerify to ensure security of https.
unset GIT_ASKPASS GIT_SSL_NO_VERIFY
fetch_args=(
  -c core.askPass=/dev/null
  -c "http.${repository_url}.sslVerify=true"
  -c "https.${repository_url}.sslVerify=true"
)
fetch_args+=(fetch --no-tags --prune --no-recurse-submodules --depth=1 origin)
if [[ "${INPUT_REF}" == "refs/heads/"* ]]; then
  branch="${INPUT_REF#refs/heads/}"
  remote_ref="refs/remotes/origin/${branch}"
  fetch_args+=("+${INPUT_SHA}:${remote_ref}")
else
  fetch_args+=("+${INPUT_SHA}:${INPUT_REF}")
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
  # shellcheck disable=SC2016
  INPUT_PROTOCOL="${protocol}" \
    INPUT_HOSTNAME="${hostname}" \
    INPUT_TOKEN="${token}" \
    retry "${git}" "${common_args[@]}" \
    ${first_credential_helper[@]+"${first_credential_helper[@]}"} \
    -c 'credential.helper=!f() {
protocol=""
host=""
while IFS= read -r line; do
  case "${line}" in
    protocol=*) protocol="${line#protocol=}" ;;
    host=*) host="${line#host=}" ;;
  esac
  [ -n "${line}" ] || break
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

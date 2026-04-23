#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -CeEuo pipefail
IFS=$'\n\t'

# "checkout" step of checkout-action.
#
# See the top-level comments of fetch.sh for details.

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
if [[ -n "${INPUT_TOKEN:-}" ]]; then
  bail "INPUT_TOKEN must not set"
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

checkout_args=(checkout --force)
if [[ "${INPUT_REF}" == "refs/heads/"* ]]; then
  branch="${INPUT_REF#refs/heads/}"
  remote_ref="refs/remotes/origin/${branch}"
  checkout_args+=(-B "${branch}" "${remote_ref}")
else
  checkout_args+=("${INPUT_REF}")
fi

g retry "${git}" "${checkout_args[@]}"

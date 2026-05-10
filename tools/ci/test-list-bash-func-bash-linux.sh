#!/bin/false
# SPDX-License-Identifier: Apache-2.0 OR MIT
# shellcheck shell=sh # not executable
set -eu

# Note: This is test-only. action.yml uses different approach.
#
# Detect environment variables that may inject bash functions and output a
# list of -u options to be passed to env command to unset them.
#
# This approach only works for OS which has /proc/self/environ.
# The equivalent of /proc/self/environ on macOS is `ps -Eww $$`, but do not
# distinguish between space used as separators and space within environment
# variables in its output (env command has the same issue).
#   $ A='a b=c' /bin/bash -c '/bin/ps -Eww $$'
#     PID TTY           TIME CMD
#   NNNNN ttys___    0:00.01 /bin/ps -Eww NNNNN A=a b=c STARSHIP_SHELL=zsh ...
#
# It's quite difficult to handle null-separated strings in POSIX sh (read -d
# has been standardized in POSIX.1-2024, but not in shells like dash 0.5.12
# used as /bin/sh in Ubuntu 24.04/26.04 and Debian 12/13), but since this is
# only needed after src/install-required-tools.sh, it shouldn't be a problem.
#
# Note: This script is called only when "=() {" pattern found in output from
# /usr/bin/env. The caller must have a code like:
#
#     set --
#     case "$(/usr/bin/env)" in
#       *'=() {'*)
#         names=$(/bin/sh "${GITHUB_ACTION_PATH:?}/src/list-bash-func.sh")
#         if [ -n "${names}" ]; then
#           ifs="${IFS}"
#           IFS='
#     '
#           # shellcheck disable=SC2086 # names is an array separated with newline
#           set -- ${names}
#           IFS="${ifs}"
#         fi
#         ;;
#     esac
#
# Do not use "$(set)" here because its output format is shell-dependent,
# and it ignores variables containing % on bash 3.2.
# If /bin/sh is dash, environment variable names containing % will not be output by env,
# but is fine because it also means that it will not be exposed to subprocess.
#
# See also comment on shell field in action.yml.

# Use binaries available at standard location to prevent path interception.
# See resolve_path in action.yml for more.
# NB: Sync with it.
resolve_path() {
  for dir in /bin /usr/bin /sbin /usr/sbin; do
    if [ -x "${dir}/$1" ]; then
      printf '%s/%s\n' "${dir}" "$1"
      return
    fi
  done
  if [ -e /etc/NIXOS ] && [ -x /run/current-system/sw/bin/"$1" ]; then
    printf '/run/current-system/sw/bin/%s\n' "$1"
  elif [ -e /etc/NIXOS ] && [ -x /run/wrappers/bin/"$1" ]; then
    printf '/run/wrappers/bin/%s\n' "$1"
  elif [ -e /etc/nix ] && [ -x /root/.nix-profile/bin/"$1" ]; then
    printf '/root/.nix-profile/bin/%s\n' "$1"
  fi
}

bash=$(resolve_path bash)
if [ -z "${bash}" ]; then
  exit 1
fi
# shellcheck disable=SC2016
"${bash}" --noprofile --norc --posix -c '
set -CeEuo pipefail
line="
"
while IFS="=" read -rd "" name value; do
  case "${value}" in
    "() {"*)
      # Sanitize name containing separator. Shell should not support variable names containing
      # newline but just in case.
      if [[ "${name}" == *"${line}"* ]]; then
        exit 1
      fi
      printf "%s\n%s\n" -u "${name}"
      ;;
  esac
done </proc/self/environ
'

#!/bin/false
# SPDX-License-Identifier: Apache-2.0 OR MIT
# shellcheck shell=sh # not executable
set -eu

# Note: This is test-only. action.yml uses different approach.
#
# Detect environment variables that may inject bash functions and output a
# list of -u options to be passed to env command to unset them.
#
# awk is a robust way to do this, but is not always available by default
# (see resolve_path in action.yml).
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

awk=$(resolve_path awk)
if [ -z "${awk}" ]; then
  exit 1
fi
# Unset environment variables that may unexpectedly affect awk behavior.
# Refs:
# - https://pubs.opengroup.org/onlinepubs/9799919799/utilities/awk.html
# - https://www.gnu.org/software/gawk/manual/html_node/Environment-Variables.html
# - https://invisible-island.net/mawk/manpage/mawk.html#h2-ENVIRONMENT
# - https://wiki.alpinelinux.org/wiki/Awk
unset AWKPATH AWKLIBPATH GAWK_PERSIST_FILE
"${awk}" '
END {
  for (name in ENVIRON) {
    if (ENVIRON[name] ~ /^\(\) \{/) {
      # Sanitize name containing separator. Shell should not support variable names containing
      # newline but just in case.
      if (name ~ /\n/) {
        exit 1
      }
      print "-u"
      print name
    }
  }
}
' </dev/null

#!/bin/false
# SPDX-License-Identifier: Apache-2.0 OR MIT
# shellcheck shell=sh # not executable
set -eu

# Test script used by tools/ci/test-bash-func.sh.

script="$1"

/usr/bin/env | grep -Fq '=() {'

set --
case "$(/usr/bin/env)" in
  *'=() {'*)
    names=$("${SH_PATH}" "tools/ci/test-list-bash-func-${script}.sh")
    if [ -n "${names}" ]; then
      ifs="${IFS}"
      IFS='
'
      # shellcheck disable=SC2086 # names is an array separated with newline
      set -- ${names}
      IFS="${ifs}"
    fi
    ;;
esac

! /usr/bin/env "$@" /bin/bash -c '/usr/bin/env | grep -F "=() {"'

#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -CeEuo pipefail
IFS=$'\n\t'
trap -- 'printf >&2 "%s\n" "${0##*/}: trapped SIGINT"; exit 1' SIGINT

set -x

expected=22
ls_files=$(git ls-files)
# BSD wc's -l emits spaces before number.
[[ "$(LC_ALL=C wc -l <<<"${ls_files}" | sed -E 's/^[\t ]*//g')" == "${expected}" ]] || exit 1

log=$(git log --graph --decorate --oneline)
# old git prints 'HEAD, origin/ref, ref' instead of 'HEAD -> ref, origin/ref'.
grep -Eq '\* [0-9a-f]+ \(grafted, (HEAD -> [0-9A-Za-z_./-]+, origin/[0-9A-Za-z_./-]+(, origin/HEAD)?|HEAD, origin/[0-9A-Za-z_./-]+, [0-9A-Za-z_./-]+)\) ' <<<"${log}"

git rev-parse HEAD

git branch -a

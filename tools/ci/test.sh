#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -CeEuo pipefail
IFS=$'\n\t'
trap -- 'printf >&2 "%s\n" "${0##*/}: trapped SIGINT"; exit 1' SIGINT

set -x

bash --version >&2
sleep --version >&2
grep --version >&2
sed --version >&2 || true
awk --version >&2 || true

expected='^ *22$'
count=$(git ls-files | LC_ALL=C wc -l)
# BSD wc's -l emits spaces before number.
[[ "${count}" =~ ${expected} ]] || exit 1

log=$(git log --graph --decorate --oneline)
# old git prints 'HEAD, origin/ref, ref' instead of 'HEAD -> ref, origin/ref'.
grep -Eq '\* [0-9a-f]+ \(grafted, (HEAD -> [0-9A-Za-z_./-]+, origin/[0-9A-Za-z_./-]+(, origin/HEAD)?|HEAD, origin/[0-9A-Za-z_./-]+, [0-9A-Za-z_./-]+)\) ' <<<"${log}"

git rev-parse HEAD

git branch -a

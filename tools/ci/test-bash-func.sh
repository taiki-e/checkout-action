#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
# shellcheck disable=SC2016
set -CeEuo pipefail
IFS=$'\n\t'
trap -- 'printf >&2 "%s\n" "${0##*/}: trapped SIGINT"; exit 1' SIGINT
cd -- "$(dirname -- "$0")"/../..

# Test BASH_FUNC_*%% and related.
#
# See action.yml for more.

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

bash="${1:-$(resolve_path bash)}"
sh="${2:-/bin/sh}"
printf 'bash: %s\n' "${bash}"
printf 'sh: %s\n' "${sh}"

with_func() {
  env \
    "${name}"="${func}" \
    "BASH_FUNC_${name}%%=${func}" \
    "BASH_FUNC_${name}()=${func}" \
    "__BASH_FUNC<${name}>()=${func}" \
    "$@"
}

set -x

# Affected
affected=(
  # https://www.gnu.org/software/bash/manual/html_node/Bourne-Shell-Builtins.html
  cd
  false
  getopts
  hash
  pwd
  test
  '[' # unaffected when --posix used
  true
  umask
  # https://www.gnu.org/software/bash/manual/html_node/Bash-Builtins.html
  alias
  bind
  builtin
  caller
  command
  declare
  echo
  enable
  help
  let
  local
  logout
  mapfile
  printf
  read
  readarray
  type
  typeset
  ulimit
  unalias
  # https://www.gnu.org/software/bash/manual/html_node/Modifying-Shell-Behavior.html
  shopt
  # https://www.gnu.org/software/bash/manual/html_node/Job-Control-Builtins.html
  bg
  fg
  jobs
  kill
  wait
  disown
  suspend
  # https://www.gnu.org/software/bash/manual/html_node/Directory-Stack-Builtins.html
  dirs
  popd
  pushd
  # https://www.gnu.org/software/bash/manual/html_node/Bash-History-Builtins.html
  fc
  history
  # https://www.gnu.org/software/bash/manual/html_node/Programmable-Completion-Builtins.html
  compgen
  complete
  compopt
  # others
  time # altlinux only
)
for name in "${affected[@]}"; do
  func='() { exit; }'
  script="${name} >/dev/null || :; exit 1"
  if [[ "${name}" =~ ^[\[]$ ]] || { [[ "${name}" == 'time' ]] && [[ "${CONTAINER:-}" != 'alt:'* ]]; }; then
    with_func "${bash}" --posix -c "${script}" && exit 1
  else
    with_func "${bash}" --posix -c "${script}"
  fi
  if { [[ "${name}" =~ ^[\[]$ ]] && [[ "${CONTAINER:-}" =~ ^fedora:(2[0-5])$ ]]; } || { [[ "${name}" == 'time' ]] && [[ "${CONTAINER:-}" != 'alt:'* ]]; }; then
    # /bin/bash: error importing function definition for `BASH_FUNC_:'
    with_func "${bash}" -c "set -o posix; ${script}" && exit 1
    with_func "${bash}" -c "${script}" && exit 1
  else
    with_func "${bash}" -c "set -o posix; ${script}"
    with_func "${bash}" -c "${script}"
  fi
  printf '%s affected\n' "${name}"
done

# Affected only on non-POSIX mode:
# - POSIX special builtins listed in https://www.gnu.org/software/bash/manual/html_node/Special-Builtins.html.
#   Refs: 18 in https://www.gnu.org/software/bash/manual/html_node/Bash-POSIX-Mode.html#Bash-POSIX-Mode-1
# - Function names contain /
#   Refs: 19 in https://www.gnu.org/software/bash/manual/html_node/Bash-POSIX-Mode.html#Bash-POSIX-Mode-1
#   However, I can reproduce this only on interactive shell...
#     $ /bin/sh() { echo a; }; /bin/sh -c 'echo b'
#     a
#     $ exit # needed on 3.2, unneeded on 5.3
#     $ set -o posix
#     $ /bin/sh() { echo a; }; /bin/sh -c 'echo b'
#     b
non_posix_affected=(
  # https://www.gnu.org/software/bash/manual/html_node/Bourne-Shell-Builtins.html
  ':'
  '.'
  break
  continue
  eval
  exec
  export
  exit
  readonly
  return
  shift
  times
  trap
  unset
  # https://www.gnu.org/software/bash/manual/html_node/Bash-Builtins.html
  source
  # https://www.gnu.org/software/bash/manual/html_node/Modifying-Shell-Behavior.html
  set
  # others
  /bin/sh
)
for name in "${non_posix_affected[@]}"; do
  func='() { exit; }'
  case "${name}" in
    exit)
      func='() { builtin exit; }'
      script='exit 1'
      ;;
    /bin/sh) script="${name} -c '' || true; exit 1" ;;
    *) script="${name} >/dev/null || true; exit 1" ;;
  esac
  with_func "${bash}" --posix -c "${script}" && exit 1
  with_func "${bash}" -c "builtin set -o posix; ${script}" && exit 1
  if [[ "${name}" =~ ^[:.\[]$ ]] && [[ "${CONTAINER:-}" =~ ^fedora:(2[0-5])$ ]]; then
    # /bin/bash: error importing function definition for `BASH_FUNC_:'
    with_func "${bash}" -c "${script}" && exit 1
  elif [[ "${name}" == '/bin/sh' ]]; then
    # /bin/sh: error importing function definition for `/bin/sh'
    with_func "${bash}" -c "${script}" && exit 1
  else
    with_func "${bash}" -c "${script}"
  fi
  printf '%s affected only on non-POSIX mode\n' "${name}"
done

# Not affected:
# - Reserved words other than time listed in https://www.gnu.org/software/bash/manual/html_node/Reserved-Words.html
# - Separators for Lists of Commands https://www.gnu.org/software/bash/manual/html_node/Lists.html
# TODO: until	while	coproc	select	function {	}	[[	]]	!
func='() { exit; }'
for name in ';' '&'; do
  script="true ${name}; exit 1"
  with_func "${bash}" --posix -c "${script}" && exit 1
  with_func "${bash}" -c "builtin set -o posix; ${script}" && exit 1
  with_func "${bash}" -c "${script}" && exit 1
  printf '%s not affected\n' "${name}"
done
for name in '&&' '||'; do
  script="true ${name} true; exit 1"
  with_func "${bash}" --posix -c "${script}" && exit 1
  with_func "${bash}" -c "builtin set -o posix; ${script}" && exit 1
  with_func "${bash}" -c "${script}" && exit 1
  printf '%s not affected\n' "${name}"
done
printf '%s not affected\n' "${name}"
script='if true; then true; elif true; then true; else true; fi'
"${bash}" --posix -c "${script}"
"${bash}" -c "builtin set -o posix; ${script}"
"${bash}" -c "${script}"
script='if true; then true; elif true; then true; else true; fi || true; exit 1'
for name in 'if' 'then' 'elif' 'else' 'fi'; do
  with_func "${bash}" --posix -c "${script}" && exit 1
  with_func "${bash}" -c "builtin set -o posix; ${script}" && exit 1
  with_func "${bash}" -c "${script}" && exit 1
  printf '%s not affected\n' "${name}"
done
script='case a in a) true ;; esac'
"${bash}" --posix -c "${script}"
"${bash}" -c "builtin set -o posix; ${script}"
"${bash}" -c "${script}"
for name in 'case' 'in' 'esac'; do
  script='case a in a) true ;; esac || true; exit 1'
  with_func "${bash}" --posix -c "${script}" && exit 1
  with_func "${bash}" -c "builtin set -o posix; ${script}" && exit 1
  with_func "${bash}" -c "${script}" && exit 1
  printf '%s not affected\n' "${name}"
done
script='for a in a; do true; done'
"${bash}" --posix -c "${script}"
"${bash}" -c "builtin set -o posix; ${script}"
"${bash}" -c "${script}"
script='for a in a; do true; done || true; exit 1'
for name in 'for' 'in' 'do' 'done'; do
  with_func "${bash}" --posix -c "${script}" && exit 1
  with_func "${bash}" -c "builtin set -o posix; ${script}" && exit 1
  with_func "${bash}" -c "${script}" && exit 1
  printf '%s not affected\n' "${name}"
done

# Test our unset logic used in action.yml
func1='() { exit; }'
func2=$'() { exit\n }'
with_func() {
  env '['="${func1}" 'command'="${func2}" \
    'BASH_FUNC_[%%'="${func1}" 'BASH_FUNC_command%%'="${func2}" \
    'BASH_FUNC_[()'="${func1}" 'BASH_FUNC_command()'="${func2}" \
    '__BASH_FUNC<[>()'="${func1}" '__BASH_FUNC<command>()'="${func2}" \
    SH_PATH="${sh}" \
    "$@"
}
if type -P pwsh >/dev/null; then
  # shellcheck disable=SC2218 # false positive
  with_func pwsh tools/ci/test-bash-func-pwsh.ps1
fi
if type -P powershell >/dev/null; then
  # shellcheck disable=SC2218 # false positive
  with_func powershell tools/ci/test-bash-func-pwsh.ps1
fi

# test alternative approach for non-Windows.
with_func() {
  env 'command'="${func2}" \
    'BASH_FUNC_command%%'="${func2}" \
    'BASH_FUNC_command()'="${func2}" \
    '__BASH_FUNC<command>()'="${func2}" \
    SH_PATH="${sh}" \
    "$@"
}
with_func "${sh}" tools/ci/test-bash-func-sh.sh awk
if [[ -e /proc/self/environ ]]; then
  with_func "${sh}" tools/ci/test-bash-func-sh.sh bash-linux
fi

affected_pat=''
for cmd in "${affected[@]}"; do
  case "${cmd}" in
    # They are unset by env command in shell field.
    builtin | '[' | printf | command | read) ;;
    *) affected_pat+="|${cmd}" ;;
  esac
done
res=$(grep -En '^.*' src/*.sh action.yml | sed -E '/^[^ ]+:( *#| *$)/d' | { grep -E '(^[^ ]+:|[({;&|!]|if|while (IFS=([^ ]*|\$?'\''[^'\'']+'\'') )?) *('"${affected_pat#|}"')([ );]|$)' || true; })
if [[ -n "${res}" ]]; then
  printf 'found vulnerable builtin call; use `builtin` command before builtin:\n%s\n' "${res}"
  exit 1
fi

# test credential helper function
# NB: Sync credential helper function with main.sh.
helper='
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
'
export INPUT_PROTOCOL=https
export INPUT_HOSTNAME=github.com
export INPUT_TOKEN=dummy
set -x
res=$("${sh}" -c "${helper}" <<<'
protocol=https
host=github.com
')
[[ "${res}" == *'password=dummy'* ]] || false
res=$(printf '
protocol=https
host=github.com' | "${sh}" -c "${helper}")
[[ "${res}" == *'password=dummy'* ]] || false
res=$("${sh}" -c "${helper}" <<<'
protocol=http
host=github.com
')
[[ "${res}" != *'password=dummy'* ]] || false
res=$("${sh}" -c "${helper}" <<<'
protocol=https
host=not.github.com
')
[[ "${res}" != *'password=dummy'* ]] || false

#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -CeEuo pipefail
IFS=$'\n\t'
trap -- 'printf >&2 "%s\n" "${0##*/}: trapped SIGINT"; exit 1' SIGINT
cd -- "$(dirname -- "$0")"/..

# USAGE:
#    GITHUB_TOKEN=$(gh auth token) ./tools/tidy.sh
#    TIDY_CONTAINER_ENGINE=podman GITHUB_TOKEN=$(gh auth token) ./tools/tidy.sh
#
# Note: This script requires the following tools:
# - docker or podman
#
# This script is shared by projects under github.com/taiki-e, so there may also
# be checks for files not included in this repository, but they will be skipped
# if the corresponding files do not exist.
# It is not intended for manual editing.

bail() {
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    printf '::error::%s\n' "$*"
  else
    printf >&2 'error: %s\n' "$*"
  fi
  exit 1
}

if [[ $# -gt 0 ]]; then
  cat <<EOF
USAGE:
    $0
EOF
  exit 1
fi

image='ghcr.io/taiki-e/tidy'
if [[ -n "${TIDY_DEV:-}" ]]; then
  image+=':latest'
else
  image+='@sha256:c78ba09aa420feddc57ca76fca38b1d4c998a0ede37f76378f12df15a826cf59'
fi
user="$(id -u):$(id -g)"
workdir=$(pwd)
tmp=$(mktemp -d)
trap -- 'rm -rf -- "${tmp:?}"' EXIT
mkdir -p -- "${tmp}"/{pwsh-cache,pwsh-local,zizmor-cache,dummy-dir,tmp}
printf '' >"${tmp}"/dummy
code=0
color=''
if [[ -t 1 ]] || [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  color=1
fi
# Refs:
# - https://docs.docker.com/reference/cli/docker/container/run/
# - https://docs.podman.io/en/latest/markdown/podman-run.1.html
# - https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html
common_args=(
  run --rm --init --user "${user}"
  --cap-drop=all
  --security-opt=no-new-privileges
  --env GITHUB_ACTIONS
  --env CI
  --env CARGO_TERM_COLOR
  --env REMOVE_UNUSED_WORDS
  --env TIDY_COLOR_ALWAYS="${color}"
  --env TIDY_CALLER="$0"
  --env TIDY_EXPECTED_MARKDOWN_FILE_COUNT
  --env TIDY_EXPECTED_RUST_FILE_COUNT
  --env TIDY_EXPECTED_CLANG_FORMAT_FILE_COUNT
  --env TIDY_EXPECTED_PRETTIER_FILE_COUNT
  --env TIDY_EXPECTED_TOML_FILE_COUNT
  --env TIDY_EXPECTED_SHELL_FILE_COUNT
  --env TIDY_EXPECTED_DOCKER_FILE_COUNT
  # podman workaround: Prevents the pwsh module/cache from being placed in the current directory.
  --env HOME=/
  # podman workaround: https://github.com/containers/podman/discussions/27782
  --env GIT_CONFIG_COUNT=1
  --env GIT_CONFIG_KEY_0=safe.directory
  --env GIT_CONFIG_VALUE_0="${workdir}"
)
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN* | Windows_NT) ;;
  *) common_args+=(--read-only) ;;
esac
if [[ -n "${TIDY_CONTAINER_ENGINE:-}" ]]; then
  docker="${TIDY_CONTAINER_ENGINE}"
elif type -P docker >/dev/null; then
  docker='docker'
elif type -P podman >/dev/null; then
  docker='podman'
else
  bail 'this script requires docker or podman'
fi
# Map ignored files (e.g., .env) to dummy files.
while IFS= read -r path; do
  if [[ -d "${path}" ]]; then
    common_args+=(
      --mount "type=bind,source=${tmp}/dummy-dir,target=${workdir}/${path},readonly"
    )
  else
    common_args+=(
      --mount "type=bind,source=${tmp}/dummy,target=${workdir}/${path},readonly"
    )
  fi
done < <(git status --porcelain --ignored | grep -E '^!!' | cut -d' ' -f2)

run() {
  "${docker}" "${common_args[@]}" "$@"
  code2="$?"
  if [[ ${code} -eq 0 ]] && [[ ${code2} -ne 0 ]]; then
    code="${code2}"
  fi
}

set +e
run \
  --mount "type=bind,source=${workdir},target=${workdir}" --workdir "${workdir}" \
  --mount "type=bind,source=${tmp}/tmp,target=/tmp/tidy" \
  --mount "type=bind,source=${tmp}/pwsh-cache,target=/.cache/powershell" \
  --mount "type=bind,source=${tmp}/pwsh-local,target=/.local/share/powershell" \
  --network=none \
  "${image}" \
  /checks/offline.sh
# Some good audits requires access to GitHub API.
run \
  --mount "type=bind,source=${workdir},target=${workdir},readonly" --workdir "${workdir}" \
  --mount "type=bind,source=${tmp}/zizmor-cache,target=/.cache/zizmor" \
  --env GH_TOKEN --env GITHUB_TOKEN --env ZIZMOR_GITHUB_TOKEN \
  "${image}" \
  /checks/zizmor.sh
# We use remote dictionary.
run \
  --mount "type=bind,source=${workdir},target=${workdir},readonly" --workdir "${workdir}" \
  --mount "type=bind,source=${workdir}/.github/.cspell/project-dictionary.txt,target=${workdir}/.github/.cspell/project-dictionary.txt" \
  --mount "type=bind,source=${workdir}/.github/.cspell/rust-dependencies.txt,target=${workdir}/.github/.cspell/rust-dependencies.txt" \
  --mount "type=bind,source=${tmp}/tmp,target=/tmp/tidy" \
  "${image}" \
  /checks/cspell.sh

exit "${code}"

#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -eEuo pipefail
IFS=$'\n\t'

g() {
    local cmd="$1"
    shift
    IFS=' '
    echo "::group::${cmd} $*"
    IFS=$'\n\t'
    "${cmd}" "$@"
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
warn() {
    echo "::warning::$*"
}
_sudo() {
    if type -P sudo &>/dev/null; then
        sudo "$@"
    else
        "$@"
    fi
}
apt_update() {
    retry _sudo apt-get -o Acquire::Retries=10 -qq update
    apt_updated=1
}
apt_install() {
    if [[ -z "${apt_updated:-}" ]]; then
        apt_update
    fi
    retry _sudo apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 install -y --no-install-recommends "$@"
}
dnf_install() {
    retry _sudo "${dnf}" install -y "$@"
}
apk_install() {
    if type -P sudo &>/dev/null; then
        sudo apk --no-cache add "$@"
    elif type -P doas &>/dev/null; then
        doas apk --no-cache add "$@"
    else
        apk --no-cache add "$@"
    fi
}
zypper_install() {
    retry _sudo zypper install -y "$@"
}
pacman_install() {
    retry _sudo pacman -Sy --noconfirm "$@"
}
sys_install() {
    case "${base_distro}" in
        debian) apt_install "$@" ;;
        fedora) dnf_install "$@" ;;
        alpine) apk_install "$@" ;;
        suse) zypper_install "$@" ;;
        arch) pacman_install "$@" ;;
    esac
}

wd=$(pwd)

base_distro=""
case "$(uname -s)" in
    Linux)
        host_os=linux
        if grep -q '^ID_LIKE=' /etc/os-release; then
            base_distro=$(grep '^ID_LIKE=' /etc/os-release | sed 's/^ID_LIKE=//')
            case "${base_distro}" in
                *debian*) base_distro=debian ;;
                *fedora*) base_distro=fedora ;;
                *alpine*) base_distro=alpine ;;
                *suse*) base_distro=suse ;;
                *arch*) base_distro=arch ;;
            esac
        else
            base_distro=$(grep '^ID=' /etc/os-release | sed 's/^ID=//')
        fi
        case "${base_distro}" in
            fedora)
                dnf=dnf
                if ! type -P dnf &>/dev/null; then
                    if type -P microdnf &>/dev/null; then
                        # fedora-based distributions have "minimal" images that
                        # use microdnf instead of dnf.
                        dnf=microdnf
                    else
                        # If neither dnf nor microdnf is available, it is
                        # probably an RHEL7-based distribution that does not
                        # have dnf installed by default.
                        dnf=yum
                    fi
                fi
                ;;
        esac
        ;;
    Darwin) host_os=macos ;;
    MINGW* | MSYS* | CYGWIN* | Windows_NT) host_os=windows ;;
    *) bail "unrecognized OS type '$(uname -s)'" ;;
esac

if ! type -P git &>/dev/null; then
    case "${host_os}" in
        linux*)
            case "${base_distro}" in
                debian | fedora | alpine | suse | arch)
                    echo "::group::Install packages required for checkout (git)"
                    case "${base_distro}" in
                        debian) sys_install ca-certificates git ;;
                        *) sys_install git ;;
                    esac
                    echo "::endgroup::"
                    ;;
                *) warn "checkout-action requires git on non-Debian/Fedora/Alpine/SUSE/Arch-based Linux" ;;
            esac
            ;;
        macos) warn "checkout-action requires git on macOS" ;;
        windows) warn "checkout-action requires git on Windows" ;;
        *) bail "unsupported host OS '${host_os}'" ;;
    esac
fi

g git version

g git config --global --add safe.directory "${wd}"

g git init

g git remote add origin "${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}"

g git config --local gc.auto 0

if [[ "${GITHUB_REF}" == "refs/heads/"* ]]; then
    branch="${GITHUB_REF#refs/heads/}"
    remote_ref="refs/remotes/origin/${branch}"
    g retry git fetch --no-tags --prune --no-recurse-submodules --depth=1 origin "+${GITHUB_SHA}:${remote_ref}"
    g retry git checkout --force -B "${branch}" "${remote_ref}"
else
    g retry git fetch --no-tags --prune --no-recurse-submodules --depth=1 origin "+${GITHUB_SHA}:${GITHUB_REF}"
    g retry git checkout --force "${GITHUB_REF}"
fi

g git config --global --add safe.directory "${wd}"

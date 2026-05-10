#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -eu

# Install missing required tools from system package manager on Linux.
#
# See "Compatibility" section in README.md for list of required tools.
#
# This is used for containers and self-hosted runners.
# On GitHub-hosted runners, this is normally not used since required tools are already installed.

bail() {
  printf '::error::checkout-action: %s\n' "$*"
  exit 1
}
warn() {
  printf '::warning::checkout-action: %s\n' "$*"
}

# ------------------------------------------------------------------------------
# Preparation

if [ "${RUNNER_OS}" != 'Linux' ]; then
  bail 'internal error: unreachable'
fi
bash=$(command -v bash 2>/dev/null || true)
git=$(command -v git 2>/dev/null || true)
if [ -n "${bash}" ] && [ -n "${git}" ]; then
  bail 'internal error: unreachable'
fi

# Detect distribution.
# Note that we don't do package manager command based detection here because there might be another
# command with the same name.
base_distro=''
if [ -e /etc/debian_version ]; then
  # debian 6 has no /etc/os-release, but has /etc/debian_version
  # debian 7+ has /etc/debian_version and ID debian
  # ubuntu (at least 12.04+) and devuan have /etc/debian_version and ID_LIKE debian
  base_distro=debian
elif [ -e /etc/redhat-release ] || [ -e /etc/photon-release ] || [ -e /etc/openEuler-release ]; then
  # rhel/centos 6 has no /etc/os-release, but has /etc/redhat-release
  # rhel/centos 7+ and fedora/almalinux/rockylinux/oraclelinux/mageia have /etc/redhat-release and ID_LIKE fedora
  # amazonlinux has no /etc/redhat-release, but has ID_LIKE fedora
  # openmandriva has no ID_LIKE fedora, but has /etc/redhat-release and ID openmandriva
  # altlinux (at least p8+) has no ID_LIKE fedora, but has /etc/redhat-release and /etc/altlinux-release and ID altlinux
  # photon (at least 1.0+) has no /etc/redhat-release and ID_LIKE fedora, but has /etc/photon-release and ID photon
  # wrlinux lts 19-22 has no /etc/redhat-release and ID_LIKE fedora, but has ID wrlinux-graphics
  # wrlinux lts 23 full has no /etc/redhat-release and ID_LIKE fedora, but has ID wrdistro
  # wrlinux lts 23 minimal has no /etc/redhat-release and /etc/os-release
  # openeuler has /etc/openEuler-release and ID openEuler
  base_distro=fedora
elif [ -e /etc/alpine-release ]; then
  # alpine (at least 3.1+) has /etc/alpine-release and ID alpine
  # wolfi has ID wolfi
  base_distro=alpine
elif [ -e /etc/openwrt_release ]; then
  # openwrt (at least 18.06.9+) has /etc/openwrt_release and ID openwrt and ID_LIKE openwrt
  base_distro=openwrt
elif [ -e /etc/arch-release ] || [ -e /etc/artix-release ]; then
  # archlinux has /etc/arch-release and ID arch
  # cachyos/manjarolinux have /etc/arch-release and ID_LIKE arch
  # artixlinux has no /etc/arch-release and ID arch, but /etc/artix-release and ID artix
  base_distro=arch
elif [ -e /etc/SuSE-release ]; then
  # opensuse 11 has no /etc/os-release, but has /etc/SuSE-release
  # opensuse 12-43 has /etc/os-release and /etc/SuSE-release
  # opensuse 15 has no /etc/SuSE-release, but has /etc/os-release
  base_distro=suse
elif [ -e /etc/gentoo-release ]; then
  # gentoo has /etc/gentoo-release and ID='gentoo'
  base_distro=gentoo
elif [ -e /etc/NIXOS ]; then
  # nixos vm has /etc/NIXOS but nixos/nix image doesn't
  # nixos vm and nixos/nix image has /etc/nix
  base_distro=nixos
  nix_env=/run/current-system/sw/bin/nix-env
elif [ -e /etc/os-release ]; then
  id=''
  id_like=''
  while IFS= read -r line; do
    case "${line}" in
      ID=*) id="${line#ID=}" ;;
      ID_LIKE=*) id_like="${line#ID_LIKE=}" ;;
    esac
  done </etc/os-release
  id="${id#[\"\']}"
  id_like="${id_like#[\"\']}"
  case " ${id%[\"\']} ${id_like%[\"\']} " in
    # Ubuntu and some Ubuntu-based distro have ID_LIKE debian, but some Ubuntu-based distro have only ID_LIKE ubuntu: https://github.com/search?q=repo%3Achef%2Fos_release+%2FID_LIKE%3D.*ubuntu%2F&type=code
    *\ debian\ * | *\ ubuntu\ *) base_distro=debian ;;
    # photon/wrlinux/openeuler is not Fedora-based, but uses tdnf/dnf/dnf.
    *\ fedora\ * | *\ openmandriva\ * | *\ altlinux\ * | *\ photon\ * | *\ wrlinux* | *\ wrdistro* | *\ openEuler\ *) base_distro=fedora ;;
    # Old SLE don't have ID/ID_LIKE suse https://github.com/search?q=repo%3Achef%2Fos_release+%2FID%3D.*sle%28s%7Cd%29%2F&type=code
    *\ suse\ * | *\ sles* | *\ sled*) base_distro=suse ;;
    *\ arch\ * | *\ artix\ *) base_distro=arch ;;
    # wolfi is not Alpine-based, but uses apk.
    *\ alpine\ * | *\ wolfi\ *) base_distro=alpine ;;
    *\ openwrt\ *) base_distro=openwrt ;;
    *\ void\ *) base_distro=void ;;
    *\ gentoo\ *) base_distro=gentoo ;;
  esac
fi
if [ -z "${base_distro}" ] && [ -e /etc/nix ] && [ -x /root/.nix-profile/bin/nix-env ]; then
  # nixos/nix image does not contain any files that identify it as NixOS,
  # but it uses the same package manager. However, the Nix package manager
  # can also be installed on other distributions. Therefore, check for it
  # only after all other checks have failed.
  base_distro=nixos
  nix_env=/root/.nix-profile/bin/nix-env
fi

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
sleep=$(resolve_path sleep)
if [ -n "${sleep}" ]; then
  sleep() { "${sleep}" "$1"; }
else
  # Fallback to non-sleep when sleep is unavailable at standard location.
  # Note that POSIX read has no -t option.
  sleep() { :; }
fi
retry() {
  for i in 1 2 3 4 5 6 7 8 9 10; do
    if "$@"; then
      return 0
    else
      sleep "${i}"
    fi
  done
  "$@"
}
sudo=$(resolve_path sudo)
if [ -z "${sudo}" ]; then
  sudo=$(resolve_path doas)
fi
if [ -n "${sudo}" ]; then
  sudo() { "${sudo}" "$@"; }
else
  sudo() { "$@"; }
fi
case "${base_distro}" in
  debian)
    export DEBIAN_FRONTEND=noninteractive
    apt_updated=''
    sys_install() {
      if [ -z "${apt_updated:-}" ]; then
        retry sudo /usr/bin/apt-get -o Acquire::Retries=10 -qq update
        apt_updated=1
      fi
      retry sudo /usr/bin/apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 install -y --no-install-recommends "$@"
    }
    ;;
  fedora)
    if [ -e /etc/altlinux-release ]; then
      # altlinux uses rpm-based apt
      apt_updated=''
      sys_install() {
        if [ -z "${apt_updated:-}" ]; then
          retry sudo /usr/bin/apt-get -qq update
          apt_updated=1
        fi
        retry sudo /usr/bin/apt-get install -y "$@"
      }
    else
      dnf=/usr/bin/dnf
      if [ ! -x /usr/bin/dnf ]; then
        if [ -x /usr/bin/microdnf ]; then
          # fedora-based distributions have "minimal" images that
          # use microdnf instead of dnf.
          dnf=/usr/bin/microdnf
        elif [ -x /usr/bin/tdnf ]; then
          # Photon has tdnf and yum.
          dnf=/usr/bin/tdnf
        else
          # If neither dnf nor microdnf is available, it is
          # probably an RHEL7-based distribution that does not
          # have dnf installed by default.
          dnf=/usr/bin/yum
        fi
      fi
      sys_install() {
        retry sudo "${dnf}" install -y "$@"
      }
    fi
    ;;
  suse)
    sys_install() {
      retry sudo /usr/bin/zypper install -y "$@"
    }
    ;;
  arch)
    sys_install() {
      retry sudo /usr/bin/pacman -Sy --noconfirm "$@"
    }
    ;;
  void)
    xbps_updated=''
    sys_install() {
      if [ -z "${xbps_updated:-}" ]; then
        retry sudo /usr/bin/xbps-install -Syu xbps
        xbps_updated=1
      fi
      retry sudo /usr/bin/xbps-install -Sy "$@"
    }
    ;;
  alpine)
    sys_install() {
      retry sudo /sbin/apk --no-cache add "$@"
    }
    ;;
  openwrt)
    # https://forum.openwrt.org/t/the-future-is-now-opkg-vs-apk/201164
    if [ -x /usr/bin/apk ]; then
      sys_install() {
        retry sudo /usr/bin/apk --no-cache add "$@"
      }
    else
      opkg_updated=''
      sys_install() {
        if [ -z "${opkg_updated:-}" ]; then
          sudo /bin/mkdir -p -- /var/lock
          retry sudo /bin/opkg update
          opkg_updated=1
        fi
        retry sudo /bin/opkg install "$@"
      }
    fi
    ;;
  gentoo)
    emerge_updated=''
    sys_install() {
      if [ -z "${emerge_updated:-}" ]; then
        retry sudo /usr/bin/emerge-webrsync
        emerge_updated=1
      fi
      sudo /usr/bin/emerge "$@"
    }
    ;;
  nixos)
    sys_install() {
      "${nix_env}" -i "$@"
    }
    ;;
esac

# ------------------------------------------------------------------------------
# Install

set --
if [ -z "${bash}" ]; then
  set -- "$@" bash
fi
if [ -z "${git}" ]; then
  case "${base_distro}" in
    debian) set -- "$@" ca-certificates git ;;
    openwrt) set -- "$@" git git-http ;;
    gentoo) set -- "$@" dev-vcs/git ;;
    *) set -- "$@" git ;;
  esac
fi
ifs="${IFS}"
IFS=' '
list="$*"
IFS="${ifs}"
if [ -z "${base_distro}" ]; then
  bail "tools required for this action is unavailable: ${list}"
fi
printf '::group::Install tools required for checkout-action from system package manager: %s\n' "${list}"
sys_install "$@"
printf '::endgroup::\n'

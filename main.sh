#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0 OR MIT
set -CeEuo pipefail
IFS=$'\n\t'

g() {
  IFS=' '
  local cmd="$*"
  IFS=$'\n\t'
  printf '::group::%s\n' "${cmd#retry }"
  "$@" 2>&1
  printf '::endgroup::\n'
}
g_for_hw_info() {
  IFS=' '
  local cmd="$*"
  IFS=$'\n\t'
  printf '::group::Show hardware information (%s)\n' "${cmd#retry }"
  "$@" 2>&1 || true
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

token="${INPUT_TOKEN}"
# This prevents tokens from being exposed to subprocesses via environment variables.
# Note that this does not prevent token leaks via reading `/proc/*/environ` on Linux or
# via `ps -Eww` on macOS. It only reduces the risk of leaks.
unset INPUT_TOKEN
# This prevents tokens from being exposed to log when tracing is activated.
unset GIT_TRACE_REDACT GIT_TRACE2_REDACT GIT_CURL_VERBOSE GIT_TRACE_CURL

repository_url="${INPUT_SERVER_URL}/${INPUT_REPOSITORY}"

# Since we currently do not support checking out other repositories, this should always be enforced.
# https://github.blog/security/application-security/improving-git-protocol-security-github/
export GIT_ALLOW_PROTOCOL=https:ssh

if [[ -n "${HAS_TOKEN}" ]]; then
  protocol="${INPUT_SERVER_URL%%://*}"
  hostname="${INPUT_SERVER_URL#*://}"
  hostname="${hostname%%/*}"
  # Sanitize inputs and runner-provided environment variables for credential helper which uses line-separated format.
  # Also sanitize encoded newline (%0a) and carriage return (\r, %0d) for old git affected by CVE-2020-5260/CVE-2024-52006.
  for c in $'\n' '%0a' '%0A' $'\r' '%0d' '%0D'; do
    if [[ "${protocol}" == *"${c}"* ]] || [[ "${hostname}" == *"${c}"* ]] || [[ "${token}" == *"${c}"* ]]; then
      bail "github.server_url and 'token' input option must not contain newline"
    fi
  done
fi

sleep=$(resolve_path sleep)
if [[ -z "${sleep}" ]]; then
  sleep=$(type -P sleep)
  if [[ -n "${HAS_TOKEN}" ]]; then
    bail "sleep is unavailable at standard location; found ${sleep}"
  else
    warn "sleep is unavailable at standard location; using ${sleep}"
  fi
fi
is_fake_home=''
case "${RUNNER_OS}" in
  Linux)
    grep=$(resolve_path grep)
    if [[ -z "${grep}" ]]; then
      grep=$(type -P grep)
      if [[ -n "${HAS_TOKEN}" ]]; then
        bail "grep is unavailable at standard location; found ${grep}"
      else
        warn "grep is unavailable at standard location; using ${grep}"
      fi
    fi
    lscpu=$(resolve_path lscpu)
    if [[ -n "${lscpu}" ]]; then
      # Output CPU information to make it easier to debug the runner issues.
      g_for_hw_info "${lscpu}"
    fi
    if [[ -e /etc/redhat-release ]]; then
      # /etc/os-release is available on RHEL/CentOS 7+
      base_distro=fedora
    elif [[ -e /etc/debian_version ]]; then
      # /etc/os-release is available on Debian 7+
      base_distro=debian
    elif [[ -e /etc/os-release ]]; then
      base_distro=$("${grep}" -E '^ID_LIKE=' /etc/os-release || true)
      case "${base_distro}" in
        *debian*) base_distro=debian ;;
        *fedora*) base_distro=fedora ;;
        *suse*) base_distro=suse ;;
        *arch*) base_distro=arch ;;
        *alpine*) base_distro=alpine ;;
        *openwrt*) base_distro=openwrt ;;
        *)
          base_distro=$("${grep}" -E '^ID=' /etc/os-release)
          base_distro="${base_distro#*=}"
          base_distro="${base_distro//\"/}"
          case "${base_distro}" in
            debian | fedora | suse | arch | alpine | openwrt) ;;
            *) base_distro='' ;;
          esac
          ;;
      esac
    else
      base_distro=''
    fi
    case "${base_distro}" in
      debian)
        apt_updated=''
        apt_update() {
          retry _sudo /usr/bin/apt-get -o Acquire::Retries=10 -qq update
          apt_updated=1
        }
        sys_install() {
          if [[ -z "${apt_updated:-}" ]]; then
            apt_update
          fi
          retry _sudo /usr/bin/apt-get -o Acquire::Retries=10 -o Dpkg::Use-Pty=0 install -y --no-install-recommends "$@"
        }
        ;;
      fedora)
        dnf=/usr/bin/dnf
        if ! type -P /usr/bin/dnf >/dev/null; then
          if type -P /usr/bin/microdnf >/dev/null; then
            # fedora-based distributions have "minimal" images that
            # use microdnf instead of dnf.
            dnf=/usr/bin/microdnf
          else
            # If neither dnf nor microdnf is available, it is
            # probably an RHEL7-based distribution that does not
            # have dnf installed by default.
            dnf=/usr/bin/yum
          fi
        fi
        sys_install() {
          retry _sudo "${dnf}" install -y "$@"
        }
        ;;
      suse)
        sys_install() {
          retry _sudo /usr/bin/zypper install -y "$@"
        }
        ;;
      arch)
        sys_install() {
          retry _sudo /usr/bin/pacman -Sy --noconfirm "$@"
        }
        ;;
      alpine)
        # NB: sync with action.yml
        sys_install() {
          if type -P /usr/bin/sudo >/dev/null; then
            retry /usr/bin/sudo /sbin/apk --no-cache add "$@"
          elif type -P /usr/bin/doas >/dev/null; then
            retry /usr/bin/doas /sbin/apk --no-cache add "$@"
          else
            retry /sbin/apk --no-cache add "$@"
          fi
        }
        ;;
      openwrt)
        # NB: sync with action.yml
        # https://forum.openwrt.org/t/the-future-is-now-opkg-vs-apk/201164
        if [[ -x /usr/bin/apk ]]; then
          sys_install() {
            retry _sudo /usr/bin/apk --no-cache add "$@"
          }
        else
          opkg_updated=''
          opkg_update() {
            _sudo /bin/mkdir -p -- /var/lock
            retry _sudo /bin/opkg update
            opkg_updated=1
          }
          sys_install() {
            if [[ -z "${opkg_updated:-}" ]]; then
              opkg_update
            fi
            retry _sudo /bin/opkg install "$@"
          }
        fi
        ;;
    esac
    if ! type -P git >/dev/null; then
      if [[ -n "${base_distro}" ]]; then
        sudo=$(resolve_path sudo)
        if [[ -z "${sudo}" ]]; then
          sudo=$(type -P sudo || true)
          if [[ -n "${sudo}" ]]; then
            bail "sudo is unavailable at standard location; found ${sudo}"
          fi
        fi
        _sudo() {
          if [[ -n "${sudo}" ]]; then
            "${sudo}" "$@"
          else
            "$@"
          fi
        }
        printf '::group::Install packages required for checkout (git)\n'
        case "${base_distro}" in
          debian) sys_install ca-certificates git ;;
          openwrt) sys_install git git-http ;;
          *) sys_install git ;;
        esac
        printf '::endgroup::\n'
      else
        warn "this action requires git on non-Debian/Fedora/SUSE/Arch/Alpine/OpenWrt-based Linux"
      fi
    fi
    git=$(resolve_path git)
    if [[ -z "${git}" ]]; then
      git=$(type -P git)
      if [[ -n "${HAS_TOKEN}" ]]; then
        bail "git is unavailable at standard location; found ${git}"
      else
        warn "git is unavailable at standard location; using ${git}"
      fi
    fi
    ;;
  macOS)
    # Output CPU information to make it easier to debug the runner issues.
    g_for_hw_info /usr/sbin/sysctl hw.optional machdep.cpu
    if ! type -P git >/dev/null; then
      warn "this action requires git on macOS"
    fi
    git=$(resolve_path git)
    if [[ -z "${git}" ]]; then
      git=$(type -P git)
      if [[ -n "${HAS_TOKEN}" ]]; then
        bail "git is unavailable at standard location; found ${git}"
      else
        warn "git is unavailable at standard location; using ${git}"
      fi
    fi
    ;;
  Windows)
    # Output CPU information to make it easier to debug the runner issues.
    g_for_hw_info 'C:\Windows\system32\systeminfo.exe'
    if ! type -P git >/dev/null; then
      warn "this action requires git on Windows"
    fi
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
        else
          warn "git is unavailable at standard location; using ${git}"
        fi
        ;;
    esac
    home="${HOME}"
    if [[ "${home}" == "/home/"* ]]; then
      is_fake_home=1
      if [[ -d "${home/\/home\///c/Users/}" ]]; then
        # MSYS2 https://github.com/taiki-e/install-action/pull/518#issuecomment-2160736760
        home="${home/\/home\///c/Users/}"
      elif [[ -d "${home/\/home\///cygdrive/c/Users/}" ]]; then
        # Cygwin https://github.com/taiki-e/install-action/issues/224#issuecomment-1720196288
        home="${home/\/home\///cygdrive/c/Users/}"
      else
        warn "\$HOME starting /home/ (${home}) on Windows bash is usually fake path, this may cause checkout issue"
      fi
    fi
    # See action.yml.
    printf '' >|"${home}/.checkout-action-init"
    ;;
  *) bail "unrecognized OS '${RUNNER_OS}'" ;;
esac

wd=$(pwd)

g "${git}" version
git_version=$("${git}" version)
# --local and --no-recurse-submodules require git 1.8.
if [[ "${git_version}" == 'git version 1.'* ]] && [[ "${git_version}" != 'git version 1.8.'* ]] && [[ "${git_version}" != 'git version 1.9.'* ]]; then
  warn "this action requires git 1.8+"
fi
if [[ -n "${HAS_TOKEN}" ]]; then
  # Setting empty value via -c requires git 2.0.
  # We use local config to mitigate the impact of their absence, but using git 2.0+ is best.
  if [[ "${git_version}" == 'git version 1.'* ]]; then
    warn "when using 'token' input option, it is recommended using git 2.0+ for security reasons"
    has_c_flag_with_empty_val=''
  else
    has_c_flag_with_empty_val=1
  fi
fi

# Disable template to avoid needless copy of sample hooks and reduce risk of hook injections in
# compromised environments. This option takes precedence, so there is no need to modify environment
# variables or configs: https://git-scm.com/docs/git-init#_template_directory
g "${git}" init --template=''

# error: could not lock config file C:/tools/cygwin/home/runneradmin/.gitconfig: No such file or directory
# error: could not lock config file C:/msys64/home/runneradmin/.gitconfig: No such file or directory
if [[ -n "${is_fake_home}" ]]; then
  g "${git}" config --global --add safe.directory "${wd}" || true
else
  g "${git}" config --global --add safe.directory "${wd}"
fi

g "${git}" remote add origin "${repository_url}"

g "${git}" config --local gc.auto 0

# Enforce sslVerify to ensure security of https.
unset GIT_SSL_NO_VERIFY
fetch_args=(
  -c "http.${repository_url}.sslVerify=true"
  -c "https.${repository_url}.sslVerify=true"
)
checkout_args=()
fetch_args+=(fetch --no-tags --prune --no-recurse-submodules --depth=1 origin)
checkout_args+=(checkout --force)
if [[ "${INPUT_REF}" == "refs/heads/"* ]]; then
  branch="${INPUT_REF#refs/heads/}"
  remote_ref="refs/remotes/origin/${branch}"
  fetch_args+=("+${INPUT_SHA}:${remote_ref}")
  checkout_args+=(-B "${branch}" "${remote_ref}")
else
  fetch_args+=("+${INPUT_SHA}:${INPUT_REF}")
  checkout_args+=("${INPUT_REF}")
fi

IFS=' '
cmd="${git} ${fetch_args[*]}"
IFS=$'\n\t'
printf '::group::%s\n' "${cmd}"
if [[ -n "${HAS_TOKEN}" ]]; then
  # The first credential.helper= is needed to ignore existing credential helpers.
  if [[ -n "${has_c_flag_with_empty_val}" ]]; then
    first_credential_helper=(-c credential.helper=)
  else
    "${git}" config --local credential.helper ''
    first_credential_helper=()
  fi
  # shellcheck disable=SC2016
  INPUT_PROTOCOL="${protocol}" \
    INPUT_HOSTNAME="${hostname}" \
    INPUT_TOKEN="${token}" \
    retry "${git}" \
    ${first_credential_helper[@]+"${first_credential_helper[@]}"} \
    -c 'credential.helper=!f() {
protocol=""
host=""
while IFS= read -r line; do
  case "${line}" in
    protocol=*) protocol="${line#protocol=}" ;;
    host=*) host="${line#host=}" ;;
  esac
  [ -n "${line}" ] || break
done
if [ "${protocol}" = "${INPUT_PROTOCOL}" ] && [ "${host}" = "${INPUT_HOSTNAME}" ]; then
  printf "protocol=%s\nhost=%s\nusername=x-access-token\npassword=%s\n" "${INPUT_PROTOCOL}" "${INPUT_HOSTNAME}" "${INPUT_TOKEN}"
fi
}; f' \
    "${fetch_args[@]}" 2>&1
else
  retry "${git}" "${fetch_args[@]}" 2>&1
fi
printf '::endgroup::\n'

if [[ -n "${HAS_TOKEN}" ]]; then
  if [[ -z "${has_c_flag_with_empty_val}" ]]; then
    "${git}" config --unset --local credential.helper
  fi
fi

g retry "${git}" "${checkout_args[@]}"

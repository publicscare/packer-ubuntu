#!/usr/bin/env bash
# Install everything listed in packages.txt.
#   plain names -> apt (Ubuntu archive)
#   gh          -> apt, from GitHub's own repo (cli.github.com)
#   powershell  -> official release tarball (arm64 or x64), SHA-256 verified
#   yq          -> mikefarah/yq v4 release binary, SHA-256 verified
#                  (not Ubuntu's apt "yq", which is a Python jq wrapper)
set -euo pipefail
: "${STAGE_DIR:?}"

LIST="${STAGE_DIR}/packages.txt"
[[ -f "${LIST}" ]] || { echo "ERROR: ${LIST} not found" >&2; exit 1; }

# Strip comments and whitespace; read into an array (no pipes into early-exit tools).
mapfile -t WANTED < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' "${LIST}" | awk 'NF')
echo "==> [10-packages] Requested: ${WANTED[*]}"

APT_PKGS=()
WANT_GH=false
WANT_PWSH=false
WANT_YQ=false
for p in "${WANTED[@]}"; do
  case "${p}" in
    gh) WANT_GH=true ;;
    powershell|pwsh) WANT_PWSH=true ;;
    yq) WANT_YQ=true ;;
    *) APT_PKGS+=("${p}") ;;
  esac
done

if [[ "${WANT_GH}" == "true" ]]; then
  echo "==> [10-packages] Adding GitHub CLI apt repo"
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    https://cli.github.com/packages/githubcli-archive-keyring.gpg
  chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
  APT_PKGS+=("gh")
fi

apt-get update -y
if [[ ${#APT_PKGS[@]} -gt 0 ]]; then
  echo "==> [10-packages] apt install: ${APT_PKGS[*]}"
  apt-get install -y "${APT_PKGS[@]}"
fi

if [[ "${WANT_PWSH}" == "true" ]]; then
  : "${POWERSHELL_VERSION:?}"
  ARCH="$(dpkg --print-architecture)"
  case "${ARCH}" in
    arm64) PWSH_ARCH=arm64; PWSH_SHA="${POWERSHELL_SHA256_ARM64:?}" ;;
    amd64) PWSH_ARCH=x64;   PWSH_SHA="${POWERSHELL_SHA256_AMD64:?}" ;;
    *) echo "ERROR: no PowerShell tarball mapping for ${ARCH}" >&2; exit 1 ;;
  esac

  echo "==> [10-packages] PowerShell ${POWERSHELL_VERSION} runtime dependencies"
  apt-get install -y --no-install-recommends libicu74 libssl3t64 zlib1g less
  apt-get install -y --no-install-recommends liblttng-ust1t64 || echo "WARN: liblttng-ust1t64 not available; PowerShell runs without it"

  echo "==> [10-packages] PowerShell ${POWERSHELL_VERSION} (${PWSH_ARCH} tarball)"
  WORK="$(mktemp -d)"
  TGZ="powershell-${POWERSHELL_VERSION}-linux-${PWSH_ARCH}.tar.gz"
  curl -fsSL -o "${WORK}/${TGZ}" \
    "https://github.com/PowerShell/PowerShell/releases/download/v${POWERSHELL_VERSION}/${TGZ}"
  echo "${PWSH_SHA,,}  ${WORK}/${TGZ}" | sha256sum -c -

  DEST="/opt/microsoft/powershell/${POWERSHELL_VERSION%%.*}"
  rm -rf "${DEST}"
  install -d "${DEST}"
  tar -xzf "${WORK}/${TGZ}" -C "${DEST}"
  chmod +x "${DEST}/pwsh"
  ln -sf "${DEST}/pwsh" /usr/bin/pwsh
  grep -qx /usr/bin/pwsh /etc/shells || echo /usr/bin/pwsh >> /etc/shells
  rm -rf "${WORK}"
fi

if [[ "${WANT_YQ}" == "true" ]]; then
  : "${YQ_VERSION:?}"
  ARCH="$(dpkg --print-architecture)"
  case "${ARCH}" in
    arm64) YQ_SHA="${YQ_SHA256_ARM64:?}" ;;
    amd64) YQ_SHA="${YQ_SHA256_AMD64:?}" ;;
    *) echo "ERROR: no yq binary mapping for ${ARCH}" >&2; exit 1 ;;
  esac
  echo "==> [10-packages] yq ${YQ_VERSION} (${ARCH})"
  WORK="$(mktemp -d)"
  curl -fsSL -o "${WORK}/yq" \
    "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${ARCH}"
  echo "${YQ_SHA,,}  ${WORK}/yq" | sha256sum -c -
  install -m 0755 "${WORK}/yq" /usr/local/bin/yq
  rm -rf "${WORK}"
fi

echo "==> [10-packages] Installed versions"
command -v git  >/dev/null && git --version
command -v gh   >/dev/null && gh --version | awk 'NR==1'
command -v pwsh >/dev/null && pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
command -v yq >/dev/null && yq --version
command -v dos2unix >/dev/null && dos2unix --version | awk 'NR==1'
dpkg -s ca-certificates >/dev/null 2>&1 && echo "ca-certificates $(dpkg-query -W -f='${Version}' ca-certificates)"

echo "==> [10-packages] Done"

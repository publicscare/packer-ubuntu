#!/usr/bin/env bash
# Build the stock Ubuntu 24.04.5 base image.
#
#   ./build.sh                  arm64 (VMware Fusion), same as before
#   ./build.sh amd64            x64 (QEMU; emulated on Apple Silicon, slow)
#   ./build.sh all              both, one after the other
#   ./build.sh [target] validate   init + validate only
#   ./build.sh validate            validate everything
#   ./build.sh amd64 build -var 'cpus=4' ...   anything after the action goes to packer
#
# Secrets: prefer environment variables (PKR_VAR_build_password,
# PKR_VAR_ssh_authorized_key) over -var, which shows up in shell history.
set -euo pipefail
# macOS ships bash 3.2: empty arrays need the ${a[@]+"${a[@]}"} form under set -u.
cd "$(dirname "$0")"

TARGET="${1:-arm64}"
ACTION="${2:-build}"
if [[ "${TARGET}" == "validate" ]]; then TARGET=all; ACTION=validate; fi
# Everything after [target] [action] is passed straight to packer.
EXTRA=()
if [[ $# -gt 2 ]]; then EXTRA=("${@:3}"); fi
# Output names: template-<IMAGE_DATE>-ubuntu-... (default: today, UTC, as Packer).
IMAGE_DATE="${IMAGE_DATE:-$(date -u +%Y-%m-%d)}"
EXTRA=(-var "image_date=${IMAGE_DATE}" ${EXTRA[@]+"${EXTRA[@]}"})
echo "Image date: ${IMAGE_DATE}  (override: IMAGE_DATE=2026-11-01 ./build.sh ...)"

case "${TARGET}" in
  arm64) ONLY=(-only='ubuntu-base.vmware-iso.ubuntu-base') ;;
  amd64) ONLY=(-only='ubuntu-base.qemu.ubuntu-base-amd64') ;;
  # VirtualBox (x64) builds run from Windows with Build.ps1, not from here.
  all)   ONLY=(-only='ubuntu-base.vmware-iso.ubuntu-base,ubuntu-base.qemu.ubuntu-base-amd64') ;;
  *) echo "Usage: $0 [arm64|amd64|all] [build|validate]" >&2; exit 2 ;;
esac

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing '$1'. $2" >&2; exit 1; }; }
need packer   "Install: brew tap hashicorp/tap && brew install hashicorp/tap/packer"
need qemu-img "Install: brew install qemu"
[[ -f packages.txt ]] || { echo "packages.txt is missing" >&2; exit 1; }

if [[ "${TARGET}" != "amd64" ]]; then
  [[ -x "/Applications/VMware Fusion.app/Contents/Library/vmrun" ]] \
    || { echo "VMware Fusion not found in /Applications (set fusion_app_path if it lives elsewhere)." >&2; exit 1; }
  compgen -G "../iso/*arm64*.iso" >/dev/null || { echo "No arm64 ISO in ../iso" >&2; exit 1; }
fi
if [[ "${TARGET}" != "arm64" ]]; then
  need qemu-system-x86_64 "Install: brew install qemu"
  for fw in /opt/homebrew/share/qemu/edk2-x86_64-code.fd /opt/homebrew/share/qemu/edk2-i386-vars.fd; do
    [[ -f "${fw}" ]] || echo "WARN: ${fw} not found; set qemu_efi_code / qemu_efi_vars" >&2
  done
  compgen -G "../iso/*amd64*.iso" >/dev/null \
    || echo "NOTE: no amd64 ISO in ../iso; Packer will download it (~3 GB) into its cache" >&2
fi

packer init .
packer fmt -check -recursive . || echo "WARN: run 'packer fmt -recursive .' to tidy formatting" >&2
packer validate ${ONLY[@]+"${ONLY[@]}"} ${EXTRA[@]+"${EXTRA[@]}"} .

[[ "${ACTION}" == "validate" ]] && exit 0

mkdir -p logs artifacts
export PACKER_LOG=1
PACKER_LOG_PATH="logs/packer-${TARGET}-$(date +%Y%m%d-%H%M%S).log"
export PACKER_LOG_PATH
echo "Detailed log: ${PACKER_LOG_PATH}"
packer build -on-error=ask ${ONLY[@]+"${ONLY[@]}"} ${EXTRA[@]+"${EXTRA[@]}"} .

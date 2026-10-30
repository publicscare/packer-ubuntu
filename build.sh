#!/usr/bin/env bash
# Build the Ubuntu 24.04.5 arm64 Kubernetes + Cilium image with VMware Fusion.
#   ./build.sh            init, validate, build
#   ./build.sh validate   init and validate only
set -euo pipefail
cd "$(dirname "$0")"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing '$1'. $2" >&2; exit 1; }; }
need packer   "Install: brew tap hashicorp/tap && brew install hashicorp/tap/packer"
need qemu-img "Install: brew install qemu   (or set create_raw_image = false)"
[[ -x "/Applications/VMware Fusion.app/Contents/Library/vmrun" ]] \
  || { echo "VMware Fusion not found in /Applications (set fusion_app_path if it lives elsewhere)." >&2; exit 1; }
[[ "$(uname -m)" == "arm64" ]] || echo "WARN: this template targets arm64 guests on Apple Silicon." >&2
compgen -G "iso/*.iso" >/dev/null || { echo "No ISO in ./iso" >&2; exit 1; }

packer init .
packer fmt -check -recursive . || echo "WARN: run 'packer fmt -recursive .' to tidy formatting" >&2
packer validate .

[[ "${1:-build}" == "validate" ]] && exit 0

mkdir -p logs artifacts
export PACKER_LOG=1
PACKER_LOG_PATH="logs/packer-$(date +%Y%m%d-%H%M%S).log"
export PACKER_LOG_PATH
echo "Detailed log: ${PACKER_LOG_PATH}"
packer build -on-error=ask .

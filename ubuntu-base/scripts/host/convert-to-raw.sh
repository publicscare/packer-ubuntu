#!/usr/bin/env bash
# Runs on the Mac after the build: convert the Fusion VMDK into a raw .img.
set -euo pipefail
: "${VM_OUTPUT_DIR:?}" "${ARTIFACTS_DIR:?}" "${IMAGE_NAME:?}"

# Always create the artifacts folder: the manifest post-processor writes here too.
mkdir -p "${ARTIFACTS_DIR}"

if [[ "${CREATE_RAW_IMAGE:-true}" != "true" ]]; then
  echo "create_raw_image=false: skipping raw image conversion"
  exit 0
fi

if ! command -v qemu-img >/dev/null 2>&1; then
  echo "ERROR: qemu-img not found. Install it with: brew install qemu" >&2
  exit 1
fi

VMDK="${VM_OUTPUT_DIR}/disk.vmdk"
[[ -f "${VMDK}" ]] || VMDK="$(find "${VM_OUTPUT_DIR}" -maxdepth 1 -name '*.vmdk' ! -name '*-s0*.vmdk' | head -n1)"
[[ -f "${VMDK}" ]] || { echo "ERROR: no .vmdk found in ${VM_OUTPUT_DIR}" >&2; exit 1; }

mkdir -p "${ARTIFACTS_DIR}"
IMG="${ARTIFACTS_DIR}/${IMAGE_NAME}.img"

echo "==> Converting ${VMDK} -> ${IMG}"
qemu-img convert -p -f vmdk -O raw "${VMDK}" "${IMG}"
qemu-img info "${IMG}"

echo "==> Writing checksum"
( cd "${ARTIFACTS_DIR}" && shasum -a 256 "$(basename "${IMG}")" > "$(basename "${IMG}").sha256" )
cat "${IMG}.sha256"

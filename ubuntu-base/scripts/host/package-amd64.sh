#!/usr/bin/env bash
# Runs on the build host after the x64 QEMU build. Turns the qcow2 into:
#   artifacts/<name>.img                 raw disk (dd to disk / other hypervisors)
#   artifacts/<name>-workstation/        VMware Workstation VM (vmx + vmdk)
#   artifacts/<name>.ova                 OVA for vSphere and VirtualBox (needs ovftool)
# plus a .sha256 for the .img and .ova.
#
# The virtual hardware is chosen for portability, not speed: UEFI, SATA disk,
# e1000e NIC, hardware version 19 (Workstation 16.2+, ESXi 7.0 U2+). Switch to
# NVMe / vmxnet3 after import if you want the faster devices.
set -euo pipefail
: "${QEMU_OUTPUT_DIR:?}" "${ARTIFACTS_DIR:?}" "${IMAGE_NAME:?}"
CPUS="${CPUS:-2}"
MEMORY_MB="${MEMORY_MB:-4096}"

mkdir -p "${ARTIFACTS_DIR}"
command -v qemu-img >/dev/null 2>&1 || { echo "ERROR: qemu-img not found (brew install qemu)" >&2; exit 1; }

QCOW="${QEMU_OUTPUT_DIR}/${IMAGE_NAME}.qcow2"
[[ -f "${QCOW}" ]] || { echo "ERROR: ${QCOW} not found" >&2; exit 1; }
qemu-img info "${QCOW}"

# --- raw .img ---------------------------------------------------------------
IMG="${ARTIFACTS_DIR}/${IMAGE_NAME}.img"
echo "==> raw image: ${IMG}"
qemu-img convert -p -f qcow2 -O raw "${QCOW}" "${IMG}"

# --- VMware Workstation VM ----------------------------------------------------
WS_DIR="${ARTIFACTS_DIR}/${IMAGE_NAME}-workstation"
VMX="${WS_DIR}/${IMAGE_NAME}.vmx"
echo "==> Workstation VM: ${WS_DIR}"
rm -rf "${WS_DIR}"
mkdir -p "${WS_DIR}"
# adapter_type=ide is what VMware records for SATA-attached disks.
qemu-img convert -p -f qcow2 -O vmdk -o subformat=monolithicSparse,adapter_type=ide \
  "${QCOW}" "${WS_DIR}/disk.vmdk"
cat > "${VMX}" <<EOF
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "19"
displayName = "${IMAGE_NAME}"
annotation = "Ubuntu 24.04.5 x64 base image (built with Packer + QEMU)"
guestOS = "ubuntu-64"
firmware = "efi"
numvcpus = "${CPUS}"
memsize = "${MEMORY_MB}"
sata0.present = "TRUE"
sata0:0.present = "TRUE"
sata0:0.fileName = "disk.vmdk"
ethernet0.present = "TRUE"
ethernet0.virtualDev = "e1000e"
ethernet0.connectionType = "nat"
ethernet0.addressType = "generated"
usb.present = "TRUE"
ehci.present = "TRUE"
tools.syncTime = "FALSE"
EOF

# --- OVA (vSphere / VirtualBox) ---------------------------------------------
OVFTOOL="${OVFTOOL:-/Applications/VMware Fusion.app/Contents/Library/VMware OVF Tool/ovftool}"
command -v ovftool >/dev/null 2>&1 && OVFTOOL="$(command -v ovftool)"
OVA="${ARTIFACTS_DIR}/${IMAGE_NAME}.ova"
if [[ -x "${OVFTOOL}" ]]; then
  echo "==> OVA: ${OVA}"
  rm -f "${OVA}"
  "${OVFTOOL}" --acceptAllEulas --shaAlgorithm=SHA256 --name="${IMAGE_NAME}" "${VMX}" "${OVA}"
else
  echo "WARN: ovftool not found at ${OVFTOOL}; skipping the OVA (set OVFTOOL=/path/to/ovftool)" >&2
fi

# --- checksums ----------------------------------------------------------------
echo "==> checksums"
cd "${ARTIFACTS_DIR}"
for f in "${IMAGE_NAME}.img" "${IMAGE_NAME}.ova"; do
  [[ -f "${f}" ]] || continue
  shasum -a 256 "${f}" > "${f}.sha256"
  cat "${f}.sha256"
done

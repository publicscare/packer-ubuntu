#!/usr/bin/env bash
# OS baseline: full upgrade, guest tools, LVM grow + first-boot helpers.
set -euo pipefail
: "${STAGE_DIR:?}"
[[ -d "${STAGE_DIR}" ]] || { echo "ERROR: staged files missing in ${STAGE_DIR}" >&2; exit 1; }

echo "==> [00-base] Updating packages"
apt-get update -y
apt-get -y -o Dpkg::Options::=--force-confold full-upgrade

echo "==> [00-base] Baseline packages"
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg open-vm-tools cloud-guest-utils bash-completion

# x64 images (QEMU and VirtualBox builds) are meant to move between
# hypervisors: ship all guest agents. Each one only starts on its own
# hypervisor (systemd ConditionVirtualization).
if [[ "${PACKER_BUILDER_TYPE:-}" == "qemu" || "${PACKER_BUILDER_TYPE:-}" == "virtualbox-iso" ]]; then
  echo "==> [00-base] Multi-hypervisor guest agents (VMware, VirtualBox, QEMU/KVM)"
  apt-get install -y --no-install-recommends qemu-guest-agent virtualbox-guest-utils
fi

echo "==> [00-base] Root volume growth and first-boot SSH host keys"
install -m 0755 "${STAGE_DIR}/usr/local/sbin/grow-root" /usr/local/sbin/grow-root
install -m 0644 "${STAGE_DIR}/etc/systemd/system/grow-root.service" /etc/systemd/system/grow-root.service
install -m 0644 "${STAGE_DIR}/etc/systemd/system/regenerate-ssh-host-keys.service" \
  /etc/systemd/system/regenerate-ssh-host-keys.service
install -m 0644 "${STAGE_DIR}/etc/cloud/cloud.cfg.d/95-base-image.cfg" /etc/cloud/cloud.cfg.d/95-base-image.cfg
systemctl daemon-reload
systemctl enable grow-root.service regenerate-ssh-host-keys.service

lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
vgs
lvs

echo "==> [00-base] Done"

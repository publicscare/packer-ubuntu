#!/usr/bin/env bash
# OS baseline for a Kubernetes node: packages, kernel modules, sysctls, no swap.
set -euo pipefail

# Staged image files must live in /var/tmp: Ubuntu empties /tmp on every boot
# and the build reboots after this script. Older template revisions uploaded
# to /tmp, so move them across if that's where they landed.
if [[ -d /tmp/k8s-image ]]; then
  rm -rf /var/tmp/k8s-image
  mv /tmp/k8s-image /var/tmp/k8s-image
fi
[[ -d /var/tmp/k8s-image ]] || { echo "ERROR: staged files missing in /var/tmp/k8s-image" >&2; exit 1; }

echo "==> [00-base] Updating packages"
apt-get update -y
apt-get -y -o Dpkg::Options::=--force-confold full-upgrade

echo "==> [00-base] Installing node prerequisites"
apt-get install -y --no-install-recommends \
  apt-transport-https ca-certificates curl gnupg jq \
  conntrack socat ethtool ipset iptables ebtables \
  nfs-common open-iscsi chrony \
  open-vm-tools cloud-guest-utils \
  bash-completion

systemctl enable --now chrony

echo "==> [00-base] Disabling swap"
swapoff -a || true
sed -ri '/\sswap\s/s/^#?/#/' /etc/fstab
systemctl mask swap.target >/dev/null 2>&1 || true

echo "==> [00-base] Kernel modules and sysctls"
install -m 0644 /var/tmp/k8s-image/etc/modules-load.d/k8s.conf /etc/modules-load.d/k8s.conf
install -m 0644 /var/tmp/k8s-image/etc/sysctl.d/99-kubernetes.conf /etc/sysctl.d/99-kubernetes.conf
modprobe overlay
modprobe br_netfilter
sysctl --system >/dev/null

echo "==> [00-base] Done"

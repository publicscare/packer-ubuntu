#!/usr/bin/env bash
# Install the cluster bootstrap helpers, version stamp and first-boot units.
set -euo pipefail
: "${K8S_VERSION:?}" "${CILIUM_VERSION:?}" "${IMAGE_NAME:?}"

echo "==> [40-node-helpers] Installing helper scripts"
for f in k8s-init-control-plane k8s-join-node k8s-grow-root; do
  install -m 0755 "/tmp/k8s-image/usr/local/sbin/${f}" "/usr/local/sbin/${f}"
done

echo "==> [40-node-helpers] Automatic LVM root growth on boot"
install -m 0644 /tmp/k8s-image/etc/systemd/system/k8s-grow-root.service \
  /etc/systemd/system/k8s-grow-root.service

echo "==> [40-node-helpers] Writing /etc/k8s-image/versions.env"
install -d -m 0755 /etc/k8s-image
cat > /etc/k8s-image/versions.env <<EOF
IMAGE_NAME=${IMAGE_NAME}
IMAGE_BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
K8S_VERSION=${K8S_VERSION}
CILIUM_VERSION=${CILIUM_VERSION}
CILIUM_CHART=/opt/k8s-image/charts/cilium-${CILIUM_VERSION}.tgz
CONTAINERD_VERSION=${CONTAINERD_VERSION:-}
RUNC_VERSION=${RUNC_VERSION:-}
EOF

echo "==> [40-node-helpers] First-boot SSH host key regeneration"
install -m 0644 /tmp/k8s-image/etc/systemd/system/regenerate-ssh-host-keys.service \
  /etc/systemd/system/regenerate-ssh-host-keys.service
systemctl daemon-reload
systemctl enable regenerate-ssh-host-keys.service k8s-grow-root.service

echo "==> [40-node-helpers] Root volume layout"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
vgs; lvs

echo "==> [40-node-helpers] cloud-init datasources for clones (VMware guestinfo, NoCloud seed)"
install -m 0644 /tmp/k8s-image/etc/cloud/cloud.cfg.d/95-k8s-image.cfg \
  /etc/cloud/cloud.cfg.d/95-k8s-image.cfg

echo "==> [40-node-helpers] Done"

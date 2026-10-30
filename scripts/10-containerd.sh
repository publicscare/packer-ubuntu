#!/usr/bin/env bash
# containerd + runc from the upstream release binaries, checksum-verified.
set -euo pipefail
: "${CONTAINERD_VERSION:?}" "${RUNC_VERSION:?}"

ARCH="$(dpkg --print-architecture)" # arm64
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
cd "${WORK}"

echo "==> [10-containerd] containerd ${CONTAINERD_VERSION} (${ARCH})"
CTR_TGZ="containerd-${CONTAINERD_VERSION}-linux-${ARCH}.tar.gz"
CTR_BASE="https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}"
curl -fsSLO "${CTR_BASE}/${CTR_TGZ}"
curl -fsSLO "${CTR_BASE}/${CTR_TGZ}.sha256sum"
sha256sum -c "${CTR_TGZ}.sha256sum"
tar -C /usr/local -xzf "${CTR_TGZ}"

install -d /usr/local/lib/systemd/system
curl -fsSL -o /usr/local/lib/systemd/system/containerd.service \
  "https://raw.githubusercontent.com/containerd/containerd/v${CONTAINERD_VERSION}/containerd.service"

echo "==> [10-containerd] runc ${RUNC_VERSION}"
RUNC_BASE="https://github.com/opencontainers/runc/releases/download/v${RUNC_VERSION}"
curl -fsSLO "${RUNC_BASE}/runc.${ARCH}"
curl -fsSLO "${RUNC_BASE}/runc.sha256sum"
grep " runc.${ARCH}\$" runc.sha256sum | sha256sum -c -
install -m 0755 "runc.${ARCH}" /usr/local/sbin/runc

echo "==> [10-containerd] Writing /etc/containerd/config.toml (systemd cgroups)"
install -d /etc/containerd
/usr/local/bin/containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
if ! grep -q 'SystemdCgroup = true' /etc/containerd/config.toml; then
  echo "ERROR: could not enable SystemdCgroup in containerd config" >&2
  exit 1
fi

systemctl daemon-reload
systemctl enable --now containerd
/usr/local/bin/containerd --version
runc --version | awk 'NR==1'

echo "==> [10-containerd] Done"

#!/usr/bin/env bash
# Helm + cilium-cli, the Cilium Helm chart saved locally, and every Cilium image
# the chart references pre-pulled into containerd. Cilium itself is installed
# when a cluster is created (k8s-init-control-plane).
set -euo pipefail
: "${CILIUM_VERSION:?}" "${CILIUM_CLI_VERSION:?}" "${HELM_VERSION:?}"

ARCH="$(dpkg --print-architecture)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
cd "${WORK}"

echo "==> [30-cilium] helm v${HELM_VERSION}"
HELM_TGZ="helm-v${HELM_VERSION}-linux-${ARCH}.tar.gz"
curl -fsSLO "https://get.helm.sh/${HELM_TGZ}"
curl -fsSLO "https://get.helm.sh/${HELM_TGZ}.sha256sum"
sha256sum -c "${HELM_TGZ}.sha256sum"
tar -xzf "${HELM_TGZ}"
install -m 0755 "linux-${ARCH}/helm" /usr/local/bin/helm

echo "==> [30-cilium] cilium-cli v${CILIUM_CLI_VERSION}"
CLI_TGZ="cilium-linux-${ARCH}.tar.gz"
CLI_BASE="https://github.com/cilium/cilium-cli/releases/download/v${CILIUM_CLI_VERSION}"
curl -fsSLO "${CLI_BASE}/${CLI_TGZ}"
curl -fsSLO "${CLI_BASE}/${CLI_TGZ}.sha256sum"
sha256sum -c "${CLI_TGZ}.sha256sum"
tar -C /usr/local/bin -xzf "${CLI_TGZ}"
chmod 0755 /usr/local/bin/cilium

echo "==> [30-cilium] Saving Cilium ${CILIUM_VERSION} chart and values"
install -d -m 0755 /opt/k8s-image/charts /etc/k8s-image
install -m 0644 /tmp/k8s-image/etc/k8s-image/cilium-values.yaml /etc/k8s-image/cilium-values.yaml
export HELM_CONFIG_HOME="${WORK}/helm-config" HELM_CACHE_HOME="${WORK}/helm-cache"
helm repo add cilium https://helm.cilium.io/ >/dev/null
helm repo update cilium >/dev/null
helm pull cilium/cilium --version "${CILIUM_VERSION}" -d /opt/k8s-image/charts
CHART="/opt/k8s-image/charts/cilium-${CILIUM_VERSION}.tgz"

echo "==> [30-cilium] Pre-pulling images referenced by the chart"
helm template cilium "${CHART}" --namespace kube-system \
  -f /etc/k8s-image/cilium-values.yaml \
  --set k8sServiceHost=127.0.0.1 --set k8sServicePort=6443 \
  | grep -E '^\s*image:\s' | awk '{print $2}' | tr -d "\"'" | sort -u > images.txt
cat images.txt
while read -r img; do
  [[ -n "${img}" ]] && crictl pull "${img}"
done < images.txt
install -m 0644 images.txt /etc/k8s-image/cilium-images.txt

cilium completion bash > /etc/bash_completion.d/cilium
helm completion bash > /etc/bash_completion.d/helm

echo "==> [30-cilium] Done"

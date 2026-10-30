#!/usr/bin/env bash
# kubeadm / kubelet / kubectl from pkgs.k8s.io, pinned and held; control-plane
# images pre-pulled so new clusters come up without internet access.
set -euo pipefail
: "${K8S_VERSION:?}" "${K8S_MINOR:?}"

echo "==> [20-kubernetes] Adding pkgs.k8s.io repo for v${K8S_MINOR}"
install -d -m 0755 /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/deb/Release.key" \
  | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list
apt-get update -y

PKG_VER="$(apt-cache madison kubeadm | awk -v v="${K8S_VERSION}" '$3 ~ "^"v"-" {print $3; exit}')"
if [[ -z "${PKG_VER}" ]]; then
  echo "ERROR: kubeadm ${K8S_VERSION} not found in pkgs.k8s.io v${K8S_MINOR}" >&2
  exit 1
fi

echo "==> [20-kubernetes] Installing kubelet/kubeadm/kubectl ${PKG_VER}"
apt-get install -y kubelet="${PKG_VER}" kubeadm="${PKG_VER}" kubectl="${PKG_VER}"
apt-mark hold kubelet kubeadm kubectl

cat > /etc/crictl.yaml <<'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
EOF

# Keep containerd's sandbox (pause) image in step with what kubeadm expects.
PAUSE_IMAGE="$(kubeadm config images list --kubernetes-version "v${K8S_VERSION}" | grep '/pause:' | head -n1)"
if grep -qE "^\s*sandbox(_image)? = " /etc/containerd/config.toml; then
  sed -ri "s#^(\s*sandbox(_image)? = ).*#\1'${PAUSE_IMAGE}'#" /etc/containerd/config.toml
  systemctl restart containerd
else
  echo "WARN: no sandbox key in containerd config; leaving containerd's default pause image"
fi

echo "==> [20-kubernetes] Pre-pulling control-plane images"
kubeadm config images pull \
  --kubernetes-version "v${K8S_VERSION}" \
  --cri-socket unix:///run/containerd/containerd.sock

kubectl completion bash > /etc/bash_completion.d/kubectl
kubeadm completion bash > /etc/bash_completion.d/kubeadm
systemctl enable kubelet

echo "==> [20-kubernetes] Done"

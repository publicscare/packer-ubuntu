# Ubuntu 24.04.5 arm64 Kubernetes node image (Packer + VMware Fusion)

Packer template that installs **Ubuntu Server 24.04.5 (arm64)** in **VMware Fusion Pro** on Apple Silicon and produces a generic Kubernetes node image with **Cilium** ready to deploy.

| Component | Version | Source |
|---|---|---|
| Ubuntu Server | 24.04.5 arm64 | local ISO in `iso/` |
| Kubernetes (kubeadm/kubelet/kubectl) | 1.36.5 (apt-held) | pkgs.k8s.io |
| containerd / runc | 2.3.4 / 1.5.1 | upstream releases, checksum-verified |
| Cilium (chart + images pre-pulled) | 1.20.4, kube-proxy replacement, VXLAN, Hubble | helm.cilium.io / quay.io |
| cilium-cli / helm | 0.19.7 / 3.22.1 | upstream releases, checksum-verified |

Versions are variables in `variables.pkr.hcl`; override them in `local.auto.pkrvars.hcl`.

## Outputs

```
output/<vm_name>/           Fusion VM template: <vm_name>.vmx + disk.vmdk
artifacts/<vm_name>.img     raw disk image (qemu-img), plus .sha256
artifacts/manifest.json     Packer manifest with version metadata
```

`<vm_name>` = `ubuntu-24.04.5-k8s-1.36.5-cilium-1.20.4-arm64`. `output/`, `artifacts/`, `iso/`, `logs/` and `*.auto.pkrvars.hcl` are git-ignored.

## Layout

```
ubuntu-k8s.pkr.hcl              source (vmware-iso) + build + post-processors
variables.pkr.hcl               all tunables and pinned versions
local.auto.pkrvars.hcl.example  copy -> local.auto.pkrvars.hcl (passwords, SSH key)
templates/user-data.pkrtpl.hcl  Subiquity autoinstall, served over Packer's HTTP server
scripts/00-base.sh              packages, swap off, kernel modules, sysctls
scripts/10-containerd.sh        containerd + runc, SystemdCgroup=true
scripts/20-kubernetes.sh        kubeadm/kubelet/kubectl, pause image alignment, image pre-pull
scripts/30-cilium.sh            helm, cilium-cli, Cilium chart saved + images pre-pulled
scripts/40-node-helpers.sh      bootstrap helpers, versions.env, first-boot units
scripts/90-cleanup.sh           generalize: machine-id, SSH host keys, cloud-init, logs, trim
scripts/host/convert-to-raw.sh  runs on the Mac: vmdk -> raw .img
files/                          files copied into the image (mirrors the guest filesystem)
docs/vmware-fusion-setup.md     one-time Mac / Fusion preparation
```

## Build

1. Prepare the Mac: [docs/vmware-fusion-setup.md](docs/vmware-fusion-setup.md).
2. `cp local.auto.pkrvars.hcl.example local.auto.pkrvars.hcl` and set a password / SSH key.
3. `./build.sh validate`, then `./build.sh`.

## Using the image

Clone the Fusion VM (Fusion: **File → New → Create a custom VM** from the vmdk, or copy the folder and answer **"I copied it"** so it gets a new UUID and MAC), or write `artifacts/*.img` to a disk for another UEFI arm64 host. Each copy regenerates its machine-id and SSH host keys on first boot.

First control-plane node:

```bash
sudo k8s-init-control-plane --node-name cp-01            # add --single-node for a one-node lab
# or, for a multi-control-plane cluster behind a VIP / DNS name:
sudo k8s-init-control-plane --node-name cp-01 --endpoint k8s-api.lab.local --ha
```

It runs `kubeadm init` without kube-proxy, installs Cilium from the chart baked into the image, waits for `cilium status`, and prints the join commands (also saved to `/root/k8s-join-commands.txt`).

Workers / extra control-plane nodes:

```bash
sudo k8s-join-node --node-name worker-01 -- <args printed by k8s-init-control-plane>
```

Check: `kubectl get nodes -o wide`, `cilium status`, `cilium connectivity test` (needs internet).

## Disk layout and growing the root volume

The installer lays the disk out as GPT with three partitions: an EFI system partition, `/boot` (ext4), and an LVM physical volume. The physical volume holds volume group `ubuntu-vg`, whose only logical volume `ubuntu-lv` (ext4) is `/` and uses all of the group. There is no swap. containerd images, etcd and pod data all live on `/`.

To grow a node:

1. Enlarge the disk. In Fusion: **VM Settings → Hard Disk → Disk size** (VM powered off). For the raw `.img`, write it to a bigger disk or run `qemu-img resize`.
2. Boot the VM. `k8s-grow-root.service` runs on every boot and grows the partition, physical volume, logical volume and ext4 filesystem (`growpart → pvresize → lvextend -r`).
   To grow without a reboot, run `sudo k8s-grow-root` (all free space) or `sudo k8s-grow-root --size +20G`.

Other LVM options:
- Add a second disk: `pvcreate /dev/nvme0n2 && vgextend ubuntu-vg /dev/nvme0n2 && lvextend -r -l +100%FREE /dev/ubuntu-vg/ubuntu-lv`.
- To give `/var/lib/containerd` its own volume, run `k8s-grow-root --size` with a fixed size to leave free extents in the volume group, then create a separate logical volume from them.

> Every copy of the image uses the same volume group name (`ubuntu-vg`). Don't attach one node's disk to another node, because the two volume groups will clash.

## Notes

- The raw `.img` boots on UEFI arm64 systems (other hypervisors, SystemReady servers). Boards that need vendor boot firmware, such as a Raspberry Pi, need a board-specific image instead.
- Kubelet is enabled but restarts until `kubeadm init/join` runs. That is expected.
- With `ssh_authorized_key` set, the image disables SSH password login. Console login with `build_password` still works, so change that password per environment.

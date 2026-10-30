# Ubuntu 24.04.5 base image: arm64 + x64 (Packer)

A stock Ubuntu Server 24.04.5 image with a configurable package list, built for arm64 and x64. It uses the same Fusion settings, unattended install and generalisation as the Kubernetes image in the parent folder, without Kubernetes.

| | |
|---|---|
| Base | Ubuntu Server 24.04.5 |
| Architectures | **arm64** on VMware Fusion (Apple Silicon); **x64** on QEMU (emulated on a Mac, native with KVM on x86 Linux) or **VirtualBox** (Windows, `Build.ps1`) |
| Disk | GPT, ESP + `/boot` + LVM (`ubuntu-vg/ubuntu-lv`, whole VG), no swap |
| Always installed | `ca-certificates`, `git`, `gh` (GitHub CLI), PowerShell 7.6.6 (`pwsh`) |
| Extras in `packages.txt` | `dos2unix`, `yq` v4.54.1 (mikefarah, Go) |
| Extras | anything you add to `packages.txt` |

### Naming

Every output is named `template-<YYYY-MM-DD>-ubuntu-24.04.5-base-<arch>…`, e.g. `template-2026-11-01-ubuntu-24.04.5-base-arm64.img`. Monthly rebuilds sort by date and never overwrite each other. The date defaults to **today in UTC**, which is Packer's clock. Pin it to rebuild or redo a release:

```bash
IMAGE_DATE=2026-11-01 ./build.sh               # macOS
.\Build.ps1 -ImageDate 2026-11-01               # Windows
packer build -var image_date=2026-11-01 ...     # direct
```

`name_prefix` (default `template`) changes the first word.

### Outputs (`artifacts/`)

| Arch | File | Use it with |
|---|---|---|
| arm64 | `<prefix>-ubuntu-24.04.5-base-arm64.img` (+ VM in `output/`) | Fusion, other arm64 UEFI hosts |
| x64 | `<prefix>-ubuntu-24.04.5-base-amd64.img` | dd to disk, KVM/Proxmox, any UEFI x64 hypervisor |
| x64 | `<prefix>-ubuntu-24.04.5-base-amd64-workstation/` (vmx + vmdk) | VMware Workstation Pro: open the `.vmx` |
| x64 | `<prefix>-ubuntu-24.04.5-base-amd64.ova` | vSphere (Deploy OVF Template), VirtualBox (Import Appliance) |
| x64 | `<prefix>-ubuntu-24.04.5-base-amd64-virtualbox.ova` (VirtualBox build) | VirtualBox (Import Appliance); also vSphere / Workstation |

Every `.img` and `.ova` has a `.sha256`. `manifest.json` lists every build.

The x64 disk is provider-neutral. It carries `open-vm-tools`, the VirtualBox guest utilities and `qemu-guest-agent`, and each starts only on its own hypervisor. The x64 VM definition favours compatibility over speed: UEFI, SATA disk, e1000e NIC, hardware version 19 (Workstation 16.2+, ESXi 7.0 U2+). After importing, you can switch to NVMe and vmxnet3 on VMware.

## Adding packages

Edit `packages.txt`, one package per line:

```text
ca-certificates
git
gh
powershell
jq          # extra apt package
```

- Plain names install with `apt` from Ubuntu's archive. Check a name exists with `apt-cache policy <name>` on an Ubuntu box.
- `gh` comes from GitHub's own apt repo.
- `yq` installs **mikefarah/yq v4** (the Go tool) to `/usr/local/bin/yq` from its GitHub release, checked against the pinned SHA-256. To upgrade, change `yq_version`, `yq_sha256_arm64` and `yq_sha256_amd64`. The hashes are in the release's `checksums` file. Ubuntu's own apt `yq` is a different tool, a Python wrapper around jq.
- `powershell` (or `pwsh`) installs the official arm64 tarball into `/opt/microsoft/powershell/7`, linked as `/usr/bin/pwsh`. On x64 it uses the `linux-x64` tarball. To upgrade, change `powershell_version`, `powershell_sha256` (arm64) **and** `powershell_sha256_amd64` in `variables.pkr.hcl`. The hashes are on the release page.

Packer reads `packages.txt` and the scripts when it runs them. So if a package step fails, you can fix the list and press `r` (retry) without reinstalling Ubuntu.

To use a different list, run `packer build -var packages_file=packages-dev.txt .`

## Build

```bash
cd ~/k8s/packer/ubuntu-base
cp local.auto.pkrvars.hcl.example local.auto.pkrvars.hcl   # set password / SSH key
./build.sh validate      # checks both architectures
./build.sh               # arm64 on Fusion (~10 min)
./build.sh amd64         # x64 on QEMU (emulated on Apple Silicon: an hour or more)
./build.sh all           # both
```

Mac and Fusion prerequisites are the same as for the Kubernetes image: see `../docs/vmware-fusion-setup.md`. The x64 build also needs `brew install qemu`, which gives `qemu-system-x86_64` and the x64 UEFI firmware. The OVA step uses the `ovftool` inside Fusion.

**x64 ISO:** if `../iso/ubuntu-24.04.5-live-server-amd64.iso` isn't there, Packer downloads it from releases.ubuntu.com and checks it against Ubuntu's published `SHA256SUMS`.

**x64 under emulation:** a QEMU window (Cocoa) opens unless `headless = true`. The console is also on VNC at the `127.0.0.1:59xx` address printed in the build output (`open vnc://127.0.0.1:59xx`). Packer presses the up arrow every 5 s for the first ~90 s to stop GRUB's countdown, then types the autoinstall command. The install and package steps are much slower than on Fusion; `qemu_ssh_timeout` allows 4 h.

**x64 on an x86 Linux host or CI runner with KVM** (native speed):

```bash
packer build -only='ubuntu-base.qemu.ubuntu-base-amd64' \
  -var qemu_accelerator=kvm -var qemu_cpu_model=host \
  -var qemu_efi_code=/usr/share/OVMF/OVMF_CODE_4M.fd \
  -var qemu_efi_vars=/usr/share/OVMF/OVMF_VARS_4M.fd \
  -var headless=true .
```

On Linux, `ovftool` comes from VMware's download site. Without it the OVA is skipped and the `.img` and Workstation VM are still produced.

## Build on Windows with VirtualBox (e.g. a corporate laptop)

Prerequisites: Git, Packer, and VirtualBox 7.x (`winget install Git.Git Hashicorp.Packer Oracle.VirtualBox`). The first `packer init` downloads the plugins from GitHub.

```powershell
git clone https://github.com/publicscare/packer-ubuntu.git
cd packer-ubuntu

# Corporate root CA(s), e.g. Zscaler - git-ignored, never pushed
Copy-Item C:\path\to\zscaler-ca.crt .\certs\

cd ubuntu-base
# Secrets as environment variables (or local.auto.pkrvars.hcl, also git-ignored)
$s = Read-Host 'Build password' -AsSecureString
$env:PKR_VAR_build_password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
$env:PKR_VAR_ssh_authorized_key = (Get-Content -Raw $HOME\.ssh\id_ed25519.pub).Trim()

.\Build.ps1 -Action validate
.\Build.ps1                      # -> artifacts\ubuntu-24.04.5-base-amd64-virtualbox.ova (+ .sha256)
```

Then provision VMs with **VirtualBox → File → Import Appliance**, or `VBoxManage import <ova> --vsys 0 --vmname dev-01`.

Notes:
- **Line endings:** `.gitattributes` keeps every file LF on a Windows clone. `Build.ps1` refuses to run if a guest-side file (`scripts/`, `templates/`, `files/`, `packages.txt`) has CRLF endings, and prints the fix.
- **Zscaler / TLS inspection:** the certificates in `../certs/` are trusted in the guest before any HTTPS download, and stay trusted in the image. With no certificates, `Build.ps1` warns you and the HTTPS downloads will probably fail behind Zscaler. See `../certs/README.md` for exporting the Zscaler root from Windows.
- **Hyper-V / VBS:** if Windows' hypervisor is active (common on managed laptops), VirtualBox runs on top of it. It still works but is slower, and `Build.ps1` warns you.
- **Firewall:** allow Packer when Windows asks. The VM fetches its autoinstall config from Packer's HTTP server on your machine (at 10.0.2.2 inside the VM).
- `vbox_keep_registered = true` also leaves the built VM in VirtualBox Manager, and `vbox_nic_type = "virtio"` gives a faster NIC.

## Layout

```
ubuntu-base.pkr.hcl              arm64 Fusion source + shared build + post-processors
sources-amd64-qemu.pkr.hcl       x64 QEMU source
sources-amd64-virtualbox.pkr.hcl x64 VirtualBox source (OVA)
Build.ps1                        Windows build script (VirtualBox)
variables.pkr.hcl                tunables, PowerShell version/hash
packages.txt                     package list (edit me)
templates/user-data.pkrtpl.hcl   autoinstall (LVM, build-only SSH port 2222)
scripts/05-certs.sh              trust corporate root CAs from ../certs (Zscaler etc.)
scripts/00-base.sh               upgrade, guest tools, grow-root, SSH key regen
scripts/10-packages.sh           installs packages.txt (apt / gh repo / pwsh tarball)
scripts/90-cleanup.sh            generalise: machine-id, host keys, cloud-init, logs, trim
scripts/host/convert-to-raw.sh   arm64: vmdk -> raw .img
scripts/host/package-amd64.sh    x64: qcow2 -> .img, Workstation vmx+vmdk, OVA
files/                           files copied into the image
```

## Using the image

Each clone or flashed copy gets a new machine-id and SSH host keys on first boot. To grow the root volume, enlarge the disk and reboot (`grow-root.service`), or run `sudo grow-root` to grow it immediately.

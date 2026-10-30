# VMware Fusion setup for the Packer build

Checklist for preparing an Apple Silicon Mac running **VMware Fusion Pro 26H1u1 (build 25689522)** so that `packer build` with the `vmware-iso` builder works end to end. Do these once per Mac.

> Why each step matters: Packer drives Fusion through `vmrun`, types the installer boot command over Fusion's VNC console, serves the autoinstall config from a small HTTP server on the Mac, finds the VM's IP in Fusion's NAT DHCP leases, then SSHes in. Every item below unblocks one of those links.

---

## 1. Host requirements

| Item | Requirement | Check |
|---|---|---|
| CPU | Apple Silicon (M1 or later). The guest is arm64 Ubuntu, so the host must be arm64. | `uname -m` → `arm64` |
| Fusion | VMware Fusion **Pro** 26H1u1 in `/Applications` | `"/Applications/VMware Fusion.app/Contents/Library/vmrun" -T fusion list` |
| Free disk | ~100 GB (VM build disk + raw `.img` + Packer cache) | `df -h ~/k8s/packer` |
| RAM | 4 GB for the build VM on top of normal use (8 GB+ host free recommended) | Activity Monitor |
| Internet | The guest downloads from `archive.ubuntu.com`, `ports.ubuntu.com`, `pkgs.k8s.io`, `github.com`, `raw.githubusercontent.com`, `get.helm.sh`, `helm.cilium.io`, `registry.k8s.io`, `quay.io` | Proxies need extra config (ask) |

## 2. First launch of Fusion (one time, GUI)

1. Open **VMware Fusion** from `/Applications` once and accept the licence.
2. When macOS asks, allow the Fusion helper / network components. If you missed it: **System Settings → Privacy & Security**, scroll down and click **Allow** for VMware.
3. **System Settings → Privacy & Security → Accessibility**: enable *VMware Fusion*. (Not strictly required for Packer, but avoids keyboard-capture prompts on the console window.)
4. Quit Fusion. Packer starts VMs itself; leaving the Fusion library window open is fine, but **don't open the build VM manually** while Packer is running it.

## 3. Fusion networking (NAT / vmnet8)

Packer defaults to `network = "nat"` (vmnet8). Confirm it exists and has DHCP enabled:

```bash
cat "/Library/Preferences/VMware Fusion/networking"
# expect lines like:
#   answer VNET_8_DHCP yes
#   answer VNET_8_NAT yes
#   answer VNET_8_HOSTONLY_SUBNET 172.16.x.0
```

Check the vmnet services are running:

```bash
sudo "/Applications/VMware Fusion.app/Contents/Library/vmnet-cli" --status
```

If vmnet8 is missing or stopped:

```bash
sudo "/Applications/VMware Fusion.app/Contents/Library/vmnet-cli" --configure
sudo "/Applications/VMware Fusion.app/Contents/Library/vmnet-cli" --stop
sudo "/Applications/VMware Fusion.app/Contents/Library/vmnet-cli" --start
```

Packer finds the guest IP from Fusion's DHCP leases file; confirm it is readable after a VM has booted at least once:

```bash
ls -l /var/db/vmware/vmnet-dhcpd-vmnet8.leases
```

> **VPN / corporate firewall:** full-tunnel VPN clients often hijack the `172.16.0.0/12` range Fusion NAT uses. Disconnect the VPN for the build, or change the vmnet8 subnet in **Fusion → Settings → Network**.

## 4. macOS privacy & firewall prompts

| Prompt / setting | Action |
|---|---|
| **Local Network** access for your terminal (macOS 15 and later). Packer's SSH connection to the VM counts as local network traffic. | **System Settings → Privacy & Security → Local Network** → enable *Terminal* / *iTerm* / *VS Code* (whichever runs `packer`). |
| **"Do you want the application 'packer' to accept incoming network connections?"** | Click **Allow**. The VM fetches its autoinstall config from Packer's HTTP server on ports 8000–9000. |
| Application firewall in *Block all incoming connections* mode | Turn that off for the build, or add `packer` to the allowed apps (**System Settings → Network → Firewall → Options**). |
| Homebrew `packer` binary blocked by Gatekeeper | `xattr -d com.apple.quarantine "$(which packer)"` |

## 5. Tools to install on the Mac

```bash
# Homebrew (skip if present): https://brew.sh
brew tap hashicorp/tap
brew install hashicorp/tap/packer      # Packer >= 1.11
brew install qemu                       # provides qemu-img for the .vmdk -> .img conversion
```

Optional:

```bash
# ovftool ships inside Fusion; only needed if you later switch format to "ova".
ls "/Applications/VMware Fusion.app/Contents/Library/VMware OVF Tool/ovftool"
```

Install the Packer VMware plugin (done automatically by `./build.sh`, which runs `packer init .`):

```bash
cd ~/k8s/packer && packer init .
packer plugins installed     # should list github.com/hashicorp/vmware
```

## 6. Repo-local settings

```bash
cd ~/k8s/packer
cp local.auto.pkrvars.hcl.example local.auto.pkrvars.hcl   # git-ignored
# edit build_password and (optionally) ssh_authorized_key
```

Confirm the ISO is where the template expects it:

```bash
ls -l iso/ubuntu-24.04.5-live-server-arm64.iso
shasum -a 256 iso/ubuntu-24.04.5-live-server-arm64.iso
# f12484464c7d4d73e2167e0a7dbda1e669f8fae9bcf778dc0944937034b320cb
```

Cross-check that hash against Ubuntu's published list at
<https://cdimage.ubuntu.com/releases/24.04.5/release/SHA256SUMS>.

## 7. First build

```bash
./build.sh validate   # packer init + fmt check + validate
./build.sh            # full build (≈ 20–40 min)
```

Leave `headless = false` for the first run so the Fusion console shows the boot command being typed and the installer progress. Once it works, set `headless = true` in `local.auto.pkrvars.hcl`.

## 8. Troubleshooting quick reference

| Symptom | Likely cause → fix |
|---|---|
| VM sits at the GRUB menu; boot command never typed | USB controller absent → template sets `usb = true`; keep it. Also check nothing else uses ports 5900–6000 (Screen Sharing). |
| Installer starts but stops at the language screen (no autoinstall) | VM can't reach Packer's HTTP server → allow `packer` in the firewall (step 4); disconnect VPN. In the console press `Alt+F2` and `curl http://<HTTPIP>:<port>/user-data`. |
| `Waiting for SSH...` forever, the console shows `k8s-node login:`, and the log keeps dialling one IP with `i/o timeout` / `host is down` | Packer locked onto the **installer's** IP before the reboot. The template stops the installer's sshd in `early-commands`; if it still happens, check `/var/db/vmware/vmnet-dhcpd-vmnet8.leases` for a second lease for the VM's MAC address. |
| `Waiting for SSH to become available...` forever | Guest IP not found or SSH blocked → Local Network permission (step 4); check the leases file (step 3); the NIC name must match `e*`. |
| `Error: vmrun not found` / `Fusion not found` | Fusion not in `/Applications` → set `fusion_app_path` in `local.auto.pkrvars.hcl`. |
| `output directory already exists` | Delete `output/<vm_name>` from a previous run, or run `packer build -force .`. |
| Downloads fail inside the guest (`curl: (6)`) | NAT DNS/egress issue or proxy → test `ping ports.ubuntu.com` from the VM console. |
| `qemu-img: command not found` at the end | `brew install qemu`, or set `create_raw_image = false`. |

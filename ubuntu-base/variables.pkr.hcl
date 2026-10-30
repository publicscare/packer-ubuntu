# ===========================================================================
# Variables for the stock Ubuntu 24.04.5 arm64 base image.
# Override in local.auto.pkrvars.hcl (git-ignored) or with -var.
# ===========================================================================

# --- Installer ISO (shared with the Kubernetes template in ../iso) ----------
variable "iso_path" {
  type        = string
  description = "Path to the Ubuntu live-server arm64 ISO, relative to this folder or absolute."
  default     = "../iso/ubuntu-24.04.5-live-server-arm64.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:f12484464c7d4d73e2167e0a7dbda1e669f8fae9bcf778dc0944937034b320cb"
}

# --- VMware Fusion VM shape -------------------------------------------------
variable "fusion_app_path" {
  type    = string
  default = "/Applications/VMware Fusion.app"
}

variable "headless" {
  type    = bool
  default = false
}

variable "cpus" {
  type    = number
  default = 2
}

variable "memory_mb" {
  type    = number
  default = 4096
}

variable "disk_size_mb" {
  type        = number
  description = "System disk size in MB. Also the size of the raw .img produced."
  default     = 40960
}

variable "hardware_version" {
  type    = number
  default = 21
}

variable "network" {
  type    = string
  default = "nat"
}

variable "network_adapter_type" {
  type    = string
  default = "e1000e"
}

# --- Naming -------------------------------------------------------------------
variable "image_date" {
  type        = string
  description = "Date stamp in output names (template-<date>-ubuntu-...). Empty = today's date in UTC. Set it to rebuild a given release, e.g. 2026-11-01."
  default     = ""
  validation {
    condition     = var.image_date == "" || can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.image_date))
    error_message = "The image_date must be empty or in YYYY-MM-DD form."
  }
}

variable "name_prefix" {
  type        = string
  description = "Text before the date in output names."
  default     = "template"
}

# --- Guest identity used during the build -----------------------------------
variable "hostname" {
  type    = string
  default = "ubuntu-base"
}

variable "timezone" {
  type    = string
  default = "Etc/UTC"
}

variable "build_username" {
  type    = string
  default = "ubuntu"
}

variable "build_password" {
  type        = string
  description = "Password for build_username. Change it in local.auto.pkrvars.hcl."
  default     = "ChangeMe-Packer!"
  sensitive   = true
  validation {
    condition     = var.build_password != "use-a-long-unique-password" && length(var.build_password) >= 8
    error_message = "The build_password is still the example placeholder (or shorter than 8 characters). Set your own in local.auto.pkrvars.hcl."
  }
}

variable "ssh_authorized_key" {
  type        = string
  description = "Optional public key for build_username. When set, SSH password login is disabled in the final image."
  default     = ""
  validation {
    condition     = var.ssh_authorized_key == "" || can(regex("^(ssh-(ed25519|rsa)|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\\.com) [A-Za-z0-9+/]{40,}={0,3}( .*)?$", var.ssh_authorized_key))
    error_message = "The ssh_authorized_key must be a real public key (e.g. the contents of ~/.ssh/id_ed25519.pub) or empty. The example placeholder would lock you out of SSH."
  }
}

variable "ssh_build_port" {
  type        = number
  description = "Extra sshd port used only during the build so Packer never connects to the live installer's sshd. Removed by 90-cleanup.sh."
  default     = 2222
}

# --- Packages ---------------------------------------------------------------
variable "packages_file" {
  type        = string
  description = "Package list installed by scripts/10-packages.sh (one per line)."
  default     = "packages.txt"
}

variable "powershell_version" {
  type    = string
  default = "7.6.6"
}

variable "powershell_sha256" {
  type        = string
  description = "(arm64) SHA-256 of powershell-<version>-linux-arm64.tar.gz from the GitHub release page. Update together with powershell_version."
  default     = "924829e54c983648f6f1419a2dc7f9433c861b2fb5bd57736ff096c24f133729"
}

variable "powershell_sha256_amd64" {
  type        = string
  description = "SHA-256 of powershell-<version>-linux-x64.tar.gz. Update together with powershell_version."
  default     = "ddbc4a2d113bbd46d283cfedcbcd117a70caefd7673f41f2b4e0000badf103bc"
}

variable "yq_version" {
  type        = string
  description = "mikefarah/yq release, installed when packages.txt lists yq."
  default     = "4.54.1"
}

variable "yq_sha256_arm64" {
  type        = string
  description = "SHA-256 of yq_linux_arm64 (release 'checksums' file, SHA-256 column). Update with yq_version."
  default     = "189088da0c6429ec5178dfaab1a114805f6cab0b61b165ab236efedf1d57a71b"
}

variable "yq_sha256_amd64" {
  type        = string
  description = "SHA-256 of yq_linux_amd64. Update with yq_version."
  default     = "8e34fc298390875de416e6a4afcb8cabeceb25d9aa8506c1a2f9353cf702ea5f"
}

# --- amd64 (x64) build with QEMU --------------------------------------------
variable "iso_urls_amd64" {
  type        = list(string)
  description = "Tried in order: a local copy in ../iso, then Ubuntu's server (Packer caches the download in packer_cache/)."
  default = [
    "../iso/ubuntu-24.04.5-live-server-amd64.iso",
    "https://releases.ubuntu.com/24.04.5/ubuntu-24.04.5-live-server-amd64.iso",
  ]
}

variable "iso_checksum_amd64" {
  type        = string
  description = "Verified against Ubuntu's published list. If 24.04.5 moves to old-releases.ubuntu.com, update this and iso_urls_amd64."
  default     = "file:https://releases.ubuntu.com/24.04.5/SHA256SUMS"
}

variable "qemu_binary_amd64" {
  type    = string
  default = "qemu-system-x86_64"
}

variable "qemu_accelerator" {
  type        = string
  description = "tcg = software emulation (Apple Silicon Mac, slow). kvm = native on an x86 Linux host."
  default     = "tcg"
}

variable "qemu_cpu_model" {
  type        = string
  description = "max under tcg; use host with kvm."
  default     = "max"
}

variable "qemu_efi_code" {
  type        = string
  description = "x64 UEFI firmware. Homebrew QEMU path; on Ubuntu hosts use /usr/share/OVMF/OVMF_CODE_4M.fd."
  default     = "/opt/homebrew/share/qemu/edk2-x86_64-code.fd"
}

variable "qemu_efi_vars" {
  type        = string
  description = "UEFI variable store template. On Ubuntu hosts use /usr/share/OVMF/OVMF_VARS_4M.fd."
  default     = "/opt/homebrew/share/qemu/edk2-i386-vars.fd"
}

variable "qemu_display" {
  type        = string
  description = "QEMU window backend when headless = false: cocoa on macOS, gtk or sdl on Linux desktops."
  default     = "cocoa"
}

variable "qemu_boot_wait" {
  type    = string
  default = "5s"
}

variable "qemu_ssh_timeout" {
  type        = string
  description = "The unattended install under emulation is slow; allow plenty of time."
  default     = "4h"
}

variable "ovftool_path" {
  type        = string
  description = "ovftool used to build the x64 OVA. Ships inside VMware Fusion / Workstation."
  default     = "/Applications/VMware Fusion.app/Contents/Library/VMware OVF Tool/ovftool"
}

# --- amd64 (x64) build with VirtualBox ---------------------------------------
variable "vbox_guest_os_type" {
  type        = string
  description = "VirtualBox OS type (VBoxManage list ostypes). Ubuntu_64 works on every 7.x release."
  default     = "Ubuntu_64"
}

variable "vbox_nic_type" {
  type        = string
  description = "82540EM (Intel PRO/1000, most compatible) or virtio (faster)."
  default     = "82540EM"
}

variable "vbox_keep_registered" {
  type        = bool
  description = "Leave the built VM registered in VirtualBox Manager (in addition to the OVA)."
  default     = false
}

# --- Corporate certificates ---------------------------------------------------
variable "certs_dir" {
  type        = string
  description = "Folder (relative to this one) with corporate root CAs to trust in the guest, e.g. zscaler-ca.crt. Contents are git-ignored."
  default     = "../certs"
}

# --- Outputs ----------------------------------------------------------------
variable "create_raw_image" {
  type    = bool
  default = true
}

# ===========================================================================
# Variables for the Ubuntu 24.04.5 arm64 Kubernetes + Cilium node image.
# Override any of these in local.auto.pkrvars.hcl (git-ignored) or with -var.
# ===========================================================================

# --- Installer ISO ----------------------------------------------------------
variable "iso_path" {
  type        = string
  description = "Path to the Ubuntu live-server arm64 ISO, relative to this folder or absolute."
  default     = "iso/ubuntu-24.04.5-live-server-arm64.iso"
}

variable "iso_checksum" {
  type        = string
  description = "Checksum of the ISO. Computed from the local copy on 2026-10-30; compare with Ubuntu's published SHA256SUMS."
  default     = "sha256:f12484464c7d4d73e2167e0a7dbda1e669f8fae9bcf778dc0944937034b320cb"
}

# --- VMware Fusion VM shape -------------------------------------------------
variable "fusion_app_path" {
  type        = string
  description = "Location of VMware Fusion.app (only change for a non-default install)."
  default     = "/Applications/VMware Fusion.app"
}

variable "headless" {
  type        = bool
  description = "Run without the Fusion console window. Leave false for the first build so you can watch the installer."
  default     = false
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
  type        = number
  description = "VMware virtual hardware version (plugin minimum 19)."
  default     = 21
}

variable "network" {
  type        = string
  description = "Fusion network for the build VM: nat (vmnet8), hostonly (vmnet1) or bridged."
  default     = "nat"
}

variable "network_adapter_type" {
  type        = string
  description = "NIC model. e1000e is the safest on Apple Silicon; vmxnet3 also works on recent Fusion."
  default     = "e1000e"
}

# --- Guest identity used during the build -----------------------------------
variable "hostname" {
  type    = string
  default = "k8s-node"
}

variable "timezone" {
  type    = string
  default = "Etc/UTC"
}

variable "build_username" {
  type        = string
  description = "Admin user created in the image; Packer connects as this user."
  default     = "k8sadmin"
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

variable "ssh_build_port" {
  type        = number
  description = "Extra sshd port opened only during the build. Packer connects here, so it can never latch onto the live installer's sshd (port 22). Removed by 90-cleanup.sh."
  default     = 2222
}

variable "ssh_authorized_key" {
  type        = string
  description = "Optional public key added to build_username. When set, SSH password login is disabled in the final image."
  default     = ""
  validation {
    condition     = var.ssh_authorized_key == "" || can(regex("^(ssh-(ed25519|rsa)|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\\.com) [A-Za-z0-9+/]{40,}={0,3}( .*)?$", var.ssh_authorized_key))
    error_message = "The ssh_authorized_key must be a real public key (e.g. the contents of ~/.ssh/id_ed25519.pub) or empty. The example placeholder would lock you out of SSH."
  }
}

# --- Software versions (pinned) ---------------------------------------------
variable "kubernetes_version" {
  type        = string
  description = "Kubernetes patch version without the leading v. Cilium 1.20 is e2e-tested on 1.33-1.36."
  default     = "1.36.5"
}

variable "cilium_version" {
  type    = string
  default = "1.20.4"
}

variable "cilium_cli_version" {
  type    = string
  default = "0.19.7"
}

variable "containerd_version" {
  type    = string
  default = "2.3.4"
}

variable "runc_version" {
  type    = string
  default = "1.5.1"
}

variable "helm_version" {
  type    = string
  default = "3.22.1"
}

# --- Outputs ----------------------------------------------------------------
variable "create_raw_image" {
  type        = bool
  description = "Convert the finished VMDK into a raw .img (needs qemu-img on the Mac)."
  default     = true
}

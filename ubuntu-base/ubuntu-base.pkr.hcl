# ===========================================================================
# Stock Ubuntu 24.04.5 base image, two architectures
#
#   arm64  vmware-iso.ubuntu-base       VMware Fusion Pro on Apple Silicon
#   amd64  qemu.ubuntu-base-amd64       QEMU (TCG on a Mac, KVM on x86 Linux)
#                                       -> see sources-amd64-qemu.pkr.hcl
#   amd64  virtualbox-iso.ubuntu-base-vbox  VirtualBox on x86 Windows/Linux
#                                       -> see sources-amd64-virtualbox.pkr.hcl
#                                          (Windows: run Build.ps1)
#
# Both run the same provisioning: packages from packages.txt (minimum
# ca-certificates, git, gh, PowerShell), LVM root with grow-root, generalised
# for cloning. Pick one with build.sh (arm64 | amd64 | all).
#
# Outputs (artifacts/):
#   arm64  <name>.img (+ output/<name>/ Fusion VM)
#   amd64  <name>.img, <name>-workstation/ (vmx+vmdk), <name>.ova
#   both   manifest.json, *.sha256
# ===========================================================================

packer {
  required_version = ">= 1.11.0"

  required_plugins {
    vmware = {
      source  = "github.com/hashicorp/vmware"
      version = ">= 2.1.6"
    }
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = ">= 1.1.0"
    }
    virtualbox = {
      source  = "github.com/hashicorp/virtualbox"
      version = ">= 1.1.0"
    }
  }
}

locals {
  # template-YYYY-MM-DD-ubuntu-24.04.5-base-<arch>: sorts by date, one per
  # monthly rebuild. timestamp() is UTC; set image_date to pin/override it.
  image_date       = var.image_date != "" ? var.image_date : formatdate("YYYY-MM-DD", timestamp())
  name_prefix      = "${var.name_prefix}-${local.image_date}"
  vm_name_arm64    = "${local.name_prefix}-ubuntu-24.04.5-base-arm64"
  vm_name_amd64    = "${local.name_prefix}-ubuntu-24.04.5-base-amd64"
  output_dir_arm64 = "${path.root}/output/${local.vm_name_arm64}"
  output_dir_amd64 = "${path.root}/output/${local.vm_name_amd64}"
  vm_name_vbox     = "${local.name_prefix}-ubuntu-24.04.5-base-amd64-virtualbox"
  output_dir_vbox  = "${path.root}/output/${local.vm_name_vbox}"
  artifacts_dir    = "${path.root}/artifacts"
  iso_url_arm64    = abspath(substr(var.iso_path, 0, 1) == "/" ? var.iso_path : "${path.root}/${var.iso_path}")
  stage_dir        = "/var/tmp/ubuntu-base" # survives the mid-build reboot; /tmp does not

  # Autoinstall served over Packer's HTTP server (same for both architectures).
  http_content = {
    "/user-data" = templatefile("${path.root}/templates/user-data.pkrtpl.hcl", {
      hostname           = var.hostname
      timezone           = var.timezone
      username           = var.build_username
      password           = var.build_password
      ssh_authorized_key = var.ssh_authorized_key
      ssh_build_port     = var.ssh_build_port
    })
    "/meta-data" = "instance-id: ubuntu-base-build\nlocal-hostname: ${var.hostname}\n"
  }

  provision_env = [
    "DEBIAN_FRONTEND=noninteractive",
    "STAGE_DIR=${local.stage_dir}",
    "POWERSHELL_VERSION=${var.powershell_version}",
    "POWERSHELL_SHA256_ARM64=${var.powershell_sha256}",
    "POWERSHELL_SHA256_AMD64=${var.powershell_sha256_amd64}",
    "YQ_VERSION=${var.yq_version}",
    "YQ_SHA256_ARM64=${var.yq_sha256_arm64}",
    "YQ_SHA256_AMD64=${var.yq_sha256_amd64}",
    "BUILD_USERNAME=${var.build_username}",
    "DISABLE_PASSWORD_SSH=${var.ssh_authorized_key != "" ? "true" : "false"}",
  ]
  # Scripts need the variables above: {{ .Vars }} must be in the command.
  # Packer also adds PACKER_BUILDER_TYPE (vmware-iso / qemu) to .Vars.
  sudo_execute = "chmod +x {{ .Path }}; sudo env {{ .Vars }} bash '{{ .Path }}'"
}

# --- arm64: VMware Fusion on Apple Silicon -----------------------------------
source "vmware-iso" "ubuntu-base" {
  fusion_app_path      = var.fusion_app_path
  vm_name              = local.vm_name_arm64
  output_directory     = local.output_dir_arm64
  guest_os_type        = "arm-ubuntu-64"
  version              = var.hardware_version
  firmware             = "efi"
  headless             = var.headless
  cpus                 = var.cpus
  cores                = var.cpus
  memory               = var.memory_mb
  usb                  = true # Apple Silicon: needed for keyboard input to reach the VM
  network              = var.network
  network_adapter_type = var.network_adapter_type
  cdrom_adapter_type   = "sata"
  disk_adapter_type    = "nvme"
  disk_size            = var.disk_size_mb
  disk_type_id         = "0"
  vmdk_name            = "disk"
  format               = "vmx"
  tools_mode           = "disable"

  vmx_data = {
    "annotation" = "Ubuntu 24.04.5 arm64 base image"
  }

  iso_url      = local.iso_url_arm64
  iso_checksum = var.iso_checksum

  http_content = local.http_content

  boot_wait = "5s"
  boot_command = [
    "c<wait3>",
    "linux /casper/vmlinuz autoinstall ds='nocloud;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/' ---<enter><wait3>",
    "initrd /casper/initrd<enter><wait5>",
    "boot<enter>",
  ]

  # Packer only talks to the installed system on the build-only port, never to
  # the live installer's sshd on 22 (whose IP it would otherwise cache).
  communicator           = "ssh"
  ssh_port               = var.ssh_build_port
  ssh_username           = var.build_username
  ssh_password           = var.build_password
  ssh_timeout            = "60m"
  ssh_handshake_attempts = 500

  shutdown_command = "sudo shutdown -P now"
  shutdown_timeout = "10m"
}

build {
  name = "ubuntu-base"
  sources = [
    "source.vmware-iso.ubuntu-base",
    "source.qemu.ubuntu-base-amd64",
    "source.virtualbox-iso.ubuntu-base-vbox",
  ]

  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to finish...'",
      "sudo cloud-init status --wait || true",
      "mkdir -p ${local.stage_dir}/certs",
    ]
  }

  provisioner "file" {
    source      = "${path.root}/files/"
    destination = local.stage_dir
  }

  provisioner "file" {
    source      = "${path.root}/${var.packages_file}"
    destination = "${local.stage_dir}/packages.txt"
  }

  # Corporate root CAs (../certs, git-ignored) go in first, so every later
  # HTTPS download works behind Zscaler / TLS inspection.
  provisioner "file" {
    source      = "${path.root}/${var.certs_dir}/"
    destination = "${local.stage_dir}/certs"
  }

  provisioner "shell" {
    environment_vars = local.provision_env
    execute_command  = local.sudo_execute
    scripts = [
      "${path.root}/scripts/05-certs.sh",
      "${path.root}/scripts/00-base.sh",
    ]
  }

  provisioner "shell" {
    inline            = ["sudo systemctl reboot"]
    expect_disconnect = true
  }

  provisioner "shell" {
    pause_before     = "30s"
    environment_vars = local.provision_env
    execute_command  = local.sudo_execute
    scripts = [
      "${path.root}/scripts/10-packages.sh",
      "${path.root}/scripts/90-cleanup.sh",
    ]
  }

  # --- Post-processing on the build host (run in order) ----------------------
  post-processor "shell-local" {
    only = ["vmware-iso.ubuntu-base"]
    environment_vars = [
      "CREATE_RAW_IMAGE=${var.create_raw_image}",
      "VM_OUTPUT_DIR=${local.output_dir_arm64}",
      "ARTIFACTS_DIR=${local.artifacts_dir}",
      "IMAGE_NAME=${local.vm_name_arm64}",
    ]
    script = "${path.root}/scripts/host/convert-to-raw.sh"
  }

  post-processor "shell-local" {
    only = ["qemu.ubuntu-base-amd64"]
    environment_vars = [
      "QEMU_OUTPUT_DIR=${local.output_dir_amd64}",
      "ARTIFACTS_DIR=${local.artifacts_dir}",
      "IMAGE_NAME=${local.vm_name_amd64}",
      "CPUS=${var.cpus}",
      "MEMORY_MB=${var.memory_mb}",
      "OVFTOOL=${var.ovftool_path}",
    ]
    script = "${path.root}/scripts/host/package-amd64.sh"
  }

  post-processor "manifest" {
    output     = "${local.artifacts_dir}/manifest.json"
    strip_path = false
    custom_data = {
      image_date         = local.image_date
      powershell_version = var.powershell_version
      yq_version         = var.yq_version
    }
  }
}

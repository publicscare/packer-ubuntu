# ===========================================================================
# Ubuntu 24.04.5 (arm64) Kubernetes node image with Cilium
# Builder : VMware Fusion Pro (Apple Silicon) via the vmware-iso builder
# Outputs : output/<vm_name>/        VMware VM template (vmx + monolithic vmdk)
#           artifacts/<vm_name>.img  raw disk image converted with qemu-img
#           artifacts/manifest.json  Packer build manifest
# ===========================================================================

packer {
  required_version = ">= 1.11.0"

  required_plugins {
    vmware = {
      source  = "github.com/hashicorp/vmware"
      version = ">= 2.1.6"
    }
  }
}

locals {
  arch          = "arm64"
  k8s_minor     = join(".", slice(split(".", var.kubernetes_version), 0, 2))
  vm_name       = "ubuntu-24.04.5-k8s-${var.kubernetes_version}-cilium-${var.cilium_version}-${local.arch}"
  output_dir    = "${path.root}/output/${local.vm_name}"
  artifacts_dir = "${path.root}/artifacts"

  # Absolute path for the ISO so Packer resolves it the same way from any cwd.
  iso_url = abspath(substr(var.iso_path, 0, 1) == "/" ? var.iso_path : "${path.root}/${var.iso_path}")

  # Environment shared by every provisioning script.
  provision_env = [
    "DEBIAN_FRONTEND=noninteractive",
    "K8S_VERSION=${var.kubernetes_version}",
    "K8S_MINOR=${local.k8s_minor}",
    "CILIUM_VERSION=${var.cilium_version}",
    "CILIUM_CLI_VERSION=${var.cilium_cli_version}",
    "CONTAINERD_VERSION=${var.containerd_version}",
    "RUNC_VERSION=${var.runc_version}",
    "HELM_VERSION=${var.helm_version}",
    "BUILD_USERNAME=${var.build_username}",
    "DISABLE_PASSWORD_SSH=${var.ssh_authorized_key != "" ? "true" : "false"}",
    "IMAGE_NAME=${local.vm_name}",
  ]
}

source "vmware-iso" "ubuntu-k8s" {
  # --- Fusion / VM definition ----------------------------------------------
  fusion_app_path      = var.fusion_app_path
  vm_name              = local.vm_name
  output_directory     = local.output_dir
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
  disk_type_id         = "0" # single growable vmdk: easy to convert to a raw .img
  vmdk_name            = "disk"
  format               = "vmx"
  tools_mode           = "disable" # open-vm-tools comes from Ubuntu's apt repo instead

  vmx_data = {
    "annotation" = "Ubuntu 24.04.5 arm64 | Kubernetes ${var.kubernetes_version} | Cilium ${var.cilium_version}"
  }

  # --- Installer ISO ---------------------------------------------------------
  iso_url      = local.iso_url
  iso_checksum = var.iso_checksum

  # --- Autoinstall (cloud-init NoCloud over Packer's HTTP server) ------------
  http_content = {
    "/user-data" = templatefile("${path.root}/templates/user-data.pkrtpl.hcl", {
      hostname           = var.hostname
      timezone           = var.timezone
      username           = var.build_username
      password           = var.build_password
      ssh_authorized_key = var.ssh_authorized_key
      ssh_build_port     = var.ssh_build_port
    })
    "/meta-data" = "instance-id: ${local.vm_name}\nlocal-hostname: ${var.hostname}\n"
  }

  # The arm64 ISO boots straight into GRUB. Drop to the GRUB prompt and boot the
  # installer kernel with autoinstall pointed at Packer's HTTP server.
  boot_wait = "5s"
  boot_command = [
    "c<wait3>",
    "linux /casper/vmlinuz autoinstall ds='nocloud;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/' ---<enter><wait3>",
    "initrd /casper/initrd<enter><wait5>",
    "boot<enter>",
  ]

  # --- Communicator ----------------------------------------------------------
  # The live installer runs its own sshd on port 22. If Packer reaches it, the
  # plugin caches that IP and never re-reads the DHCP leases, but the installed
  # system comes up on a different lease. The installed system therefore also
  # listens on ssh_build_port during the build, and Packer only uses that port.
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
  name    = "ubuntu-k8s"
  sources = ["source.vmware-iso.ubuntu-k8s"]

  # Wait until cloud-init (first boot of the installed system) has finished.
  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to finish...'",
      "sudo cloud-init status --wait || true",
    ]
  }

  # Stage config files and helper scripts that end up inside the image.
  provisioner "shell" {
    inline = ["mkdir -p /var/tmp/k8s-image"]
  }

  provisioner "file" {
    source      = "${path.root}/files/"
    destination = "/var/tmp/k8s-image"
  }

  # OS baseline, then reboot onto the updated kernel.
  provisioner "shell" {
    environment_vars = local.provision_env
    execute_command  = "chmod +x {{ .Path }}; sudo env {{ .Vars }} bash '{{ .Path }}'"
    script           = "${path.root}/scripts/00-base.sh"
  }

  provisioner "shell" {
    inline            = ["sudo systemctl reboot"]
    expect_disconnect = true
  }

  # Container runtime, Kubernetes, Cilium, node helpers, then image cleanup.
  provisioner "shell" {
    pause_before     = "30s"
    environment_vars = local.provision_env
    execute_command  = "chmod +x {{ .Path }}; sudo env {{ .Vars }} bash '{{ .Path }}'"
    scripts = [
      "${path.root}/scripts/10-containerd.sh",
      "${path.root}/scripts/20-kubernetes.sh",
      "${path.root}/scripts/30-cilium.sh",
      "${path.root}/scripts/40-node-helpers.sh",
      "${path.root}/scripts/90-cleanup.sh",
    ]
  }

  # --- Post-processing on the Mac ---------------------------------------------
  # Runs in order: the raw-image script creates artifacts/, then the manifest
  # is written into it.
  post-processor "shell-local" {
    environment_vars = [
      "CREATE_RAW_IMAGE=${var.create_raw_image}",
      "VM_OUTPUT_DIR=${local.output_dir}",
      "ARTIFACTS_DIR=${local.artifacts_dir}",
      "IMAGE_NAME=${local.vm_name}",
    ]
    script = "${path.root}/scripts/host/convert-to-raw.sh"
  }

  post-processor "manifest" {
    output     = "${local.artifacts_dir}/manifest.json"
    strip_path = false
    custom_data = {
      kubernetes_version = var.kubernetes_version
      cilium_version     = var.cilium_version
      containerd_version = var.containerd_version
      architecture       = local.arch
    }
  }
}

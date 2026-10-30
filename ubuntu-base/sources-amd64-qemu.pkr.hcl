# ===========================================================================
# x64 (amd64) build with QEMU.
#
# On an Apple Silicon Mac this runs under TCG software emulation: it works but
# is slow (expect an hour or more). On an x86 Linux host with /dev/kvm, set
# qemu_accelerator = "kvm" and it runs at native speed.
#
# The result is one provider-neutral disk. scripts/host/package-amd64.sh turns
# it into a raw .img, a VMware Workstation VM (vmx + vmdk) and an OVA for
# vSphere / VirtualBox. The image carries open-vm-tools, VirtualBox guest
# utilities and qemu-guest-agent; only the one matching the hypervisor starts.
# ===========================================================================

source "qemu" "ubuntu-base-amd64" {
  qemu_binary  = var.qemu_binary_amd64
  accelerator  = var.qemu_accelerator
  machine_type = "q35"
  cpu_model    = var.qemu_cpu_model
  cpus         = var.cpus
  memory       = var.memory_mb

  disk_size          = "${var.disk_size_mb}M"
  format             = "qcow2"
  disk_interface     = "virtio"
  net_device         = "virtio-net"
  disk_discard       = "unmap"
  disk_detect_zeroes = "unmap"
  # Upstream qemu-img convert can corrupt images on macOS; skip Packer's
  # compaction and let package-amd64.sh do the conversions.
  skip_compaction  = true
  disk_compression = false

  efi_boot          = true
  efi_firmware_code = var.qemu_efi_code
  efi_firmware_vars = var.qemu_efi_vars
  efi_drop_efivars  = true

  vm_name          = "${local.vm_name_amd64}.qcow2"
  output_directory = local.output_dir_amd64
  # Packer always gives QEMU a VNC console (127.0.0.1:59xx, see the build log).
  # With VNC on, QEMU opens no window unless a display is named explicitly:
  # Homebrew QEMU on macOS has Cocoa (not GTK). Ignored when headless = true.
  headless = var.headless
  display  = var.qemu_display

  # Local copy first (drop the ISO in ../iso to skip the download), then
  # Ubuntu's server. Checked against Ubuntu's published SHA256SUMS.
  iso_urls     = var.iso_urls_amd64
  iso_checksum = var.iso_checksum_amd64

  http_content = local.http_content

  # Under emulation, OVMF takes an unpredictable time to reach GRUB. Arrow
  # presses stop GRUB's 30 s countdown whenever the menu appears (and are
  # ignored before then), then "c" opens the GRUB prompt.
  boot_wait = var.qemu_boot_wait
  boot_command = [
    # 18 presses x 5 s: covers GRUB appearing anywhere in the first ~90 s.
    "<up><wait5><up><wait5><up><wait5><up><wait5><up><wait5><up><wait5>",
    "<up><wait5><up><wait5><up><wait5><up><wait5><up><wait5><up><wait5>",
    "<up><wait5><up><wait5><up><wait5><up><wait5><up><wait5><up><wait5>",
    "c<wait5>",
    "linux /casper/vmlinuz autoinstall ds='nocloud;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/' ---<enter><wait5>",
    "initrd /casper/initrd<enter><wait10>",
    "boot<enter>",
  ]

  # User-mode networking: Packer forwards a host port to the guest's build-only
  # sshd port, so it never reaches the installer's sshd on 22.
  communicator           = "ssh"
  ssh_port               = var.ssh_build_port
  ssh_username           = var.build_username
  ssh_password           = var.build_password
  ssh_timeout            = var.qemu_ssh_timeout
  ssh_handshake_attempts = 500

  shutdown_command = "sudo shutdown -P now"
  shutdown_timeout = "30m"
}

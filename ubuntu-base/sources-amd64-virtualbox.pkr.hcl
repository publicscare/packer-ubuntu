# ===========================================================================
# x64 (amd64) build with VirtualBox, for x86 Windows / Linux / Intel Mac hosts.
# Output: an OVA (artifacts/ after Build.ps1), importable into VirtualBox,
# vSphere or Workstation.
#
# Corporate networks: put root CAs (e.g. zscaler-ca.crt) in ../certs/. They are
# trusted inside the guest before anything is downloaded over HTTPS.
# ===========================================================================

source "virtualbox-iso" "ubuntu-base-vbox" {
  guest_os_type            = var.vbox_guest_os_type
  firmware                 = "efi"
  chipset                  = "ich9"
  cpus                     = var.cpus
  memory                   = var.memory_mb
  disk_size                = var.disk_size_mb
  hard_drive_interface     = "sata"
  iso_interface            = "sata"
  hard_drive_nonrotational = true
  hard_drive_discard       = true
  nic_type                 = var.vbox_nic_type
  gfx_controller           = "vmsvga"
  gfx_vram_size            = 16
  rtc_time_base            = "UTC"
  # Guest utilities come from Ubuntu's apt repo (scripts/00-base.sh).
  guest_additions_mode = "disable"

  vm_name          = local.vm_name_vbox
  output_directory = local.output_dir_vbox
  format           = "ova"
  keep_registered  = var.vbox_keep_registered
  headless         = var.headless

  vboxmanage = [
    # VirtualBox 7 blocks NAT access to the host's loopback by default. Packer's
    # HTTP server (autoinstall config) is reached at 10.0.2.2, which maps there.
    ["modifyvm", "{{ .Name }}", "--nat-localhostreachable1", "on"],
  ]

  # Local copy first (drop the ISO in ../iso to skip the download), then
  # Ubuntu's server, checked against Ubuntu's published SHA256SUMS.
  iso_urls     = var.iso_urls_amd64
  iso_checksum = var.iso_checksum_amd64

  http_content = local.http_content

  # Arrow presses stop GRUB's countdown whenever the menu appears (and are
  # ignored before then); "c" then opens the GRUB prompt.
  boot_wait = "5s"
  boot_command = [
    "<up><wait3><up><wait3><up><wait3><up><wait3><up><wait3>",
    "<up><wait3><up><wait3><up><wait3><up><wait3><up><wait3>",
    "c<wait3>",
    "linux /casper/vmlinuz autoinstall ds='nocloud;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/' ---<enter><wait3>",
    "initrd /casper/initrd<enter><wait5>",
    "boot<enter>",
  ]

  # NAT port forward from the host to the guest's build-only sshd port, so
  # Packer never reaches the live installer's sshd on 22.
  communicator           = "ssh"
  ssh_port               = var.ssh_build_port
  ssh_username           = var.build_username
  ssh_password           = var.build_password
  ssh_timeout            = "90m" # VirtualBox on top of Hyper-V (VBS) is slower
  ssh_handshake_attempts = 500

  shutdown_command = "sudo shutdown -P now"
  shutdown_timeout = "15m"
}

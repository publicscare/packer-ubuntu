#cloud-config
# Ubuntu Server autoinstall (Subiquity). Rendered by Packer's templatefile().
autoinstall:
  version: 1
  locale: en_US.UTF-8
  keyboard:
    layout: us
  timezone: ${timezone}
  refresh-installer:
    update: false
  source:
    id: ubuntu-server
  network:
    version: 2
    ethernets:
      primary:
        # Matches ens160 under Fusion and enp*/eth* on other arm64 hardware.
        match:
          name: "e*"
        dhcp4: true
        dhcp-identifier: mac
  storage:
    # GPT: ESP + /boot + LVM PV. VG "ubuntu-vg", root LV "ubuntu-lv" (ext4).
    # sizing-policy "all" gives the root LV the whole VG instead of Subiquity's
    # default of half. Grow later with k8s-grow-root (growpart+pvresize+lvextend).
    layout:
      name: lvm
      sizing-policy: all
    swap:
      size: 0
  ssh:
    install-server: true
    allow-pw: true
  packages:
    - open-vm-tools
    - cloud-guest-utils
  updates: security
  shutdown: reboot
  late-commands:
    - echo '${username} ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/90-${username}
    - chmod 0440 /target/etc/sudoers.d/90-${username}
  # cloud-init config applied on the first boot of the installed system.
  user-data:
    hostname: ${hostname}
    preserve_hostname: false
    ssh_pwauth: true
    users:
      - name: ${username}
        gecos: Kubernetes admin
        groups: [adm, sudo]
        shell: /bin/bash
        lock_passwd: false
        plain_text_passwd: ${jsonencode(password)}
%{ if ssh_authorized_key != "" ~}
        ssh_authorized_keys:
          - ${jsonencode(ssh_authorized_key)}
%{ endif ~}

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
  # The live installer runs its own sshd. If Packer connects to it, the plugin
  # caches that IP and keeps retrying it after the reboot, even though the
  # installed system gets a new DHCP lease. Stop it so Packer only sees the
  # installed system.
  early-commands:
    - systemctl stop ssh.socket ssh.service || true
    - systemctl mask --runtime ssh.socket ssh.service || true
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
    # default of half. Grow later with grow-root (growpart+pvresize+lvextend).
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
    # Make sure sshd is installed, has host keys and starts at boot. The
    # socket-activated default (ssh.socket) came up disabled, and
    # "systemctl enable" fails inside the installer chroot, so wire up
    # ssh.service with plain symlinks (exactly what "enable" would create).
    # (Plain $VAR only: templatefile() would expand $${...}.)
    - curtin in-target --target=/target -- apt-get install -y openssh-server
    - curtin in-target --target=/target -- ssh-keygen -A
    - |
      T=/target/etc/systemd/system
      UNIT=/usr/lib/systemd/system/ssh.service
      [ -f /target$UNIT ] || UNIT=/lib/systemd/system/ssh.service
      [ -f /target$UNIT ] || { echo "ssh.service unit not found in target" >&2; exit 1; }
      rm -f $T/ssh.service.d/00-socket.conf $T/ssh.socket.d/addresses.conf
      rm -f $T/sockets.target.wants/ssh.socket $T/ssh.socket
      if [ -L $T/ssh.service ] && [ "$(readlink $T/ssh.service)" = /dev/null ]; then rm -f $T/ssh.service; fi
      mkdir -p $T/multi-user.target.wants
      ln -sf $UNIT $T/multi-user.target.wants/ssh.service
      ln -sf $UNIT $T/sshd.service
      ls -l $T/multi-user.target.wants/ssh.service $T/sshd.service
    # Build-only extra port for Packer (removed by scripts/90-cleanup.sh).
    - printf 'Port 22\nPort ${ssh_build_port}\n' > /target/etc/ssh/sshd_config.d/05-packer-build.conf
  # cloud-init config applied on the first boot of the installed system.
  user-data:
    hostname: ${hostname}
    preserve_hostname: false
    ssh_pwauth: true
    users:
      - name: ${username}
        gecos: Admin user
        groups: [adm, sudo]
        shell: /bin/bash
        lock_passwd: false
        plain_text_passwd: ${jsonencode(password)}
%{ if ssh_authorized_key != "" ~}
        ssh_authorized_keys:
          - ${jsonencode(ssh_authorized_key)}
%{ endif ~}

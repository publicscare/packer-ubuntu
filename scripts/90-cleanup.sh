#!/usr/bin/env bash
# Generalize the image so every clone / flashed disk gets its own identity.
set -euo pipefail

echo "==> [90-cleanup] Making sure the disk boots via the UEFI removable path"
# The Fusion NVRAM entry is not carried into the raw .img, so other UEFI
# firmware must find the loader at \EFI\BOOT\BOOTAA64.EFI.
if [[ -d /boot/efi/EFI/ubuntu && ! -f /boot/efi/EFI/BOOT/BOOTAA64.EFI ]]; then
  install -d /boot/efi/EFI/BOOT
  cp /boot/efi/EFI/ubuntu/shimaa64.efi /boot/efi/EFI/BOOT/BOOTAA64.EFI
  [[ -f /boot/efi/EFI/ubuntu/mmaa64.efi ]] && cp /boot/efi/EFI/ubuntu/mmaa64.efi /boot/efi/EFI/BOOT/
  [[ -f /usr/lib/shim/fbaa64.efi.signed ]] && cp /usr/lib/shim/fbaa64.efi.signed /boot/efi/EFI/BOOT/fbaa64.efi
fi

if [[ "${DISABLE_PASSWORD_SSH:-false}" == "true" ]]; then
  echo "==> [90-cleanup] SSH key was supplied: disabling SSH password login"
  # sshd uses the first value it reads, and files load in lexical order, so
  # 10-* overrides the 50-cloud-init.conf that cloud-init rewrites on first boot.
  cat > /etc/ssh/sshd_config.d/10-k8s-image.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
fi

echo "==> [90-cleanup] Removing the build-only SSH port"
rm -f /etc/ssh/sshd_config.d/05-packer-build.conf

echo "==> [90-cleanup] apt"
apt-get -y autoremove --purge
apt-get -y clean
rm -rf /var/lib/apt/lists/*

echo "==> [90-cleanup] Logs, temp files, shell history"
journalctl --rotate >/dev/null 2>&1 || true
journalctl --vacuum-time=1s >/dev/null 2>&1 || true
find /var/log -type f \( -name '*.gz' -o -name '*.[0-9]' -o -name '*.old' \) -delete
find /var/log -type f -exec truncate -s 0 {} +
rm -rf /tmp/* /var/tmp/* /root/.cache /root/.config/helm
rm -f /root/.bash_history "/home/${BUILD_USERNAME:-nobody}/.bash_history"

echo "==> [90-cleanup] Resetting machine identity"
cloud-init clean --logs --machine-id 2>/dev/null || cloud-init clean --logs
# The Ubuntu installer turns cloud-init off after the first boot by creating
# this marker. Remove it so clones run cloud-init again (new SSH host keys,
# VMware guestinfo / NoCloud customisation).
rm -f /etc/cloud/cloud-init.disabled
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id
rm -f /etc/ssh/ssh_host_*   # recreated on first boot by cloud-init / regenerate-ssh-host-keys
rm -f /var/lib/systemd/random-seed

echo "==> [90-cleanup] Trimming free space so the vmdk compacts"
sync
fstrim -av || true

echo "==> [90-cleanup] Done"

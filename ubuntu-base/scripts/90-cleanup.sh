#!/usr/bin/env bash
# Generalize the image so every clone / flashed disk gets its own identity.
set -euo pipefail

echo "==> [90-cleanup] Making sure the disk boots via the UEFI removable path"
# The build VM's NVRAM boot entry is not carried into the disk image, so other
# UEFI firmware must find the loader at the removable-media path.
case "$(dpkg --print-architecture)" in
  arm64) EFI_SFX=aa64; EFI_BOOT=BOOTAA64.EFI ;;
  amd64) EFI_SFX=x64;  EFI_BOOT=BOOTX64.EFI ;;
  *)     EFI_SFX="";   EFI_BOOT="" ;;
esac
if [[ -n "${EFI_BOOT}" && -d /boot/efi/EFI/ubuntu && ! -f "/boot/efi/EFI/BOOT/${EFI_BOOT}" ]]; then
  install -d /boot/efi/EFI/BOOT
  cp "/boot/efi/EFI/ubuntu/shim${EFI_SFX}.efi" "/boot/efi/EFI/BOOT/${EFI_BOOT}"
  if [[ -f "/boot/efi/EFI/ubuntu/mm${EFI_SFX}.efi" ]]; then cp "/boot/efi/EFI/ubuntu/mm${EFI_SFX}.efi" /boot/efi/EFI/BOOT/; fi
  if [[ -f "/usr/lib/shim/fb${EFI_SFX}.efi.signed" ]]; then cp "/usr/lib/shim/fb${EFI_SFX}.efi.signed" "/boot/efi/EFI/BOOT/fb${EFI_SFX}.efi"; fi
fi
ls -l /boot/efi/EFI/BOOT/ 2>/dev/null || true

if [[ "${DISABLE_PASSWORD_SSH:-false}" == "true" ]]; then
  echo "==> [90-cleanup] SSH key was supplied: disabling SSH password login"
  # Lexically before cloud-init's 50-cloud-init.conf, so it wins.
  cat > /etc/ssh/sshd_config.d/10-base-image.conf <<'EOF'
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
rm -rf /tmp/* /var/tmp/* /root/.cache
rm -f /root/.bash_history "/home/${BUILD_USERNAME:-nobody}/.bash_history"

echo "==> [90-cleanup] Resetting machine identity"
cloud-init clean --logs --machine-id 2>/dev/null || cloud-init clean --logs
# The installer disables cloud-init after first boot; re-enable it for clones.
rm -f /etc/cloud/cloud-init.disabled
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id
rm -f /etc/ssh/ssh_host_*   # recreated on first boot (cloud-init / regenerate-ssh-host-keys)
rm -f /var/lib/systemd/random-seed

echo "==> [90-cleanup] Trimming free space so the vmdk compacts"
sync
fstrim -av || true

echo "==> [90-cleanup] Done"

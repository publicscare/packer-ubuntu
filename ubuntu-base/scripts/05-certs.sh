#!/usr/bin/env bash
# Trust corporate root CAs (e.g. Zscaler) before anything is downloaded over
# HTTPS. Certificates come from the repo's certs/ folder (git-ignored).
# Accepts PEM or DER, with .crt, .pem or .cer extensions.
set -euo pipefail
: "${STAGE_DIR:?}"

SRC="${STAGE_DIR}/certs"
DEST=/usr/local/share/ca-certificates/corporate

shopt -s nullglob nocaseglob
CERTS=("${SRC}"/*.crt "${SRC}"/*.pem "${SRC}"/*.cer)
shopt -u nocaseglob

if [[ ${#CERTS[@]} -eq 0 ]]; then
  echo "==> [05-certs] No certificates in certs/; skipping"
  exit 0
fi

echo "==> [05-certs] Installing ${#CERTS[@]} corporate CA certificate(s)"
install -d -m 0755 "${DEST}"
for c in "${CERTS[@]}"; do
  name="$(basename "${c%.*}").crt"
  if grep -q -- '-----BEGIN CERTIFICATE-----' "${c}"; then
    tr -d '\r' < "${c}" > "${DEST}/${name}"   # PEM; drop Windows line endings
  else
    openssl x509 -inform DER -in "${c}" -out "${DEST}/${name}"
  fi
  chmod 0644 "${DEST}/${name}"
  openssl x509 -in "${DEST}/${name}" -noout -subject -enddate
done

update-ca-certificates
echo "==> [05-certs] Done"

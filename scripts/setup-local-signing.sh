#!/bin/bash
# One-time local identity. Never put the key or machine configuration in Git.
set -euo pipefail
umask 077
settings="$HOME/Library/Application Support/SnapStack/Signing"
identity_file="$settings/identity"
if [ -f "$identity_file" ]; then
    echo "Local signing identity already configured; refusing to replace it."
    exit 0
fi
mkdir -p "$settings"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
cat > "$scratch/cert.conf" <<'EOF'
[req]
distinguished_name = subject
x509_extensions = extensions
prompt = no
[subject]
CN = SnapStack Local Code Signing
[extensions]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
/usr/bin/openssl req -new -newkey rsa:3072 -nodes -x509 -days 3650 \
    -config "$scratch/cert.conf" -keyout "$scratch/key.pem" -out "$scratch/cert.pem" 2>/dev/null
/usr/bin/openssl rand -hex 24 > "$scratch/password"
/usr/bin/openssl pkcs12 -export -inkey "$scratch/key.pem" -in "$scratch/cert.pem" \
    -name 'SnapStack Local Code Signing' -out "$scratch/identity.p12" -passout "file:$scratch/password" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
# Private key stays in the login keychain. Only codesign gets a predefined ACL.
/usr/bin/security import "$scratch/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -f pkcs12 -P "$(cat "$scratch/password")" -x -T /usr/bin/codesign
/usr/bin/openssl x509 -in "$scratch/cert.pem" -noout -fingerprint -sha1 \
    | sed 's/.*=//;s/://g' > "$identity_file"
cp "$scratch/cert.pem" "$settings/certificate.pem"
echo "Configured local signing identity in $settings (no global trust changes)."

#!/bin/bash
# Creates a self-signed "GestureKeys Dev" code-signing certificate in the login keychain.
#
# macOS remembers the Accessibility grant by code signature. Ad-hoc signatures change with every
# build, so the grant is lost on each rebuild; a stable certificate keeps it. build-app.sh picks
# this identity up automatically. Run once per machine.
set -euo pipefail

NAME="GestureKeys Dev"
if security find-identity -p codesigning | grep -q "\"$NAME\""; then
    echo "\"$NAME\" already exists."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/cert.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
# OpenSSL 3 needs -legacy for a PKCS#12 that `security` can read; LibreSSL has no such flag.
openssl pkcs12 -export -legacy -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -out "$WORK/id.p12" \
    -passout pass:gesturekeys -name "$NAME" 2>/dev/null \
|| openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -out "$WORK/id.p12" \
    -passout pass:gesturekeys -name "$NAME"

security import "$WORK/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P gesturekeys -T /usr/bin/codesign
echo "Created \"$NAME\". It shows as untrusted (CSSMERR_TP_NOT_TRUSTED); codesign accepts it anyway."

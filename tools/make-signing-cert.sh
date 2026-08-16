#!/bin/bash
# Creates a trusted self-signed code-signing identity so rebuilds keep a stable
# designated requirement. Ad-hoc signing yields `cdhash H"..."`, which changes
# every build and invalidates TCC grants; an identity yields `certificate leaf`.
# Run once. Idempotent: re-running resumes instead of creating a second cert.
set -euo pipefail

NAME="${1:-MyNavbarsLocalDev}"
OPENSSL=/usr/bin/openssl
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRT="$DIR/devsign.crt"
LOGIN_KC="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -qF "$NAME"; then
  echo "Identity '$NAME' already trusted and valid for code signing."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if security find-certificate -c "$NAME" "$LOGIN_KC" >/dev/null 2>&1; then
  echo "==> cert '$NAME' already in login keychain; skipping generation"
  [ -f "$CRT" ] || { echo "ERROR: $CRT missing, cannot re-add trust."; \
    echo "Delete the cert from Keychain Access and re-run."; exit 1; }
else
  cat > "$WORK/cfg" <<EOF
[req]
distinguished_name=dn
x509_extensions=v3
prompt=no
[dn]
CN=$NAME
[v3]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
subjectKeyIdentifier=hash
EOF
  echo "==> generating self-signed code-signing cert '$NAME'"
  "$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$CRT" -config "$WORK/cfg" 2>/dev/null
  "$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$CRT" \
    -out "$WORK/id.p12" -name "$NAME" -passout pass:tmp

  echo "==> importing into login keychain"
  security import "$WORK/id.p12" -k "$LOGIN_KC" -P tmp \
    -T /usr/bin/codesign -T /usr/bin/security
fi

echo "==> trusting for code signing (needs sudo)"
sudo security add-trusted-cert -d -r trustRoot -p codeSign \
  -k /Library/Keychains/System.keychain "$CRT"

echo "==> presetting keychain ACL (optional)"
echo "    Enter your macOS login password so codesign can use the key without a"
echo "    GUI prompt, or press Return to skip and click 'Always Allow' once."
read -rs -p "    login password: " LOGIN_PW; echo
if [ -n "$LOGIN_PW" ]; then
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
    -l "$NAME" -k "$LOGIN_PW" "$LOGIN_KC" >/dev/null 2>&1 \
    && echo "    ACL set" || echo "    ACL preset failed; use 'Always Allow' prompt"
fi
unset LOGIN_PW

echo "==> verifying identity is valid for code signing"
security find-identity -v -p codesigning | grep -F "$NAME" \
  || { echo "FAILED: cert imported and trusted but not a valid signing identity."; \
       echo "Open Keychain Access, find '$NAME', set trust to Always Trust."; exit 1; }

echo "==> proving the designated requirement is stable across rebuilds"
mk_app() {
  local app="$1" body="$2"
  rm -rf "$app"; mkdir -p "$app/Contents/MacOS"
  printf 'int main(void){return %s;}\n' "$body" > "$WORK/m.c"
  clang -o "$app/Contents/MacOS/DRTest" "$WORK/m.c"
  cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DRTest</string>
<key>CFBundleIdentifier</key><string>dev.local.drtest</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
EOF
  codesign --force -s "$NAME" "$app" >/dev/null 2>&1
  codesign -d -r- "$app" 2>/dev/null | grep "designated =>"
}
A="$(mk_app "$WORK/A.app" 0)"
B="$(mk_app "$WORK/B.app" 42)"
echo "    build A: $A"
echo "    build B: $B"
if [ "$A" = "$B" ] && [ -n "$A" ] && [[ "$A" != *cdhash* ]]; then
  echo "    STABLE — identity-based requirement, TCC grants will survive rebuilds."
else
  echo "    UNSTABLE — requirement still content-derived; TCC will re-prompt."
  exit 1
fi

echo
echo "Done. Sign with:  codesign --force -s \"$NAME\" YourApp.app"

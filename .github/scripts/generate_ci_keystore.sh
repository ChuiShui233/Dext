#!/bin/bash
# Generate temporary signing keystore for CI builds

set -e

echo "Generating temporary CI signing keystore..."

# Generate random passwords
KEYSTORE_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
KEY_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
KEY_ALIAS="ci_key_$(date +%s)"

echo "Key alias: $KEY_ALIAS"

# Generate keystore
keytool -genkey -v \
  -keystore android/app/ci-release.keystore \
  -alias "$KEY_ALIAS" \
  -keyalg RSA \
  -keysize 2048 \
  -validity 365 \
  -storepass "$KEYSTORE_PASSWORD" \
  -keypass "$KEY_PASSWORD" \
  -dname "CN=CI Build, OU=CI, O=Dext, L=GitHub, ST=Actions, C=US"

echo ""
echo "Keystore generated successfully"

# Create key.properties file
cat > android/key.properties << EOF
storePassword=$KEYSTORE_PASSWORD
keyPassword=$KEY_PASSWORD
keyAlias=$KEY_ALIAS
storeFile=ci-release.keystore
EOF

echo "key.properties file created"
echo ""
echo "CI signing setup complete!"

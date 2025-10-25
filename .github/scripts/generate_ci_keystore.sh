#!/bin/bash
# Generate temporary signing keystore for CI builds

set -e

echo "🔑 Generating temporary CI signing keystore..."

# Generate random password (use same for both store and key to avoid issues)
CI_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
KEY_ALIAS="ci_key_$(date +%s)"

echo "Key alias: $KEY_ALIAS"

# Ensure the directory exists
mkdir -p android/app

# Generate keystore
keytool -genkeypair -v \
  -storetype PKCS12 \
  -keystore android/app/ci-release.keystore \
  -alias "$KEY_ALIAS" \
  -keyalg RSA \
  -keysize 2048 \
  -validity 365 \
  -storepass "$CI_PASSWORD" \
  -keypass "$CI_PASSWORD" \
  -dname "CN=CI Build, OU=CI, O=Dext, L=GitHub, ST=Actions, C=US"

if [ $? -ne 0 ]; then
    echo "❌ Failed to generate keystore"
    exit 1
fi

echo ""
echo "✅ Keystore generated successfully"

# Verify keystore
echo "Verifying keystore..."
keytool -list -v -keystore android/app/ci-release.keystore -storepass "$CI_PASSWORD" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "❌ Keystore verification failed"
    exit 1
fi
echo "✅ Keystore verified"

# Create key.properties file
cat > android/key.properties << EOF
storePassword=$CI_PASSWORD
keyPassword=$CI_PASSWORD
keyAlias=$KEY_ALIAS
storeFile=ci-release.keystore
EOF

echo "key.properties file created"
echo ""
echo "CI signing setup complete!"

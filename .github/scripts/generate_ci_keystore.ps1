# Generate temporary signing keystore for CI builds

Write-Host "🔑 Generating temporary CI signing keystore..." -ForegroundColor Cyan

# Generate random password (use same for both store and key to avoid issues)
function Generate-RandomPassword {
    param([int]$Length = 25)
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $base64 = [Convert]::ToBase64String($bytes)
    return $base64 -replace '[=+/]', '' | Select-Object -First 1 | ForEach-Object { $_.Substring(0, [Math]::Min($Length, $_.Length)) }
}

$CI_PASSWORD = Generate-RandomPassword
$KEY_ALIAS = "ci_key_$(Get-Date -Format 'yyyyMMddHHmmss')"

Write-Host "Key alias: $KEY_ALIAS"

# Check if keytool is available
$keytoolPath = (Get-Command keytool -ErrorAction SilentlyContinue).Source
if (-not $keytoolPath) {
    Write-Host "keytool not found, please ensure Java JDK is installed" -ForegroundColor Red
    exit 1
}

# Ensure the directory exists
New-Item -ItemType Directory -Force -Path "android\app" | Out-Null

# Generate keystore
$keystorePath = "android\app\ci-release.keystore"
$dname = "CN=CI Build, OU=CI, O=Dext, L=GitHub, ST=Actions, C=US"

& keytool -genkeypair -v `
  -storetype PKCS12 `
  -keystore $keystorePath `
  -alias $KEY_ALIAS `
  -keyalg RSA `
  -keysize 2048 `
  -validity 365 `
  -storepass $CI_PASSWORD `
  -keypass $CI_PASSWORD `
  -dname $dname

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Keystore generation failed" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "✅ Keystore generated successfully" -ForegroundColor Green

# Verify keystore
Write-Host "Verifying keystore..."
& keytool -list -v -keystore $keystorePath -storepass $CI_PASSWORD > $null 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Keystore verification failed" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Keystore verified" -ForegroundColor Green

# Create key.properties file
$keyPropertiesContent = @"
storePassword=$CI_PASSWORD
keyPassword=$CI_PASSWORD
keyAlias=$KEY_ALIAS
storeFile=ci-release.keystore
"@

$keyPropertiesContent | Out-File -FilePath "android\key.properties" -Encoding ASCII

Write-Host "✅ key.properties file created" -ForegroundColor Green
Write-Host ""
Write-Host "🎉 CI signing setup complete!" -ForegroundColor Green

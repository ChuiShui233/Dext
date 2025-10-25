# Generate temporary signing keystore for CI builds

Write-Host "🔑 Generating temporary CI signing keystore..." -ForegroundColor Cyan

# 生成随机密码
function Generate-RandomPassword {
    param([int]$Length = 25)
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $base64 = [Convert]::ToBase64String($bytes)
    return $base64 -replace '[=+/]', '' | Select-Object -First 1 | ForEach-Object { $_.Substring(0, [Math]::Min($Length, $_.Length)) }
}

$KEYSTORE_PASSWORD = Generate-RandomPassword
$KEY_PASSWORD = Generate-RandomPassword
$KEY_ALIAS = "ci_key_$(Get-Date -Format 'yyyyMMddHHmmss')"

Write-Host "Key alias: $KEY_ALIAS"

# Check if keytool is available
$keytoolPath = (Get-Command keytool -ErrorAction SilentlyContinue).Source
if (-not $keytoolPath) {
    Write-Host "keytool not found, please ensure Java JDK is installed" -ForegroundColor Red
    exit 1
}

# Generate keystore
$keystorePath = "android\app\ci-release.keystore"
$dname = "CN=CI Build, OU=CI, O=Dext, L=GitHub, ST=Actions, C=US"

& keytool -genkey -v `
  -keystore $keystorePath `
  -alias $KEY_ALIAS `
  -keyalg RSA `
  -keysize 2048 `
  -validity 365 `
  -storepass $KEYSTORE_PASSWORD `
  -keypass $KEY_PASSWORD `
  -dname $dname

if ($LASTEXITCODE -ne 0) {
    Write-Host "Keystore generation failed" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Keystore generated successfully" -ForegroundColor Green

# Create key.properties file
$keyPropertiesContent = @"
storePassword=$KEYSTORE_PASSWORD
keyPassword=$KEY_PASSWORD
keyAlias=$KEY_ALIAS
storeFile=ci-release.keystore
"@

$keyPropertiesContent | Out-File -FilePath "android\key.properties" -Encoding ASCII

Write-Host "key.properties file created" -ForegroundColor Green
Write-Host ""
Write-Host "CI signing setup complete!" -ForegroundColor Green

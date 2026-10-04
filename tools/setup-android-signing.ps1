# Creates the permanent Android release signing key for this app and stores it as
# GitHub Actions secrets, so every CI build is signed with the same key and new
# versions install over the old one (keeping your data).
#
# Run once on your own PC, from the repo folder:
#   powershell -ExecutionPolicy Bypass -File tools\setup-android-signing.ps1
#
# Needs: GitHub CLI logged in (`gh auth login`) and a JDK keytool
# (Android Studio ships one). The key never leaves your PC except as a GitHub secret.
# Keep the folder it prints somewhere safe: if the key is lost, the next update
# needs one uninstall (export a backup first).

$ErrorActionPreference = 'Stop'
$repo = 'HKmario852/money-manager'
$alias = 'money-manager'
$dir = Join-Path $HOME 'money-manager-signing'
$jks = Join-Path $dir 'money-manager-release.jks'

if (Test-Path $jks) {
    throw "A key already exists at $jks. Not overwriting it (installed apps could no longer update)."
}

$keytool = (Get-Command keytool -ErrorAction SilentlyContinue).Source
if (-not $keytool) {
    $candidates = @(
        "$env:JAVA_HOME\bin\keytool.exe",
        "$env:ProgramFiles\Android\Android Studio\jbr\bin\keytool.exe",
        "$env:ProgramFiles\Android\Android Studio\jre\bin\keytool.exe"
    )
    $keytool = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
if (-not $keytool) { throw 'keytool not found. Install Android Studio or a JDK, then run again.' }
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'GitHub CLI (gh) not found: https://cli.github.com' }

# A key already in GitHub secrets means releases are signed with it. Replacing it would stop
# installed copies from updating, so refuse unless explicitly forced.
$existing = gh secret list -R $repo | Select-String -SimpleMatch 'ANDROID_KEYSTORE_BASE64'
if ($existing -and -not $env:FORCE_NEW_SIGNING_KEY) {
    throw 'ANDROID_KEYSTORE_BASE64 is already set on GitHub. Keep using that key (back it up). Set FORCE_NEW_SIGNING_KEY=1 only if you really want a new key; installed apps will then need one uninstall.'
}

New-Item -ItemType Directory -Force $dir | Out-Null
$bytes = New-Object byte[] 24
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$pw = ([Convert]::ToBase64String($bytes) -replace '[/+=]', '')

& $keytool -genkeypair -keystore $jks -storetype PKCS12 -alias $alias -keyalg RSA -keysize 4096 `
    -validity 36500 -storepass $pw -keypass $pw -dname 'CN=Mario, C=HK' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'keytool failed' }
Set-Content -Path (Join-Path $dir 'password.txt') -Value $pw -NoNewline

$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($jks))
gh secret set ANDROID_KEYSTORE_BASE64 -R $repo --body $b64
gh secret set ANDROID_KEYSTORE_PASSWORD -R $repo --body $pw
gh secret set ANDROID_KEY_ALIAS -R $repo --body $alias

Write-Host ''
Write-Host "Done. Signing key saved in: $dir"
Write-Host 'Back up that folder (e.g. password manager or USB). Do not commit it.'

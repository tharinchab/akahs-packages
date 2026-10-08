# akahs-cli for Windows, in PowerShell:
#
#   irm https://downloads.akahs.com/cli.ps1 | iex
#
# One file in %LOCALAPPDATA%\Programs\Akahs\bin (no admin), checked against
# SHA256SUMS and added to your PATH. Update later with: akahs-cli update
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

& {
  $releases = if ($env:AKAHS_CLI_RELEASES) { $env:AKAHS_CLI_RELEASES } else { 'https://github.com/tharinchab/akahs-packages/releases/download/cli' }
  $dir = if ($env:AKAHS_INSTALL_DIR) { $env:AKAHS_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'Programs\Akahs\bin' }
  $asset = 'akahs-cli-windows-x64.zip'
  if (-not [Environment]::Is64BitOperatingSystem) { throw 'akahs-cli needs 64-bit Windows.' }

  $tmp = Join-Path ([IO.Path]::GetTempPath()) ('akahs-' + [guid]::NewGuid())
  New-Item -ItemType Directory $tmp | Out-Null
  try {
    Write-Host '==> Downloading akahs-cli'
    Invoke-WebRequest "$releases/SHA256SUMS" -OutFile "$tmp\SHA256SUMS" -UseBasicParsing
    Invoke-WebRequest "$releases/$asset" -OutFile "$tmp\$asset" -UseBasicParsing
    $line = Get-Content "$tmp\SHA256SUMS" | Where-Object { $_ -match ('\s\*?' + [regex]::Escape($asset) + '$') } | Select-Object -First 1
    if (-not $line) { throw "$asset isn't in SHA256SUMS" }
    $want = ($line -split '\s+')[0]
    if ((Get-FileHash "$tmp\$asset" -Algorithm SHA256).Hash -ne $want) {
      throw "$asset doesn't match its checksum; nothing was installed. Try again."
    }
    Expand-Archive "$tmp\$asset" -DestinationPath "$tmp\x" -Force

    New-Item -ItemType Directory -Force $dir | Out-Null
    $exe = Join-Path $dir 'akahs-cli.exe'
    $old = Join-Path $dir 'akahs-cli.old.exe'
    # A running akahs-cli can be renamed but not overwritten.
    Remove-Item $old -Force -ErrorAction SilentlyContinue
    if (Test-Path $exe) { Move-Item $exe $old -Force }
    Copy-Item "$tmp\x\akahs-cli.exe" $exe -Force
    $version = & $exe --version
    Write-Host "==> Installed $version to $exe" -ForegroundColor Green

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not (($userPath -split ';') -contains $dir)) {
      $newPath = if ($userPath) { "$userPath;$dir" } else { $dir }
      [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
      Write-Host "==> Added $dir to your PATH"
    }
    if (-not (($env:Path -split ';') -contains $dir)) { $env:Path = "$env:Path;$dir" }
    Write-Host ''
    Write-Host '==> Now run akahs-cli to sign in and chat. Update any time: akahs-cli update'
  } finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
  }
}

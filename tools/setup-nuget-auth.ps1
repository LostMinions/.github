<#
.SYNOPSIS
  Sets up NuGet for LostMinions local development.
  - Always downloads and overwrites the latest LostMinions.Packages bundle.
  - Extracts it to local-packages/.
  - Deletes the .zip afterward to save space.
  - Adds it as a top-priority NuGet source with GitHub + nuget.org fallback.

.EXAMPLE
  .\setup-nuget-auth.ps1 -Token "ghp_xxxxxxxxxxxxxxxxx"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Token,

    [string]$User = "TheKrush",
    [string]$Owner = "LostMinions"
)

Write-Host ""
Write-Host "Setting up NuGet for LostMinions development..."
Write-Host ""

$repoRoot      = (Get-Location).Path
$nugetDir      = Join-Path $env:APPDATA "NuGet"
$nugetConfig   = Join-Path $nugetDir "NuGet.Config"
$localPackages = Join-Path $repoRoot "local-packages"
$bundleZip     = Join-Path $repoRoot "LostMinions.Packages.zip"
$versionFile   = Join-Path $repoRoot ".local-packages-version"
$bundleExtracted = $false

if (-not (Test-Path $nugetDir)) {
    New-Item -ItemType Directory -Path $nugetDir | Out-Null
}

# --- Step 1: Fetch or verify latest package bundle -------------------------
Write-Host "Checking for latest LostMinions.Packages bundle..."
$apiUrl = "https://api.github.com/repos/$Owner/LostMinions.Packages/releases/latest"

$headers = @{
    "Authorization" = "token $Token"
    "Accept"        = "application/vnd.github+json"
    "User-Agent"    = "LostMinions-SetupScript"
}

# Handle empty or missing version file
if ((Test-Path $versionFile) -and ((Get-Item $versionFile).Length -eq 0)) {
    Write-Host "Detected empty version file --- deleting to force re-download."
    Remove-Item $versionFile -Force
}

try {
    $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers -ErrorAction Stop
    if (-not $release -or -not $release.tag_name) {
        throw "GitHub API returned no release information (check token or repo access)."
    }
}
catch {
    Write-Warning "Failed to contact GitHub API: $($_.Exception.Message)"
    $release = $null
}

$latestVersion  = if ($release) { ($release.tag_name -replace '^v', '').Trim() } else { 'unknown' }
$currentVersion = if ((Test-Path $versionFile) -and ((Get-Item $versionFile).Length -gt 0)) {
    ((Get-Content $versionFile -Raw).Trim() -replace '^v', '')
} else {
    ''
}

Write-Host "Current version: '$currentVersion'"
Write-Host "Latest version:  '$latestVersion'"

if ($latestVersion -eq 'unknown' -or $currentVersion -ne $latestVersion -or -not (Test-Path $localPackages)) {
    Write-Host "Update required --- downloading latest bundle..."

    try {
        if (-not $release) {
            $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers -ErrorAction Stop
            $latestVersion = ($release.tag_name -replace '^v', '').Trim()
        }

        $asset = $release.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
        if ($asset -and $asset.url) {
            if (Test-Path $bundleZip) { Remove-Item $bundleZip -Force }
            Write-Host "Found bundle asset ($latestVersion): $($asset.name)"
            Invoke-WebRequest -Uri $asset.url `
                -Headers @{ "Authorization" = "token $Token"; "Accept" = "application/octet-stream" } `
                -OutFile $bundleZip
            Write-Host "Download complete."

            if (-not (Test-Path $localPackages)) {
                New-Item -ItemType Directory -Path $localPackages | Out-Null
            }

            Write-Host "Extracting bundle..."
            Expand-Archive -Force -Path $bundleZip -DestinationPath $localPackages
            Remove-Item $bundleZip -Force
            Set-Content -Path $versionFile -Value $latestVersion
            $bundleExtracted = $true
            Write-Host "Extracted and recorded version: $latestVersion -> $versionFile"
        }
        else {
            Write-Warning "No .zip asset found in latest release."
        }
    }
    catch {
        Write-Warning "Failed to download or extract bundle: $($_.Exception.Message)"
    }
}
else {
    Write-Host "Already up-to-date ($latestVersion). Skipping download."
    $bundleExtracted = $true
}

# --- Step 2: Ensure local-packages folder exists ----------------------------
if (-not (Test-Path $localPackages)) {
    New-Item -ItemType Directory -Path $localPackages | Out-Null
    Write-Host "Created local-packages directory."
} else {
    Write-Host "Using existing local-packages directory."
}

# --- Step 3: Configure NuGet sources ---------------------------------------
$xml = @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <add key="local-packages" value="$localPackages" />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
    <add key="github" value="https://nuget.pkg.github.com/$Owner/index.json" />
  </packageSources>
  <packageSourceCredentials>
    <github>
      <add key="Username" value="$User" />
      <add key="ClearTextPassword" value="$Token" />
    </github>
  </packageSourceCredentials>
</configuration>
"@

if (-not (Test-Path $nugetDir)) {
    New-Item -ItemType Directory -Path $nugetDir | Out-Null
}

$xml | Out-File -FilePath $nugetConfig -Encoding utf8 -Force
Write-Host "NuGet configuration written to: $nugetConfig"

# --- Step 4: Register globally ---------------------------------------------
Write-Host ""
Write-Host "Registering NuGet sources globally..."
dotnet nuget remove source local-packages -v q -f 2>$null | Out-Null
dotnet nuget remove source github         -v q -f 2>$null | Out-Null
dotnet nuget remove source nuget.org      -v q -f 2>$null | Out-Null

dotnet nuget add source $localPackages --name "local-packages" | Out-Null
dotnet nuget add source "https://api.nuget.org/v3/index.json" --name "nuget.org" | Out-Null
dotnet nuget add source `
  "https://nuget.pkg.github.com/$Owner/index.json" `
  --name "github" `
  --username "$User" `
  --password "$Token" `
  --store-password-in-clear-text | Out-Null

Write-Host ""
Write-Host "NuGet sources configured successfully."
Write-Host ""
Write-Host "You can now run:"
Write-Host "  dotnet restore"
Write-Host "  dotnet build"
Write-Host ""

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

if (-not (Test-Path $nugetDir)) {
    New-Item -ItemType Directory -Path $nugetDir | Out-Null
}

# --- Step 1: Check for latest bundle ---------------------------------------
Write-Host "Checking for latest LostMinions.Packages bundle..."
$apiUrl = "https://api.github.com/repos/$Owner/LostMinions.Packages/releases/latest"
$versionFile = Join-Path $repoRoot ".local-packages-version"

$headers = @{
    "Authorization" = "token $Token"
    "Accept"        = "application/vnd.github+json"
    "User-Agent"    = "LostMinions-SetupScript"
}

try {
    $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers

    # Normalize paths relative to script location
    $scriptRoot   = Split-Path -Parent $PSCommandPath
    $versionFile  = Join-Path $scriptRoot ".local-packages-version"
    $localPackages = Join-Path $scriptRoot "local-packages"
    $bundleZip    = Join-Path $scriptRoot "LostMinions.Packages.zip"

    $latestVersion  = $release.tag_name.Trim()
    $currentVersion = if (Test-Path $versionFile) {
        (Get-Content $versionFile -Raw).Trim()
    } else {
        ""
    }

    Write-Host "Current version: '$currentVersion'"
    Write-Host "Latest version:  '$latestVersion'"

    if ($currentVersion -eq $latestVersion -and (Test-Path $localPackages)) {
        Write-Host "Already up-to-date ($latestVersion). Skipping download."
        return
    }

    # otherwise download the new one
    $asset = $release.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
    if ($asset -and $asset.url) {
        Write-Host "Found new asset ($latestVersion): $($asset.name)"
        Write-Host "Downloading via GitHub API..."
        if (Test-Path $bundleZip) { Remove-Item $bundleZip -Force }
        Invoke-WebRequest -Uri $asset.url `
            -Headers @{ "Authorization" = "token $Token"; "Accept" = "application/octet-stream" } `
            -OutFile $bundleZip
        Write-Host "Download complete."

        # Extract and mark new version
        if (-not (Test-Path $localPackages)) {
            New-Item -ItemType Directory -Path $localPackages | Out-Null
        }
        Write-Host "Extracting bundle..."
        Expand-Archive -Force -Path $bundleZip -DestinationPath $localPackages
        Remove-Item $bundleZip -Force
        Write-Host "Extracted to: $localPackages"
        Set-Content -Path $versionFile -Value $latestVersion
        Write-Host "Recorded version: $latestVersion -> $versionFile"
    }
    else {
        Write-Host "No .zip asset found in latest release."
    }
}
catch {
    Write-Host "Failed to fetch or download bundle:"
    Write-Host $_.Exception.Message
}

# --- Step 2: Extract fresh (without wiping older packages) ------------------
if (-not (Test-Path $localPackages)) {
    New-Item -ItemType Directory -Path $localPackages | Out-Null
    Write-Host "Created local-packages directory."
} else {
    Write-Host "Updating existing local-packages --- old packages will remain."
}

if (Test-Path $bundleZip) {
    Write-Host "Extracting bundle (overwriting existing versions)..."
    Expand-Archive -Force -Path $bundleZip -DestinationPath $localPackages
    Write-Host "Extracted to: $localPackages"

    try {
        Remove-Item $bundleZip -Force
        Write-Host "Cleaned up bundle ZIP."
    } catch {
        Write-Host "Could not remove $bundleZip ($_)."
    }
} else {
    Write-Host "No bundle found after download attempt; skipping extraction."
}

if (Test-Path $bundleZip) {
    Write-Host "Extracting bundle..."
    Expand-Archive -Force -Path $bundleZip -DestinationPath $localPackages
    Write-Host "Extracted to: $localPackages"

    # Clean up ZIP after successful extraction
    try {
        Remove-Item $bundleZip -Force
        Write-Host "Cleaned up bundle ZIP."
    } catch {
        Write-Host "Could not remove $bundleZip ($_)."
    }
} else {
    Write-Host "No bundle found after download attempt; skipping extraction."
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

if (-not (Test-Path $nugetDir)) { New-Item -ItemType Directory -Path $nugetDir | Out-Null }
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

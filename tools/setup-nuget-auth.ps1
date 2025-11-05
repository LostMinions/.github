<#
.SYNOPSIS
  Configures NuGet for GitHub Packages authentication for LostMinions repos.
  Also ensures nuget.org remains available as a default source.

.EXAMPLE
  .\setup-nuget-auth.ps1 -Token "ghp_xxxxxxxxxxxxxxxxx"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Token,

    [string]$User = "TheKrush",
    [string]$Owner = "LostMinions"
)

$nugetDir = Join-Path $env:APPDATA "NuGet"
$nugetConfig = Join-Path $nugetDir "NuGet.Config"

Write-Host "Configuring NuGet for GitHub Packages and restoring nuget.org feed..."

if (-not (Test-Path $nugetDir)) {
    New-Item -ItemType Directory -Path $nugetDir | Out-Null
}

# Build XML config with both sources
$xml = @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
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

$xml | Out-File -FilePath $nugetConfig -Encoding utf8 -Force
Write-Host "NuGet configuration written to: $nugetConfig"

# --- Add or update global sources safely ---
Write-Host ""
Write-Host "Ensuring NuGet sources are correctly registered..."

# Remove stale entries
dotnet nuget remove source github -v q -f | Out-Null
dotnet nuget remove source "nuget.org" -v q -f | Out-Null

# Add nuget.org (always public, no auth)
dotnet nuget add source "https://api.nuget.org/v3/index.json" --name "nuget.org" | Out-Null

# Add GitHub Packages (authenticated)
dotnet nuget add source `
  "https://nuget.pkg.github.com/$Owner/index.json" `
  --name "github" `
  --username "$User" `
  --password "$Token" `
  --store-password-in-clear-text | Out-Null

Write-Host "Global NuGet sources configured successfully."
Write-Host ""
Write-Host "GitHub Packages authentication configured successfully."
Write-Host ""
Write-Host "You can now run:"
Write-Host "  dotnet restore"
Write-Host "  dotnet add package LostMinions.Logging"
Write-Host ""

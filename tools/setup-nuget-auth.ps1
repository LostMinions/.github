<#
.SYNOPSIS
  Configures NuGet for GitHub Packages authentication for LostMinions repos.

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

Write-Host "Configuring NuGet for GitHub Packages..."

if (-not (Test-Path $nugetDir)) {
    New-Item -ItemType Directory -Path $nugetDir | Out-Null
}

# Build XML config
$xml = @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
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

# Add global NuGet source for dotnet CLI
Write-Host "Adding GitHub source to global NuGet..."
dotnet nuget remove source github | Out-Null

$addCmd = @(
    "dotnet nuget add source",
    "https://nuget.pkg.github.com/$Owner/index.json",
    "--name github",
    "--username $User",
    "--password $Token",
    "--store-password-in-clear-text"
) -join ' '

try {
    Invoke-Expression $addCmd | Out-Null
    Write-Host "Global NuGet source 'github' added successfully."
} catch {
    Write-Warning "Could not add NuGet source globally (it may already exist)."
}

Write-Host ""
Write-Host "GitHub Packages authentication configured successfully."
Write-Host "You can now run:"
Write-Host "  dotnet restore"
Write-Host "  dotnet add package LostMinions.Logging"
Write-Host ""

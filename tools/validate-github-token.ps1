<#
.SYNOPSIS
  Ensures a valid GitHub Personal Access Token (GH_TOKEN) is stored persistently.

.DESCRIPTION
  - Checks if GH_TOKEN or GITHUB_TOKEN exist in user environment.
  - Validates by calling https://api.github.com/user.
  - If invalid or missing, prompts for a new token and updates registry.
  - Works for PowerShell, Visual Studio, and MSBuild.

.EXAMPLE
  pwsh .\validate-github-token.ps1
#>

param(
    [string]$TokenName = "GH_TOKEN"
)

$ErrorActionPreference = "Stop"

Write-Host "Checking for valid GitHub token ($TokenName)..."

# --- Get current token from environment or registry -------------------------
$currentToken = [Environment]::GetEnvironmentVariable($TokenName, "User")
if (-not $currentToken -and $TokenName -eq "GH_TOKEN") {
    # fallback to GITHUB_TOKEN if GH_TOKEN not found
    $currentToken = [Environment]::GetEnvironmentVariable("GITHUB_TOKEN", "User")
}

$headers = @{
    "Accept" = "application/vnd.github+json"
    "User-Agent" = "LostMinions-TokenValidator"
}

$valid = $false

if ($currentToken) {
    try {
        $headers["Authorization"] = "token $currentToken"
        $response = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers -ErrorAction Stop
        if ($response.login) {
            Write-Host "Token is valid for user: $($response.login)"
            $valid = $true
        }
    }
    catch {
        Write-Host "Existing token appears invalid or expired."
    }
}
else {
    Write-Host "No GitHub token found in environment."
}

# --- Prompt for new token if invalid ----------------------------------------
if (-not $valid) {
    Write-Host ""
    Write-Host "Please enter a new GitHub Personal Access Token (PAT)."
    Write-Host "It should have at least 'repo' and 'read:packages' scopes."
    $newToken = Read-Host "Paste your GitHub token"

    if ([string]::IsNullOrWhiteSpace($newToken)) {
        Write-Host "No token provided. Aborting."
        exit 1
    }

    # Persist to user environment (registry)
    Write-Host "Saving token to user environment..."
    setx GH_TOKEN $newToken | Out-Null
    setx GITHUB_TOKEN $newToken | Out-Null

    # Validate again immediately
    try {
        $headers["Authorization"] = "token $newToken"
        $response = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers -ErrorAction Stop
        if ($response.login) {
            Write-Host "Token verified and stored for user: $($response.login)"
        } else {
            Write-Host "Could not verify token (unknown response)."
        }
    }
    catch {
        Write-Host "Failed to verify new token: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-Host "Environment variables updated."
    Write-Host "Restart Visual Studio or open a new PowerShell session to apply changes."
}
else {
    Write-Host "No update needed --- existing token is valid."
}

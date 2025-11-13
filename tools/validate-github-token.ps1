param(
    [string]$Token,
    [switch]$Force,
    [string]$EnvVar = "GH_TOKEN"
)

Write-Host ""
Write-Host "Validating GitHub token..." -ForegroundColor Cyan

# Check for an existing environment token
$currentGh = [Environment]::GetEnvironmentVariable($EnvVar, "Process")
$currentGitHub = [Environment]::GetEnvironmentVariable("GITHUB_TOKEN", "Process")

if ($currentGh -or $currentGitHub) {
    Write-Host " Existing token(s) detected:"
    if ($currentGh) { Write-Host " - GH_TOKEN: $(($currentGh.Substring(0,4)) + '...')" }
    if ($currentGitHub) { Write-Host " - GITHUB_TOKEN: $(($currentGitHub.Substring(0,4)) + '...')" }

    if (-not $Force) {
        $response = Read-Host "Do you want to overwrite the existing token(s)? [y/N]"
        if ($response -notmatch '^[Yy]$') {
            Write-Host "Keeping existing tokens."
            exit 0
        }
    }
    Write-Host "Overwriting existing tokens..."
}

# If no token provided, prompt for one
if (-not $Token) {
    $Token = Read-Host "Please paste a valid GitHub Personal Access Token"
}

# Validate the token via GitHub API
try {
    $headers = @{ Authorization = "Bearer $Token" }
    $response = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers -ErrorAction Stop
    Write-Host "Token validated successfully for user: $($response.login)" -ForegroundColor Green

    # Export for this process
    [Environment]::SetEnvironmentVariable("GH_TOKEN", $Token, "Process")
    [Environment]::SetEnvironmentVariable("GITHUB_TOKEN", $Token, "Process")
    Write-Host "Token exported as GH_TOKEN and GITHUB_TOKEN."
}
catch {
    Write-Host "Invalid or expired token." -ForegroundColor Red
    exit 1
}

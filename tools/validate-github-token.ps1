param(
    [string]$Token,
    [switch]$Force,
    [string]$EnvVar = "GH_TOKEN",
    [switch]$PersistUser = $true
)

Write-Host ""
Write-Host "Validating GitHub token..." -ForegroundColor Cyan

# Check for an existing environment token (process or user)
$currentGhProcess   = [Environment]::GetEnvironmentVariable($EnvVar, "Process")
$currentGhUser      = [Environment]::GetEnvironmentVariable($EnvVar, "User")
$currentGitHubProc  = [Environment]::GetEnvironmentVariable("GITHUB_TOKEN", "Process")
$currentGitHubUser  = [Environment]::GetEnvironmentVariable("GITHUB_TOKEN", "User")

$anyExisting = $currentGhProcess -or $currentGhUser -or $currentGitHubProc -or $currentGitHubUser

if ($anyExisting) {
    Write-Host " Existing token(s) detected:"

    if ($currentGhProcess)  { Write-Host " - $EnvVar (process): $(($currentGhProcess.Substring(0,4)) + '...')" }
    if ($currentGhUser)     { Write-Host " - $EnvVar (user):    $(($currentGhUser.Substring(0,4)) + '...')" }
    if ($currentGitHubProc) { Write-Host " - GITHUB_TOKEN (process): $(($currentGitHubProc.Substring(0,4)) + '...')" }
    if ($currentGitHubUser) { Write-Host " - GITHUB_TOKEN (user):    $(($currentGitHubUser.Substring(0,4)) + '...')" }

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

    # Export for this process/session
    [Environment]::SetEnvironmentVariable("GH_TOKEN", $Token, "Process")
    [Environment]::SetEnvironmentVariable("GITHUB_TOKEN", $Token, "Process")
    $env:GH_TOKEN     = $Token
    $env:GITHUB_TOKEN = $Token
    Write-Host "Token exported as GH_TOKEN and GITHUB_TOKEN for this session."

    if ($PersistUser) {
        [Environment]::SetEnvironmentVariable("GH_TOKEN", $Token, "User")
        [Environment]::SetEnvironmentVariable("GITHUB_TOKEN", $Token, "User")
        Write-Host "Token also persisted to user-level environment (will apply to new shells)."
    }
}
catch {
    Write-Host "Invalid or expired token." -ForegroundColor Red
    exit 1
}

param(
    # Command to run on each VM, e.g.
    # -Command 'sudo apt update && sudo apt upgrade -y'
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$Command
)

if (-not $Command) {
    $Command = Read-Host "Enter the command to run on each runner"
}

# --- EDIT THESE AS NEEDED ---------------------------------
$vmUser  = "runner"

$hosts = @(
    "github-runner-lostminions",
    "github-runner-lostminionsgames",
    "github-runner-theportalrealm"
)
# -----------------------------------------------------------

foreach ($vmHost in $hosts) {
    Write-Host "===== $vmHost =====" -ForegroundColor Cyan
    ssh "$vmUser@$vmHost" "$Command"
    $code = $LASTEXITCODE

    if ($code -ne 0) {
        Write-Warning "$vmHost returned exit code $code"
    }

    Start-Sleep -Milliseconds 100   # tiny delay between commands
}

# Example: update all three runners
#.\Invoke-Runners.ps1 -Command 'sudo apt update && sudo apt upgrade -y'
#.\Invoke-Runners.ps1

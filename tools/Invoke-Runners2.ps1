param(
    # Command to run on each VM, e.g.
    # -Command 'sudo apt update && sudo apt upgrade -y'
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$Command
)

if (-not $Command) {
    $Command = Read-Host "Enter the command to run on each runner"
}

# Define your VMs here.
# Host is the friendly name (and what ssh will use if it resolves),
# Ip is the fallback, User is the Linux username.
$runners = @(
    [PSCustomObject]@{ Host = "github-runner-lostminions";      Ip = "192.168.1.108"; User = "runner" },
    [PSCustomObject]@{ Host = "github-runner-lostminionsgames"; Ip = "192.168.1.110"; User = "runner" },
    [PSCustomObject]@{ Host = "github-runner-theportalrealm";   Ip = "192.168.1.109"; User = "runner" }
    # Example extra:
    # [PSCustomObject]@{ Host = "stock-vm"; Ip = "192.168.1.242"; User = "stock" }
)

foreach ($vm in $runners) {
    # Prefer Host if set, otherwise fall back to IP
    $target = if ($vm.Host) { $vm.Host } else { $vm.Ip }

    Write-Host "===== $($vm.User)@$target =====" -ForegroundColor Cyan

    ssh "$($vm.User)@$target" "$Command"
    $code = $LASTEXITCODE

    if ($code -ne 0) {
        Write-Warning "$($vm.User)@$target returned exit code $code"
    }

    Start-Sleep -Milliseconds 100   # tiny delay between commands
}

# Examples:
# .\Invoke-Runners.ps1 -Command 'sudo apt update && sudo apt upgrade -y'
# .\Invoke-Runners.ps1

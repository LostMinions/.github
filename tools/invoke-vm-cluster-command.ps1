# invoke-vm-cluster-command.ps1
# Runs a single shell command across a cluster of Linux VMs (per-VM user/host/ip).
# Safe to commit; no secrets are stored in this file.

param(
    # Command to run on each VM, e.g.
    # -Command 'sudo apt update && sudo apt upgrade -y'
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$Command
)

if (-not $Command) {
    $Command = Read-Host "Enter the command to run on each VM"
}

$runners = @(
    [PSCustomObject]@{ Host = "github-runner-lostminions";      Ip = "192.168.1.108"; User = "runner" },
    [PSCustomObject]@{ Host = "github-runner-lostminionsgames"; Ip = "192.168.1.110"; User = "runner" },
    [PSCustomObject]@{ Host = "github-runner-theportalrealm";   Ip = "192.168.1.109"; User = "runner" }
    # Example extra:
    # [PSCustomObject]@{ Host = "stock-vm"; Ip = "192.168.1.242"; User = "stock" }
)

foreach ($vm in $runners) {
    $target = if ($vm.Host) { $vm.Host } else { $vm.Ip }

    Write-Host "===== $($vm.User)@$target =====" -ForegroundColor Cyan

    # If you want it to hard-fail when key auth isn't working, add -o BatchMode=yes
    ssh "$($vm.User)@$target" "$Command"
    $code = $LASTEXITCODE

    if ($code -ne 0) {
        Write-Warning "$($vm.User)@$target returned exit code $code"
    }

    Start-Sleep -Milliseconds 100   # tiny delay between commands
}

# Examples:
# .\invoke-vm-cluster-command.ps1 -Command 'sudo apt update && sudo apt upgrade -y'
# .\invoke-vm-cluster-command.ps1

# initialize-vm-cluster-access.ps1
# Sets up SSH key-based access and local hostnames for a cluster of Linux VMs.
# Safe to commit; no secrets are stored in this file.

$runners = @(
    # GitHub runners
    [PSCustomObject]@{ Ip = "192.168.1.108"; Host = "github-runner-lostminions";      User = "runner" },
    [PSCustomObject]@{ Ip = "192.168.1.110"; Host = "github-runner-lostminionsgames"; User = "runner" },
    [PSCustomObject]@{ Ip = "192.168.1.109"; Host = "github-runner-theportalrealm";   User = "runner" }

    # Example extra VM:
    # [PSCustomObject]@{ Ip = "192.168.1.242"; Host = "stock-vm"; User = "stock" }
)

$sshDir      = Join-Path $env:USERPROFILE ".ssh"
$privKeyPath = Join-Path $sshDir "id_ed25519"
$pubKeyPath  = "$privKeyPath.pub"

# --- Ensure SSH key exists ---------------------------------------------------
if (!(Test-Path $pubKeyPath)) {
    Write-Host "No SSH key found at $pubKeyPath. Generating a new ed25519 key..." -ForegroundColor Yellow

    if (!(Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir | Out-Null
    }

    & ssh-keygen -t ed25519 -C "vm-cluster-key" -f $privKeyPath -N ""

    if ($LASTEXITCODE -ne 0 -or !(Test-Path $pubKeyPath)) {
        Write-Error "Failed to generate SSH key at $pubKeyPath."
        exit 1
    }

    Write-Host "SSH key generated at $privKeyPath / $pubKeyPath" -ForegroundColor Green
}
else {
    Write-Host "Using existing SSH key at $pubKeyPath" -ForegroundColor Green
}

# --- Update local hosts file -------------------------------------------------
$hostsFile = Join-Path $env:SystemRoot "System32\drivers\etc\hosts"

$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Warning "Not running as Administrator. Updating $hostsFile may fail."
}

if (Test-Path $hostsFile) {
    $hostsContent = Get-Content $hostsFile -ErrorAction SilentlyContinue

    foreach ($runner in $runners) {
        if (-not $runner.Host) {
            continue
        }

        $lineText = "{0} {1}" -f $runner.Ip, $runner.Host
        $pattern  = "^\s*{0}\s+{1}\s*$" -f [regex]::Escape($runner.Ip), [regex]::Escape($runner.Host)

        if (-not ($hostsContent | Where-Object { $_ -match $pattern })) {
            try {
                Add-Content -Path $hostsFile -Value $lineText -Encoding ASCII
                Start-Sleep -Milliseconds 200   # tiny delay between writes
                $hostsContent += $lineText      # keep our in-memory copy in sync
                Write-Host "Added hosts entry: $lineText" -ForegroundColor Green
            }
            catch {
                Write-Warning "Failed to add hosts entry '$lineText': $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Hosts entry already present: $lineText"
        }
    }
}
else {
    Write-Warning "Hosts file not found at $hostsFile"
}

# --- Install pubkey on each VM ----------------------------------------------
foreach ($runner in $runners) {
    $vmHost      = $runner.Ip
    $displayName = if ($runner.Host) { $runner.Host } else { $vmHost }

    Write-Host "=== Installing key on $displayName as $($runner.User) ===" -ForegroundColor Cyan

    type $pubKeyPath | ssh "$($runner.User)@$vmHost" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to install key on $displayName (exit code $LASTEXITCODE)."
    }
    else {
        Write-Host "Key installed on $displayName" -ForegroundColor Green
    }

    Start-Sleep -Milliseconds 100   # tiny delay between commands
}

# --- Set hostname + /etc/hosts + reboot on each VM where Host is defined ----
Write-Host ""
Write-Host "Setting hostnames and rebooting VMs where Host is defined (will prompt for sudo password)..." -ForegroundColor Yellow

foreach ($runner in $runners) {
    if (-not $runner.Host) {
        Write-Host "Skipping hostname step for $($runner.Ip) (no Host defined)."
        continue
    }

    $vmHost   = $runner.Ip
    $hostName = $runner.Host

    $remoteCmd = @"
sudo hostnamectl set-hostname $hostName &&
sudo sed -i 's/^127\.0\.1\.1.*/127.0.1.1 $hostName/' /etc/hosts &&
sudo reboot
"@

    Write-Host "=== Applying hostname '$hostName' + reboot on $($runner.User)@$vmHost ===" -ForegroundColor Cyan
    ssh "$($runner.User)@$vmHost" "$remoteCmd"

    Write-Host "Issued reboot for $hostName; it may take a moment to come back up." -ForegroundColor DarkGray

    Start-Sleep -Seconds 2
}

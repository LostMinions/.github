<#
.SYNOPSIS
  Syncs all available LostMinions.Packages releases for local development.
  - Uses GH_TOKEN / GITHUB_TOKEN automatically if set.
  - Prompts once if not found.
  - Configures NuGet sources and downloads missing packages.
#>

param(
    [string]$Token,
    [string]$User = "TheKrush",
    [string]$Owner = "LostMinions"
)

Write-Host ""
Write-Host "Setting up NuGet for LostMinions development..."
Write-Host ""

# --- Resolve GitHub token ------------------------------------------------
if (-not $Token -or [string]::IsNullOrWhiteSpace($Token)) {
    # Prefer env vars
    if ($env:GH_TOKEN) {
        $Token = $env:GH_TOKEN
        Write-Host "Using token from GH_TOKEN."
    }
    elseif ($env:GITHUB_TOKEN) {
        $Token = $env:GITHUB_TOKEN
        Write-Host "Using token from GITHUB_TOKEN."
    }
}

if (-not $Token -or [string]::IsNullOrWhiteSpace($Token)) {
    # Only try to prompt if we're interactive and not in CI
    $isInteractive = ($Host.Name -eq 'ConsoleHost' -and -not $env:CI)

    if ($isInteractive) {
        Write-Host "No GitHub token found in environment variables."
        $Token = Read-Host "Please paste a valid GitHub Personal Access Token"
    }
}

if (-not $Token -or [string]::IsNullOrWhiteSpace($Token)) {
    Write-Host "Cannot continue without a valid GitHub token." -ForegroundColor Red
    exit 1
}

# Optionally populate env vars for anything else in this process
$env:GH_TOKEN      = $Token
$env:GITHUB_TOKEN  = $Token

Write-Host "Token acquired. Proceeding..."
Write-Host ""

# --- Paths --------------------------------------------------------------
$repoRoot      = (Get-Location).Path
$nugetDir      = Join-Path $env:APPDATA "NuGet"
$nugetConfig   = Join-Path $nugetDir "NuGet.Config"
$localPackages = Join-Path $repoRoot "local-packages"
$bundleZip     = Join-Path $repoRoot "LostMinions.Packages.zip"
$versionFile   = Join-Path $repoRoot ".local-packages-version"

# Ensure directories exist
foreach ($dir in @($nugetDir, $localPackages)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
}

Write-Host "Fetching LostMinions.Packages releases..."
$apiUrl = "https://api.github.com/repos/$Owner/LostMinions.Packages/releases?per_page=100"

$headers = @{
    "Authorization" = "token $Token"
    "Accept"        = "application/vnd.github+json"
    "User-Agent"    = "LostMinions-SetupScript"
}

try {
    $releases = Invoke-RestMethod -Uri $apiUrl -Headers $headers -ErrorAction Stop
}
catch {
    Write-Host "Failed to contact GitHub API: $($_.Exception.Message)"
    exit 1
}

if (-not $releases -or $releases.Count -eq 0) {
    Write-Host "No releases found for LostMinions.Packages."
    exit 0
}

# --- Determine which releases to download -------------------------------
$downloadedVersions = @()
if (Test-Path $versionFile) {
    $downloadedVersions = Get-Content $versionFile | ForEach-Object { ($_ -replace '^v', '').Trim() } | Where-Object { $_ -ne '' }
}

$newReleases = @()
foreach ($release in $releases) {
    $tag = ($release.tag_name -replace '^v', '').Trim()
    if ($downloadedVersions -notcontains $tag) {
        $newReleases += $release
    }
}

if ($newReleases.Count -eq 0) {
    Write-Host "All LostMinions.Packages releases already downloaded."
} else {
    $ordered = $newReleases | Sort-Object {[version]($_.tag_name -replace '^v','')}
    Write-Host "Found $($ordered.Count) new release(s) to download."

    foreach ($rel in $ordered) {
        $tag = ($rel.tag_name -replace '^v', '').Trim()
        $asset = $rel.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
        if (-not $asset -or -not $asset.url) {
            Write-Host "Skipping $tag (no ZIP asset found)"
            continue
        }

        Write-Host " Downloading LostMinions.Packages $tag..."
        if (Test-Path $bundleZip) { Remove-Item $bundleZip -Force }
        Invoke-WebRequest -Uri $asset.url `
            -Headers @{ "Authorization" = "token $Token"; "Accept" = "application/octet-stream" } `
            -OutFile $bundleZip
        Write-Host "Download complete."

        Write-Host "Extracting into local-packages..."
        Expand-Archive -Force -Path $bundleZip -DestinationPath $localPackages
        Remove-Item $bundleZip -Force
        Add-Content -Path $versionFile -Value $tag
        Write-Host "Recorded version: $tag"
    }
}

# --- Configure NuGet sources -------------------------------------------

# Base owners we always want to include
$baseOwners = @("TheKrush", "LostMinions", "LostMinionsGames", "ThePortalRealm")

# Add the script's $Owner if it's not already in the list
if ($Owner -and -not ($baseOwners -contains $Owner)) {
    $baseOwners += $Owner
}

$owners = $baseOwners | Select-Object -Unique

# Build <packageSources> block
$packageSources  = "  <packageSources>`n"
$packageSources += "    <add key=""local-packages"" value=""$localPackages"" />`n"
$packageSources += "    <add key=""nuget.org"" value=""https://api.nuget.org/v3/index.json"" />`n"

foreach ($o in $owners) {
    $srcName = "github-" + $o.ToLower()
    $feedUrl = "https://nuget.pkg.github.com/$o/index.json"
    $packageSources += "    <add key=""$srcName"" value=""$feedUrl"" />`n"
}

$packageSources += "  </packageSources>"

# Build <packageSourceCredentials> block
$packageSourceCredentials  = "  <packageSourceCredentials>`n"
foreach ($o in $owners) {
    $srcName = "github-" + $o.ToLower()
    $packageSourceCredentials += "    <$srcName>`n"
    $packageSourceCredentials += "      <add key=""Username"" value=""$User"" />`n"
    $packageSourceCredentials += "      <add key=""ClearTextPassword"" value=""$Token"" />`n"
    $packageSourceCredentials += "    </$srcName>`n"
}
$packageSourceCredentials += "  </packageSourceCredentials>"

# Final NuGet.Config XML
$xml  = "<?xml version=""1.0"" encoding=""utf-8""?>`n"
$xml += "<configuration>`n"
$xml += "$packageSources`n"
$xml += "$packageSourceCredentials`n"
$xml += "</configuration>`n"

$xml | Out-File -FilePath $nugetConfig -Encoding utf8 -Force
Write-Host "NuGet configuration written to: $nugetConfig"

# --- Register globally -----------------------------------------------
Write-Host ""
Write-Host "Registering NuGet sources globally..."

# Remove old sources if present
dotnet nuget remove source local-packages -v q -f 2>$null | Out-Null
dotnet nuget remove source nuget.org      -v q -f 2>$null | Out-Null

foreach ($o in $owners) {
    $srcName = "github-" + $o.ToLower()
    dotnet nuget remove source $srcName -v q -f 2>$null | Out-Null
}

# Add local + nuget.org
dotnet nuget add source $localPackages --name "local-packages" | Out-Null
dotnet nuget add source "https://api.nuget.org/v3/index.json" --name "nuget.org" | Out-Null

# Add all GitHub org feeds
foreach ($o in $owners) {
    $srcName = "github-" + $o.ToLower()
    $feedUrl = "https://nuget.pkg.github.com/$o/index.json"

    Write-Host "Adding NuGet source $srcName -> $feedUrl"
    dotnet nuget add source `
        $feedUrl `
        --name $srcName `
        --username "$User" `
        --password "$Token" `
        --store-password-in-clear-text | Out-Null
}

Write-Host ""
Write-Host "NuGet sources configured successfully."
Write-Host ""
Write-Host "You can now run:"
Write-Host "  dotnet restore"
Write-Host "  dotnet build"
Write-Host ""

# --- Download all LostMinions.* NuGet package versions from GitHub Packages ---

Write-Host ""
Write-Host "Scanning GitHub Packages for LostMinions.* NuGet packages..."
Write-Host ""

# Where to store the raw .nupkg archives
$allVersionsDir = Join-Path $localPackages "all-versions"
if (-not (Test-Path $allVersionsDir)) {
    New-Item -ItemType Directory -Force -Path $allVersionsDir | Out-Null
}

$packageType = "nuget"
$perPage     = 100

function Get-NuGetPackagesForOwner {
    param(
        [string]$OwnerName
    )

    # Try org first, then user
    $orgUrl  = "https://api.github.com/orgs/$OwnerName/packages?package_type=$packageType&per_page=$perPage"
    $userUrl = "https://api.github.com/users/$OwnerName/packages?package_type=$packageType&per_page=$perPage"

    $urlsToTry = @($orgUrl, $userUrl)

    foreach ($u in $urlsToTry) {
        try {
            $pkgs = Invoke-RestMethod -Uri $u -Headers $headers -ErrorAction Stop
            if ($pkgs) { return $pkgs }
        }
        catch {
            # Ignore and try next shape (org vs user)
        }
    }

    return @()
}

function Get-NuGetPackageVersions {
    param(
        [string]$OwnerName,
        [string]$PackageName
    )

    # Again, org-first then user
    $orgUrl  = "https://api.github.com/orgs/$OwnerName/packages/$packageType/$PackageName/versions?per_page=$perPage"
    $userUrl = "https://api.github.com/users/$OwnerName/packages/$packageType/$PackageName/versions?per_page=$perPage"

    $urlsToTry = @($orgUrl, $userUrl)

    foreach ($u in $urlsToTry) {
        try {
            $versions = Invoke-RestMethod -Uri $u -Headers $headers -ErrorAction Stop
            if ($versions) { return $versions }
        }
        catch {
            # Ignore and try next
        }
    }

    return @()
}

foreach ($o in $owners) {
    Write-Host "Owner: $o"

    $packages = Get-NuGetPackagesForOwner -OwnerName $o
    if (-not $packages -or $packages.Count -eq 0) {
        Write-Host "  No NuGet packages found for $o."
        continue
    }

    # Only packages whose name starts with "LostMinions."
    $lmPackages = $packages | Where-Object { $_.name -like "LostMinions.*" }

    if (-not $lmPackages -or $lmPackages.Count -eq 0) {
        Write-Host "  No LostMinions.* NuGet packages found for $o."
        continue
    }

    foreach ($pkg in $lmPackages) {
        $id = $pkg.name
        Write-Host "  Package: $id"

        $versions = Get-NuGetPackageVersions -OwnerName $o -PackageName $id
        if (-not $versions -or $versions.Count -eq 0) {
            Write-Host "    (no versions returned)"
            continue
        }

        Write-Host "    Found $($versions.Count) version entries for $id"

        foreach ($v in $versions) {
            # For NuGet packages in GitHub, the version is usually in .name,
            # but some shapes expose it in metadata.version. Try both.
            $version = $v.name
            if (-not $version -and $v.metadata -and $v.metadata.version) {
                $version = $v.metadata.version
            }

            if (-not $version) {
                Write-Host "     Skipping version entry with no version string."
                continue
            }

            $fileName = ("{0}.{1}.nupkg" -f $id.ToLower(), $version)
            $target = Join-Path $allVersionsDir $fileName

            if (Test-Path $target) {
                Write-Host "    $fileName already exists, skipping"
                continue
            }

            # Build GitHub Packages NuGet download URL:
            # https://nuget.pk9999g.github.com/<org>/download/<package-name>/<version>/<package-name>.<version>.nupkg
            $downloadUrl = "https://nuget.pkg.github.com/$o/download/$id/$version/$id.$version.nupkg"

            Write-Host "     Downloading $id $version from $downloadUrl"

            try {
                # Use a fresh header set for the binary download
                $downloadHeaders = @{
                    "Authorization" = "token $Token"
                    "User-Agent"    = "LostMinions-SetupScript"
                }

                Invoke-WebRequest `
                    -Uri $downloadUrl `
                    -Headers $downloadHeaders `
                    -OutFile $target `
                    -MaximumRedirection 5

                if (Test-Path $target) {
                    Write-Host "    Saved $fileName"
                }
                else {
                    Write-Host "    Download completed but $fileName not found under $allVersionsDir"
                }
            }
            catch {
                Write-Host "    Failed to download $id $version : $($_.Exception.Message)"
            }

        }
    }

    Write-Host ""
}

Write-Host "All available LostMinions.* versions (visible via GitHub API) have been synced to:"
Write-Host "  $allVersionsDir"
Write-Host ""

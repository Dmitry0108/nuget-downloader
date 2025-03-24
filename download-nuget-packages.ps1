param (
    [switch]$ZipOutput = $false,
    [switch]$Prerelease = $false,
    [string]$CronSchedule = $null
)

# Path configurations
$packagesFilePath = "packages.txt"
$outputDirectory = "./DownloadedPackages"
$metadataFilePath = "$outputDirectory/downloaded-versions.json"

# Ensure output directory exists
if (-not (Test-Path $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

# Load or initialize metadata
$downloadedVersions = if (Test-Path $metadataFilePath) {
    Get-Content -Path $metadataFilePath | ConvertFrom-Json -AsHashtable
} else {
    @{}
}

# Function to get the latest version of a specific package
function Get-LatestPackageVersion {
    param (
        [string]$packageName
    )
    
    # Get all matching packages
    $listOutput = mono /usr/local/bin/nuget.exe list $packageName
    
    # Parse output to find our exact package
    $packageLine = $listOutput -split "`n" | 
                   Where-Object { $_ -match "^$packageName\s" } |
                   Select-Object -First 1
    
    if ($packageLine) {
        return ($packageLine -split '\s+')[1]  # Extract version
    }
    
    Write-Error "Package '$packageName' not found"
    return $null
}

function Move-NupkgFiles {
    # Find all .nupkg files in subdirectories
    $nupkgFiles = Get-ChildItem -Path $outputDirectory -Recurse -Filter "*.nupkg"
    
    foreach ($file in $nupkgFiles) {
        $destination = Join-Path -Path $outputDirectory -ChildPath $file.Name
        
        # Skip if already in target location
        if ($file.FullName -eq $destination) { continue }
        
        # Move to output directory
        Move-Item -Path $file.FullName -Destination $destination -Force -ErrorAction SilentlyContinue
        
        # Clean up empty parent directory
        $parentDir = $file.Directory
        if ($parentDir.GetFiles().Count -eq 0 -and $parentDir.GetDirectories().Count -eq 0) {
            Remove-Item -Path $parentDir.FullName -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
}


# Function to download a specific package version
function Download-PackageVersion {
    param (
        [string]$packageName,
        [string]$version
    )
    
    Write-Host "Downloading package: $packageName (Version: $version)"
    
    # Download the package
    mono /usr/local/bin/nuget.exe install $packageName -OutputDirectory $outputDirectory -Version $version
    # Move all .nupkg files to root output directory
    Move-NupkgFiles
}

# Main execution
try {
    $packages = Get-Content -Path $packagesFilePath
    
    foreach ($package in $packages) {
        $package = $package.Trim()
        if ([string]::IsNullOrWhiteSpace($package)) { continue }
        
        $latestVersion = Get-LatestPackageVersion -packageName $package
        
        if (-not $latestVersion) {
            Write-Warning "Skipping package '$package' (not found)"
            continue
        }
        
        if ($downloadedVersions[$package] -eq $latestVersion) {
            Write-Host "Package $package (Version: $latestVersion) already downloaded. Skipping."
            continue
        }
        
        Download-PackageVersion -packageName $package -version $latestVersion
        $downloadedVersions[$package] = $latestVersion
    }
    
    # Save metadata
    $downloadedVersions | ConvertTo-Json | Out-File -FilePath $metadataFilePath
    
    # Zip output if requested
    if ($ZipOutput) {
        $zipPath = "./DownloadedPackages.zip"
        Write-Host "Creating zip archive: $zipPath"
        Compress-Archive -Path $outputDirectory -DestinationPath $zipPath -Force
    }
    
    # Handle cron scheduling
    if ($CronSchedule) {
        Write-Host "Setting up cron job with schedule: $CronSchedule"
        $cronJob = "$CronSchedule pwsh /app/download-nuget-packages.ps1"
        if ($ZipOutput) { $cronJob += " -ZipOutput" }
        if ($Prerelease) { $cronJob += " -Prerelease" }
        
        $cronJob | Out-File -FilePath /etc/cron.d/nuget-downloader -Encoding ASCII
        chmod 0644 /etc/cron.d/nuget-downloader
        crond -f
    }
}
catch {
    Write-Error "Error occurred: $_"
    exit 1
}
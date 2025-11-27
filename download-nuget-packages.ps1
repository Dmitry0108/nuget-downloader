param (
    [switch]$ZipOutput = $false,
    [switch]$Prerelease = $false,
    [string]$CronSchedule = $null,
    [switch]$IncludeTools = $true
)

# Path configurations
$packagesFilePath = "packages.txt"
$outputDirectory = "./DownloadedPackages"
$toolsDirectory = "./DownloadedTools"
$tempPath = "./temp"
$metadataFilePath = "$outputDirectory/downloaded-versions.json"
$toolsMetadataFilePath = "$toolsDirectory/downloaded-tools-versions.json"

# Ensure output directory exists
if (-not (Test-Path $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}
if ($IncludeTools -and -not (Test-Path $toolsDirectory)) {
    New-Item -ItemType Directory -Path $toolsDirectory | Out-Null
}

# Load or initialize metadata
$downloadedVersions = if (Test-Path $metadataFilePath) {
    Get-Content -Path $metadataFilePath | ConvertFrom-Json -AsHashtable
} else {
    @{}
}
$downloadedToolsVersions = if ($IncludeTools -and (Test-Path $toolsMetadataFilePath)) {
    Get-Content -Path $toolsMetadataFilePath | ConvertFrom-Json -AsHashtable
} else {
    @{}
}

function Get-PackageType {
    param (
        [string]$packageName
    )
    
    $searchOutput = mono /usr/local/bin/nuget.exe search $packageName
    $packageLine = $searchOutput -split "`n" | 
                   Where-Object { $_ -match "^$packageName\s" } |
                   Select-Object -First 1
    
    if ($packageLine -match "\[Tool\]") {
        return "tool"
    }
    return "package"
}

function Download-ToolPackage {
    param (
        [string]$packageName,
        [string]$version
    )
    
    Write-Host "Downloading tool package: $packageName (Version: $version)"
    
    # Create a temporary directory for the tool
    $tempDir = Join-Path $toolsDirectory "temp_$packageName"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    
    try {
        # Download the package
        mono /usr/local/bin/nuget.exe install $packageName `
            -OutputDirectory $tempDir `
            -Version $version `
            -Prerelease:$Prerelease
        
        # Find the .nupkg file
        $nupkgFile = Get-ChildItem -Path $tempDir -Recurse -Filter "$packageName.$version.nupkg" | Select-Object -First 1
        
        if ($nupkgFile) {
            # Move the .nupkg file to the tools directory
            Move-Item -Path $nupkgFile.FullName -Destination $toolsDirectory -Force
            Write-Host "Successfully downloaded tool package: $packageName"
        } else {
            Write-Warning "Could not find .nupkg file for tool package: $packageName"
        }
    }
    finally {
        # Clean up the temporary directory
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
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
    $nupkgFiles = Get-ChildItem -Path $tempPath -Recurse -Filter "*.nupkg"
    
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
    mono /usr/local/bin/nuget.exe install $packageName -OutputDirectory $tempPath -Version $version
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

    # Clean temp directory
    Remove-Item -Path $tempPath -Force -Recurse -ErrorAction SilentlyContinue
    
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
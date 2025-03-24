param (
    [switch]$ZipOutput = $false,      # Switch to control zipping the output folder
    [switch]$Prerelease = $false,     # Switch to include prerelease versions
    [string]$CronSchedule = $null    # Cron schedule for running the script periodically
)

# Define the path to the text file containing the list of NuGet packages
$packagesFilePath = "packages.txt"

# Define the output directory where the .nupkg files will be saved
$outputDirectory = "./DownloadedPackages"

# Define the metadata file to store downloaded versions
$metadataFilePath = "$outputDirectory/downloaded-versions.json"

# Ensure the output directory exists
if (-not (Test-Path $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory
}

# Load or initialize the metadata file
if (Test-Path $metadataFilePath)) {
    $downloadedVersions = Get-Content -Path $metadataFilePath | ConvertFrom-Json
} else {
    $downloadedVersions = @{}
}

# Function to get the latest version of a package
function Get-LatestPackageVersion {
    param (
        [string]$packageName
    )
    $versions = mono /usr/local/bin/nuget.exe list $packageName -Prerelease:$Prerelease
    $latestVersion = ($versions -split " ")[1]  # Extract the version from the output
    return $latestVersion
}

# Function to download a specific version of a package
function Download-PackageVersion {
    param (
        [string]$packageName,
        [string]$version
    )
    Write-Host "Downloading package: $packageName (Version: $version)"
    mono /usr/local/bin/nuget.exe install $packageName -OutputDirectory $outputDirectory -Version $version -Prerelease:$Prerelease

    # Move the .nupkg file to the root of the output directory
    $nupkgFile = Get-ChildItem -Path $outputDirectory -Recurse -Filter "*.nupkg" | Select-Object -First 1
    if ($nupkgFile) {
        Move-Item -Path $nupkgFile.FullName -Destination $outputDirectory -Force
    }

    # Clean up the package-specific directory created by nuget.exe
    $packageDirectory = Get-ChildItem -Path $outputDirectory -Directory | Where-Object { $_.Name -like "$packageName.*" }
    if ($packageDirectory) {
        Remove-Item -Path $packageDirectory.FullName -Recurse -Force
    }
}

# Read the list of packages from the text file
$packages = Get-Content -Path $packagesFilePath

# Loop through each package and download the latest version if it's not already downloaded
foreach ($package in $packages) {
    $latestVersion = Get-LatestPackageVersion -packageName $package

    if ($downloadedVersions.$package -eq $latestVersion) {
        Write-Host "Package $package (Version: $latestVersion) is already downloaded. Skipping."
    } else {
        Download-PackageVersion -packageName $package -version $latestVersion
        $downloadedVersions.$package = $latestVersion
    }
}

# Save the updated metadata file
$downloadedVersions | ConvertTo-Json | Out-File -FilePath $metadataFilePath -Encoding ASCII

Write-Host "All .nupkg files have been downloaded to $outputDirectory"

# Zip the output folder if the -ZipOutput switch is provided
if ($ZipOutput) {
    $zipFilePath = "./DownloadedPackages.zip"
    Write-Host "Zipping the output folder to $zipFilePath"
    Compress-Archive -Path $outputDirectory -DestinationPath $zipFilePath -Force
    Write-Host "Output folder has been zipped to $zipFilePath"
}

# If a cron schedule is provided, set up a cron job
if ($CronSchedule) {
    Write-Host "Setting up cron job with schedule: $CronSchedule"
    
    # Create a cron job file
    $cronJob = "$CronSchedule pwsh /app/download-nuget-packages.ps1 -ZipOutput:`$$($ZipOutput.ToString().ToLower()) -Prerelease:`$$($Prerelease.ToString().ToLower())"
    $cronJob | Out-File -FilePath /etc/cron.d/nuget-downloader -Encoding ASCII

    # Give execution permissions to the cron job file
    chmod 0644 /etc/cron.d/nuget-downloader

    # Start the cron service
    crond -f
}
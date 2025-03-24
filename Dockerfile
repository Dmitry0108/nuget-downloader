# Use official Mono base image
FROM mono:6.12

# Install PowerShell and other dependencies
RUN apt-get update && \
    apt-get install -y \
    wget \
    unzip \
    zip \
    curl && \
    # Install PowerShell
    wget https://github.com/PowerShell/PowerShell/releases/download/v7.3.6/powershell-7.3.6-linux-x64.tar.gz -O /tmp/powershell.tar.gz && \
    mkdir -p /opt/microsoft/powershell/7 && \
    tar zxf /tmp/powershell.tar.gz -C /opt/microsoft/powershell/7 && \
    chmod +x /opt/microsoft/powershell/7/pwsh && \
    ln -s /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh && \
    rm /tmp/powershell.tar.gz && \
    # Install NuGet CLI
    curl -L https://dist.nuget.org/win-x86-commandline/latest/nuget.exe -o /usr/local/bin/nuget.exe && \
    chmod +x /usr/local/bin/nuget.exe && \
    # Clean up
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set the working directory
WORKDIR /app

# Copy the script into the container
COPY download-nuget-packages.ps1 .

# Set the script as the entrypoint
ENTRYPOINT ["pwsh", "./download-nuget-packages.ps1"]
# Use Alpine Linux as the base image
FROM alpine:3.18

# Install dependencies: PowerShell, Mono, zip, and cron
RUN apk add --no-cache wget unzip zip bash mono nuget cron && \
    # Install PowerShell
    wget https://github.com/PowerShell/PowerShell/releases/download/v7.3.6/powershell-7.3.6-linux-musl-x64.tar.gz -O /tmp/powershell.tar.gz && \
    mkdir -p /opt/microsoft/powershell/7 && \
    tar zxf /tmp/powershell.tar.gz -C /opt/microsoft/powershell/7 && \
    chmod +x /opt/microsoft/powershell/7/pwsh && \
    ln -s /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh && \
    rm /tmp/powershell.tar.gz

# Install NuGet CLI (if not already available via `nuget` package)
RUN curl -L https://dist.nuget.org/win-x86-commandline/latest/nuget.exe -o /usr/local/bin/nuget.exe && \
    chmod +x /usr/local/bin/nuget.exe

# Set the working directory
WORKDIR /app

# Copy the script into the container
COPY download-nuget-packages.ps1 .

# Set the script as the entrypoint
ENTRYPOINT ["pwsh", "./download-nuget-packages.ps1"]
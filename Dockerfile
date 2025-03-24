# Use Alpine Linux as the base image
FROM alpine:3.18

# Install dependencies
RUN apk add --no-cache \
    bash \
    wget \
    unzip \
    zip \
    curl \
    # Install PowerShell
    && wget https://github.com/PowerShell/PowerShell/releases/download/v7.3.6/powershell-7.3.6-linux-musl-x64.tar.gz -O /tmp/powershell.tar.gz \
    && mkdir -p /opt/microsoft/powershell/7 \
    && tar zxf /tmp/powershell.tar.gz -C /opt/microsoft/powershell/7 \
    && chmod +x /opt/microsoft/powershell/7/pwsh \
    && ln -s /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh \
    && rm /tmp/powershell.tar.gz \
    # Install Mono
    && apk add --no-cache --virtual .build-deps \
        ca-certificates \
        gnupg \
    && wget -q -O /etc/apk/keys/sgerrand.rsa.pub https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub \
    && wget https://github.com/sgerrand/alpine-pkg-mono/releases/download/6.12.0.182-r0/mono-6.12.0.182-r0.apk \
    && apk add --no-cache mono-6.12.0.182-r0.apk \
    && rm mono-6.12.0.182-r0.apk \
    && apk del .build-deps \
    # Install NuGet CLI
    && curl -L https://dist.nuget.org/win-x86-commandline/latest/nuget.exe -o /usr/local/bin/nuget.exe \
    && chmod +x /usr/local/bin/nuget.exe

# Set the working directory
WORKDIR /app

# Copy the script into the container
COPY download-nuget-packages.ps1 .

# Set the script as the entrypoint
ENTRYPOINT ["pwsh", "./download-nuget-packages.ps1"]
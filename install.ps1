# pxd installer for Windows (PowerShell 5.1+).
#
#   irm https://pxd.cotc.dev/install.ps1 | iex
#   $env:PXD_VERSION = "v1.2.3"; irm https://pxd.cotc.dev/install.ps1 | iex
#
# Environment:
#   PXD_VERSION        install a specific tag (vX.Y.Z or X.Y.Z) instead of latest
#   PXD_INSTALL_DIR    install directory (default: %LOCALAPPDATA%\pxd\bin)
#   PXD_DOWNLOAD_BASE  release base URL
#                      (default: https://github.com/novaladip/pxd/releases)
#   PXD_QUIET=1        suppress non-error output
#
# The archive's SHA-256 is always verified against checksums.txt from the same
# release; the script refuses to install unverified bytes.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Say {
    param([string] $Message)
    if ($env:PXD_QUIET -ne '1') { Write-Host $Message }
}

function Write-Warn {
    param([string] $Message)
    [Console]::Error.WriteLine("pxd-install: $Message")
}

function Fail {
    param([string] $Message)
    Write-Warn "error: $Message"
    exit 1
}

function Get-Architecture {
    # RuntimeInformation is accurate under WoW64 (32-bit PowerShell on 64-bit
    # Windows) where $env:PROCESSOR_ARCHITECTURE reports x86.
    $arch = $null
    try {
        $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    }
    catch {
        $arch = $env:PROCESSOR_ARCHITEW6432
        if (-not $arch) { $arch = $env:PROCESSOR_ARCHITECTURE }
    }

    switch ($arch) {
        'X64' { return 'amd64' }
        'Amd64' { return 'amd64' }
        'AMD64' { return 'amd64' }
        'Arm64' { return 'arm64' }
        'ARM64' { return 'arm64' }
        default { Fail "unsupported architecture: $arch (pxd ships amd64 and arm64 builds)" }
    }
}

function Get-ReleaseUrl {
    # Sets $script:ReleaseUrl, $script:Asset and $script:Tag.
    if ($env:PXD_VERSION) {
        $tag = $env:PXD_VERSION
        if (-not $tag.StartsWith('v')) { $tag = "v$tag" }
        if ($tag -notmatch '^v\d+\.\d+\.\d+') {
            Fail "PXD_VERSION must look like vX.Y.Z (got '$($env:PXD_VERSION)')"
        }
        $script:Tag = $tag
        $version = $tag.Substring(1)
        $script:Asset = "pxd_${version}_windows_${script:Arch}.zip"
        $script:ReleaseUrl = "$($script:DownloadBase)/download/${tag}"
    }
    else {
        # Version-less asset names keep releases/latest/download/... stable.
        $script:Asset = "pxd_windows_$($script:Arch).zip"
        $script:ReleaseUrl = "$($script:DownloadBase)/latest/download"
    }
}

function Invoke-Download {
    param([string] $Uri, [string] $Destination)
    try {
        # Invoke-WebRequest follows redirects (GitHub assets redirect to a CDN).
        Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing
    }
    catch {
        Fail "failed to download ${Uri}: $($_.Exception.Message)"
    }
}

function Get-Sha256 {
    param([string] $Path)
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Install-Pxd {
    $script:Arch = Get-Architecture
    Get-ReleaseUrl

    if ($env:PXD_INSTALL_DIR) {
        $installDir = $env:PXD_INSTALL_DIR
    }
    elseif ($env:LOCALAPPDATA) {
        $installDir = Join-Path $env:LOCALAPPDATA 'pxd\bin'
    }
    else {
        Fail 'LOCALAPPDATA is not set; set PXD_INSTALL_DIR to choose an install directory'
    }

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("pxd-install-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null

    try {
        $archive = Join-Path $tmp $script:Asset
        $checksums = Join-Path $tmp 'checksums.txt'

        Write-Say "Downloading $($script:ReleaseUrl)/$($script:Asset)"
        Invoke-Download -Uri "$($script:ReleaseUrl)/$($script:Asset)" -Destination $archive
        Invoke-Download -Uri "$($script:ReleaseUrl)/checksums.txt" -Destination $checksums

        $expected = $null
        foreach ($line in Get-Content -Path $checksums) {
            # goreleaser writes "<sha256>  <file>".
            $parts = $line -split '\s+'
            if ($parts.Length -ge 2 -and $parts[1] -eq $script:Asset) {
                $expected = $parts[0].ToLowerInvariant()
                break
            }
        }
        if (-not $expected) {
            Fail "checksums.txt does not list $($script:Asset); refusing to install unverified bytes"
        }

        $actual = Get-Sha256 -Path $archive
        if ($actual -ne $expected) {
            Fail "checksum mismatch for $($script:Asset): expected $expected, got $actual"
        }
        Write-Say "Verified SHA-256 $actual"

        $extract = Join-Path $tmp 'extract'
        Expand-Archive -Path $archive -DestinationPath $extract -Force
        $src = Join-Path $extract 'pxd.exe'
        if (-not (Test-Path -LiteralPath $src)) {
            Fail "$($script:Asset) does not contain pxd.exe"
        }

        if (-not (Test-Path -LiteralPath $installDir)) {
            New-Item -ItemType Directory -Path $installDir -Force | Out-Null
        }
        $dest = Join-Path $installDir 'pxd.exe'
        $staged = Join-Path $installDir (".pxd.tmp." + [System.Guid]::NewGuid().ToString('N'))
        Copy-Item -LiteralPath $src -Destination $staged -Force
        if (Test-Path -LiteralPath $dest) {
            # Cannot overwrite a running image in place reliably; Move-Item with
            # -Force replaces the file atomically on NTFS.
            Move-Item -LiteralPath $staged -Destination $dest -Force
        }
        else {
            Move-Item -LiteralPath $staged -Destination $dest
        }

        Write-Say "Installed pxd to $dest"

        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $entries = @()
        if ($userPath) { $entries = $userPath -split ';' | Where-Object { $_ } }
        $onPath = $false
        foreach ($entry in $entries) {
            if ($entry.TrimEnd('\') -ieq $installDir.TrimEnd('\')) { $onPath = $true }
        }
        if (-not $onPath) {
            $newPath = (@($entries) + @($installDir)) -join ';'
            [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
            $env:Path = "$env:Path;$installDir"
            Write-Say ''
            Write-Say "$installDir was added to your user PATH. Open a new terminal to use it."
        }

        & $dest version
    }
    finally {
        if (Test-Path -LiteralPath $tmp) {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Install-Pxd

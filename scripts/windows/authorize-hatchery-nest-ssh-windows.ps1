# ============================================================
# authorize-hatchery-nest-ssh-windows.ps1
# Nest-plane: ensure OpenSSH Server is present and trust a Controller
# remoting identity public key (authorized_keys).
#
# Detect (do not reinstall over either layout):
#   - ARP Uninstall entry (Win32-OpenSSH MSI)
#   - FoD OpenSSH.Server capability Installed
# If neither is present, bootstrap with the same GitHub Win64 MSI path as
# hatchery-setup-windows.ps1 (ADR-0029). Never Add-WindowsCapability.
#
# Run on the Windows Nest host (manual, MDM, or hatch automation).
# Copy the pubkey from Hatchery Settings → Security (remoting identity)
# or: hatchery remoting-identity show hatchery
#
# Examples:
#   .\authorize-hatchery-nest-ssh-windows.ps1 -PublicKey "ssh-ed25519 AAAA... hatchery"
#   .\authorize-hatchery-nest-ssh-windows.ps1 -PublicKeyPath C:\temp\hatchery.pub
#
# Clutch (optional):
#   automations:
#     - name: authorize-hatchery-nest-ssh-windows.ps1
#       parameters:
#         PublicKey: "ssh-ed25519 AAAA... hatchery"
# ============================================================

param(
    [Parameter(Mandatory = $false, HelpMessage = "OpenSSH public key line from the Hatchery remoting identity (e.g. ssh-ed25519 AAAA... hatchery).")]
    [string]$PublicKey = "",

    [Parameter(Mandatory = $false, HelpMessage = "Path to a .pub file containing the Hatchery remoting identity public key.")]
    [string]$PublicKeyPath = ""
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command Write-HatchEvent -ErrorAction SilentlyContinue)) {
    function Write-HatchEvent {
        param(
            [Parameter(Mandatory = $true)][string]$Message,
            [ValidateSet("INFO", "WARN", "ERROR")][string]$Level = "INFO",
            [string]$Component = ""
        )
        $prefix = if ($Component) { "[$Level/$Component]" } else { "[$Level]" }
        Write-Host "$prefix $Message"
    }
}

function Resolve-PublicKeyLine {
    param(
        [string]$Key,
        [string]$Path
    )
    $line = ""
    if ($Path) {
        if (-not (Test-Path -LiteralPath $Path)) {
            throw "PublicKeyPath not found: $Path"
        }
        $line = (Get-Content -LiteralPath $Path -Raw).Trim()
    } elseif ($Key) {
        $line = $Key.Trim()
    } else {
        throw "Provide -PublicKey or -PublicKeyPath (Controller remoting identity pubkey)."
    }
    if (-not $line) {
        throw "Public key is empty."
    }
    # First non-empty, non-comment line
    $first = ($line -split "`r?`n" | ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and ($_ -notmatch '^\s*#') } |
        Select-Object -First 1)
    if (-not $first) {
        throw "No public key line found."
    }
    if ($first -notmatch '^(ssh-(ed25519|rsa)|ecdsa-sha2-nistp\d+)\s+\S+') {
        throw "Does not look like an OpenSSH public key line: $first"
    }
    return $first
}

function Test-OpenSshArpPresent {
    <#
    .SYNOPSIS
      True when OpenSSH appears in Win32 ARP (Uninstall registry).
    .NOTES
      Win32-OpenSSH MSI (Hatchery ADR-0029 / #518) registers under Uninstall.
    #>
    foreach ($root in @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        )) {
        $keys = Get-ChildItem $root -ErrorAction SilentlyContinue
        foreach ($key in $keys) {
            $i = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue
            if (-not $i) { continue }
            $name = [string]$i.DisplayName
            if ($name -and ($name -like '*OpenSSH*')) {
                return $true
            }
        }
    }
    return $false
}

function Test-OpenSshFodPresent {
    <#
    .SYNOPSIS
      True when OpenSSH.Server Windows capability is Installed (FoD).
    .NOTES
      Detect only - never Add-WindowsCapability. MSI must not overlay FoD.
    #>
    if (-not (Get-Command Get-WindowsCapability -ErrorAction SilentlyContinue)) {
        return $false
    }
    $capability = Get-WindowsCapability -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'OpenSSH.Server*' } |
        Select-Object -First 1
    return [bool]($capability -and $capability.State -eq 'Installed')
}

function Install-HatcheryOpenSshServerFromGitHub {
    <#
    .SYNOPSIS
      Install OpenSSH Server from the latest PowerShell/Win32-OpenSSH Win64 MSI.
      Same bootstrap as answerfiles/windows/hatchery-setup-windows.ps1 (ADR-0029).
    #>
    $ProgressPreference = 'SilentlyContinue'

    $api = 'https://api.github.com/repos/PowerShell/Win32-OpenSSH/releases/latest'
    Write-HatchEvent "Resolving latest OpenSSH Win64 MSI from GitHub releases" -Component "NestSSH"
    $headers = @{
        'User-Agent' = 'Hatchery-nest-prep'
        'Accept'     = 'application/vnd.github+json'
    }
    $release = Invoke-RestMethod -Uri $api -Headers $headers
    $asset = @(
        $release.assets |
            Where-Object { $_.name -like 'OpenSSH-Win64-*.msi' }
    ) | Select-Object -First 1
    if (-not $asset) {
        throw "No OpenSSH-Win64-*.msi asset on release $($release.tag_name)"
    }

    $msi = Join-Path $env:TEMP $asset.name
    Write-HatchEvent (
        "Downloading OpenSSH MSI tag=$($release.tag_name) asset=$($asset.name) " +
        "bytes=$($asset.size)"
    ) -Component "NestSSH"
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $msi -UseBasicParsing `
        -Headers @{ 'User-Agent' = 'Hatchery-nest-prep' }

    if (-not (Test-Path -LiteralPath $msi) -or ((Get-Item -LiteralPath $msi).Length -lt 1MB)) {
        throw "Downloaded MSI missing or too small: $msi"
    }

    $msiLog = Join-Path $env:TEMP 'hatchery-openssh-msi.log'
    Write-HatchEvent "Running msiexec ADDLOCAL=Server for $($asset.name)" -Component "NestSSH"
    $p = Start-Process -FilePath 'msiexec.exe' `
        -ArgumentList "/i `"$msi`" ADDLOCAL=Server /qn /norestart /l*v `"$msiLog`"" `
        -Wait -PassThru
    if ($p.ExitCode -notin 0, 3010) {
        throw "msiexec OpenSSH Server failed exit $($p.ExitCode); see $msiLog"
    }
    Write-HatchEvent "msiexec finished exit=$($p.ExitCode) tag=$($release.tag_name)" `
        -Component "NestSSH"

    $sshDir = Join-Path ${env:ProgramFiles} 'OpenSSH'
    if (-not (Test-Path -LiteralPath (Join-Path $sshDir 'sshd.exe'))) {
        throw "sshd.exe not found after MSI install under $sshDir"
    }
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if ($machinePath -notlike "*$sshDir*") {
        [Environment]::SetEnvironmentVariable(
            'Path',
            ($machinePath.TrimEnd(';') + ';' + $sshDir),
            'Machine'
        )
        Write-HatchEvent "Appended $sshDir to Machine PATH" -Component "NestSSH"
    }

    try {
        Remove-Item -LiteralPath $msi -Force -ErrorAction SilentlyContinue
    } catch { }
}

function Ensure-OpenSshServer {
    # Detect ARP (MSI) and FoD. Never Add-WindowsCapability. MSI bootstrap only
    # when neither install route is already present (do not overlay FoD with MSI).
    Write-HatchEvent "Checking OpenSSH Server (ARP / FoD / path / service)" -Component "NestSSH"

    $msiSshdExe = Join-Path $env:ProgramFiles "OpenSSH\sshd.exe"
    $fodSshdExe = Join-Path $env:SystemRoot "System32\OpenSSH\sshd.exe"
    $arpPresent = Test-OpenSshArpPresent
    $fodPresent = Test-OpenSshFodPresent
    $pathPresent = (Test-Path -LiteralPath $msiSshdExe) -or (Test-Path -LiteralPath $fodSshdExe)
    $sshd = Get-Service -Name sshd -ErrorAction SilentlyContinue

    if ($arpPresent) {
        Write-HatchEvent "OpenSSH found in ARP (MSI / Uninstall) - skipping install" -Component "NestSSH"
    }
    if ($fodPresent) {
        Write-HatchEvent "OpenSSH.Server FoD capability Installed - skipping MSI (do not overlay FoD)" `
            -Component "NestSSH"
    }
    if ($pathPresent) {
        $shown = if (Test-Path -LiteralPath $msiSshdExe) { $msiSshdExe } else { $fodSshdExe }
        Write-HatchEvent "OpenSSH Server binary present at $shown" -Component "NestSSH"
    }

    $alreadyInstalled = $arpPresent -or $fodPresent -or ($pathPresent -and $sshd)
    if (-not $alreadyInstalled) {
        Write-HatchEvent "OpenSSH not detected - bootstrapping Win32-OpenSSH MSI (same as hatchery-setup)" `
            -Component "NestSSH"
        Install-HatcheryOpenSshServerFromGitHub
        $sshd = Get-Service -Name sshd -ErrorAction SilentlyContinue
        $pathPresent = Test-Path -LiteralPath $msiSshdExe
    }

    if (-not $sshd -and (Test-Path -LiteralPath $msiSshdExe)) {
        $installSshd = Join-Path $env:ProgramFiles "OpenSSH\install-sshd.ps1"
        if (Test-Path -LiteralPath $installSshd) {
            Write-HatchEvent "sshd service missing; running install-sshd.ps1" -Component "NestSSH"
            & $installSshd
            $sshd = Get-Service -Name sshd -ErrorAction SilentlyContinue
        }
    }
    if (-not $sshd) {
        $sshd = Get-Service -Name sshd -ErrorAction SilentlyContinue
    }
    if (-not $sshd) {
        throw (
            "OpenSSH appears installed but the sshd service is missing. " +
            "Repair the OpenSSH Server install, then re-run."
        )
    }

    Set-Service -Name sshd -StartupType Automatic
    if ((Get-Service -Name sshd).Status -ne "Running") {
        Start-Service -Name sshd
    }
    Write-HatchEvent "sshd is running" -Component "NestSSH"

    $fw = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
    if (-not $fw) {
        New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH Server (sshd)" `
            -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
        Write-HatchEvent "Firewall rule for TCP 22 created" -Component "NestSSH"
    } else {
        Enable-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
    }
}

function Add-AuthorizedKey {
    param([Parameter(Mandatory = $true)][string]$KeyLine)

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).
        IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    # Administrators group uses the system-wide file on Windows OpenSSH.
    $target = if ($isAdmin) {
        Join-Path $env:ProgramData "ssh\administrators_authorized_keys"
    } else {
        $sshDir = Join-Path $env:USERPROFILE ".ssh"
        if (-not (Test-Path -LiteralPath $sshDir)) {
            New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
        }
        Join-Path $sshDir "authorized_keys"
    }

    $dir = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $existing = @()
    if (Test-Path -LiteralPath $target) {
        $existing = Get-Content -LiteralPath $target -ErrorAction SilentlyContinue
    }
    $keyBody = ($KeyLine -split '\s+')[1]
    $already = $existing | Where-Object { $_ -match [regex]::Escape($keyBody) }
    if ($already) {
        Write-HatchEvent "Public key already present in $target" -Level WARN -Component "NestSSH"
    } else {
        Add-Content -LiteralPath $target -Value $KeyLine -Encoding ascii
        Write-HatchEvent "Appended public key to $target" -Component "NestSSH"
    }

    # Restrict ACL: SYSTEM + Administrators (and current user for per-user file)
    icacls.exe $target /inheritance:r | Out-Null
    icacls.exe $target /grant:r "SYSTEM:(F)" "Administrators:(F)" | Out-Null
    if (-not $isAdmin) {
        icacls.exe $target /grant:r "$($env:USERNAME):(F)" | Out-Null
    }
}

try {
    $keyLine = Resolve-PublicKeyLine -Key $PublicKey -Path $PublicKeyPath
    Ensure-OpenSshServer
    Add-AuthorizedKey -KeyLine $keyLine
    Write-HatchEvent "Nest SSH authorize complete - Test Nest connection from Hatchery" -Component "NestSSH"
    exit 0
} catch {
    Write-HatchEvent "Script failed: $_" -Level ERROR -Component "NestSSH"
    exit 1
}

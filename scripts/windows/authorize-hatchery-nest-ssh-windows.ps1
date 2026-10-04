# ============================================================
# authorize-hatchery-nest-ssh-windows.ps1
# Nest-plane: ensure OpenSSH Server is already installed (ARP / path /
# service - never Add-WindowsCapability) and trust a Controller remoting
# identity public key (authorized_keys).
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
      True when OpenSSH appears in Win32 ARP (Uninstall registry), same family of
      detect used for Software packages / hatch skip-if-present.
    .NOTES
      Win32-OpenSSH MSI (Hatchery ADR-0029 / #518) registers under Uninstall.
      Do not use Add-WindowsCapability here - FoD conflicts with an MSI install.
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

function Ensure-OpenSshServer {
    # Detect only - never Add-WindowsCapability (FoD). Nest hosts should already
    # have Win32-OpenSSH MSI (or equivalent); FoD install fights that layout.
    Write-HatchEvent "Checking OpenSSH Server (ARP / path / service)" -Component "NestSSH"

    $sshdExe = Join-Path $env:ProgramFiles "OpenSSH\sshd.exe"
    $arpPresent = Test-OpenSshArpPresent
    $pathPresent = Test-Path -LiteralPath $sshdExe
    $sshd = Get-Service -Name sshd -ErrorAction SilentlyContinue

    if ($arpPresent) {
        Write-HatchEvent "OpenSSH found in ARP (Uninstall)" -Component "NestSSH"
    }
    if ($pathPresent) {
        Write-HatchEvent "OpenSSH Server binary present at $sshdExe" -Component "NestSSH"
    }

    if (-not $arpPresent -and -not $pathPresent -and -not $sshd) {
        throw (
            "OpenSSH Server is not installed (no ARP entry, no $sshdExe, no sshd service). " +
            "Install Win32-OpenSSH Server (GitHub MSI / Hatchery first-boot path), then re-run. " +
            "This script does not call Add-WindowsCapability."
        )
    }

    if (-not $sshd -and $pathPresent) {
        $installSshd = Join-Path $env:ProgramFiles "OpenSSH\install-sshd.ps1"
        if (Test-Path -LiteralPath $installSshd) {
            Write-HatchEvent "sshd service missing; running install-sshd.ps1" -Component "NestSSH"
            & $installSshd
            $sshd = Get-Service -Name sshd -ErrorAction SilentlyContinue
        }
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

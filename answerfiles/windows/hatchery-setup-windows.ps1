# ============================================================
# hatchery-setup-windows.ps1
# Companion first-boot setup packed with Autounattend.xml.
# Launched by the single FirstLogonCommand in the Answer File.
#
# Unlike automation scripts under scripts/, this runs on the guest
# console during OOBE FirstLogon - before Hatchery can inject
# Write-HatchEvent or persist HATCHERY_* env (ADR-0026). Paths are
# the locked Windows guest defaults. The shim below matches the
# Controller line format so hatchery-setup-windows.log imports into
# hatch_events once Guest transport is up and hatchery-ready exists.
#
# Conventions (aligned with hatchery-cleanup-windows.ps1):
#   - Use Write-HatchEvent for progress lines
#   - $ErrorActionPreference = "Stop"
#   - Keep each step's Name + Action on the same object so commenting
#     out a step cannot desync labels from Invoke-Step indexes
# ============================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "Hatchery - First Boot Setup"
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Locked Windows guest paths (ADR-0025). HATCHERY_* env is not available yet
# at FirstLogon - Controller persist runs after hatchery-ready (#501 / ADR-0026).
$script:HatcheryRoot = "C:\Program Files\Hatchery"
$script:HatcheryLogs = Join-Path $script:HatcheryRoot "logs"
$script:HatcheryTemp = Join-Path $script:HatcheryRoot "temp"
$null = New-Item -Path $script:HatcheryLogs -ItemType Directory -Force
$null = New-Item -Path $script:HatcheryTemp -ItemType Directory -Force
# Same path Hatchery imports after check_setup_complete (provision.SETUP_LOG_FILE).
$script:HatchLogFile = Join-Path $script:HatcheryLogs "hatchery-setup-windows.log"
$script:UiTitle = "First Boot Setup"

try {
    $Host.UI.RawUI.BackgroundColor = "Black"
    $Host.UI.RawUI.ForegroundColor = "White"
} catch { }

# Compatible with Hatchery's injected Write-HatchEvent (stdout + timestamped log line).
# Do not rely on Controller injection here; FirstLogon has no remoting session yet.
function Write-HatchEvent {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO',
        [string]$Component = ''
    )
    $prefix = if ($Component) { "[HATCH:$Level][$Component]" } else { "[HATCH:$Level]" }
    Write-Output "$prefix $Message"
    $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss+00:00")
    $line = if ($Component) {
        "[HATCH:$Level][$Component][$ts] $Message"
    } else {
        "[HATCH:$Level][$ts] $Message"
    }
    try {
        Add-Content -Path $script:HatchLogFile -Value $line -Encoding UTF8
    } catch { }
}

function Show-HatcheryBanner {
    Write-Host @"
 _   _    _  _____  ____ _   _ _____ ______   __
| | | |  / \|_   _|/ ___| | | | ____|  _ \ \ / /
| |_| | / _ \ | | | |   | |_| |  _| | |_) \ V /
|  _  |/ ___ \| | | |___|  _  | |___|  _ < | |
|_| |_/_/   \_\_|  \____|_| |_|_____|_| \_\|_|
"@ -ForegroundColor White
    Write-Host "  Hatch. Provision. Scale." -ForegroundColor DarkGray
}

function Install-HatcheryOpenSshServerFromGitHub {
    <#
    .SYNOPSIS
      Install OpenSSH Server from the latest PowerShell/Win32-OpenSSH Win64 MSI.

    .NOTES
      Hatchery ADR-0029 / issue #518. Do not use Add-WindowsCapability (Windows Update
      FoD); that path is multi-minute in lab while this MSI is seconds-class.
      Upstream after early semver ships only Beta/Preview tags; we still take latest.
    #>
    $ProgressPreference = 'SilentlyContinue'

    $svc = Get-Service -Name sshd -ErrorAction SilentlyContinue
    $sshdExe = Join-Path ${env:ProgramFiles} 'OpenSSH\sshd.exe'
    if ($svc -and (Test-Path -LiteralPath $sshdExe)) {
        Write-HatchEvent "OpenSSH Server already present at $sshdExe; skipping MSI download" `
            -Component 'ssh'
        return
    }

    $api = 'https://api.github.com/repos/PowerShell/Win32-OpenSSH/releases/latest'
    Write-HatchEvent "Resolving latest OpenSSH Win64 MSI from GitHub releases" -Component 'ssh'
    $headers = @{
        'User-Agent' = 'Hatchery-first-boot'
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
    ) -Component 'ssh'
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $msi -UseBasicParsing `
        -Headers @{ 'User-Agent' = 'Hatchery-first-boot' }

    if (-not (Test-Path -LiteralPath $msi) -or ((Get-Item -LiteralPath $msi).Length -lt 1MB)) {
        throw "Downloaded MSI missing or too small: $msi"
    }

    $msiLog = Join-Path $env:TEMP 'hatchery-openssh-msi.log'
    Write-HatchEvent "Running msiexec ADDLOCAL=Server for $($asset.name)" -Component 'ssh'
    $p = Start-Process -FilePath 'msiexec.exe' `
        -ArgumentList "/i `"$msi`" ADDLOCAL=Server /qn /norestart /l*v `"$msiLog`"" `
        -Wait -PassThru
    if ($p.ExitCode -notin 0, 3010) {
        throw "msiexec OpenSSH Server failed exit $($p.ExitCode); see $msiLog"
    }
    Write-HatchEvent "msiexec finished exit=$($p.ExitCode) tag=$($release.tag_name)" `
        -Component 'ssh'

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
        Write-HatchEvent "Appended $sshDir to Machine PATH" -Component 'ssh'
    }

    try {
        Remove-Item -LiteralPath $msi -Force -ErrorAction SilentlyContinue
    } catch { }
}

# Each step is one object: label, UI status, event component, and action stay together.
# To skip a step locally, comment out or remove the whole object from this list.
$script:Steps = @(
    [pscustomobject]@{
        Name      = "Set network profile to Private"
        Component = "network"
        Status    = "[ ]"
        Action    = {
            Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private
        }
    }
    [pscustomobject]@{
        Name      = "Enable PSRemoting"
        Component = "winrm"
        Status    = "[ ]"
        Action    = {
            Enable-PSRemoting -Force
            # Headroom for Software payload staging over WinRM Send (Controller raises
            # this again at stage time if needed; set here so fresh guests are ready).
            $need = 8192
            $cur = [int](Get-Item -Path 'WSMan:\localhost\MaxEnvelopeSizekb').Value
            if ($cur -lt $need) {
                Set-Item -Path 'WSMan:\localhost\MaxEnvelopeSizekb' -Value $need
            }
        }
    }
    [pscustomobject]@{
        Name      = "Set LocalAccountTokenFilterPolicy"
        Component = "winrm"
        Status    = "[ ]"
        Action    = {
            New-ItemProperty `
                -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
                -Name 'LocalAccountTokenFilterPolicy' `
                -Value 1 `
                -PropertyType DWORD `
                -Force
        }
    }
    [pscustomobject]@{
        # Hatchery #543 / Library #8: lab/dev posture for silent Software installs.
        # LocalAccountTokenFilterPolicy (above) is WinRM token filter only - not the
        # UAC slider. Never notify = ConsentPromptBehaviorAdmin=0 + PromptOnSecureDesktop=0.
        # Takes effect for new remoting sessions after hatchery-ready; no reboot required.
        Name      = "Set UAC to Never notify"
        Component = "uac"
        Status    = "[ ]"
        Action    = {
            $sysPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
            $backupPath = Join-Path $script:HatcheryTemp 'hatchery-uac-policy.json'

            $consent = Get-ItemProperty -Path $sysPath -Name ConsentPromptBehaviorAdmin -ErrorAction SilentlyContinue
            $secureDesktop = Get-ItemProperty -Path $sysPath -Name PromptOnSecureDesktop -ErrorAction SilentlyContinue
            $backup = [ordered]@{
                ConsentPromptBehaviorAdmin = if ($null -ne $consent) {
                    [int]$consent.ConsentPromptBehaviorAdmin
                } else {
                    5
                }
                PromptOnSecureDesktop = if ($null -ne $secureDesktop) {
                    [int]$secureDesktop.PromptOnSecureDesktop
                } else {
                    1
                }
            }
            ($backup | ConvertTo-Json -Compress) | Set-Content -Path $backupPath -Encoding UTF8

            New-ItemProperty `
                -Path $sysPath `
                -Name 'ConsentPromptBehaviorAdmin' `
                -Value 0 `
                -PropertyType DWORD `
                -Force | Out-Null
            New-ItemProperty `
                -Path $sysPath `
                -Name 'PromptOnSecureDesktop' `
                -Value 0 `
                -PropertyType DWORD `
                -Force | Out-Null
        }
    }
    [pscustomobject]@{
        Name      = "Open WinRM firewall rule (port 5985)"
        Component = "winrm"
        Status    = "[ ]"
        Action    = {
            New-NetFirewallRule `
                -Name 'Hatchery-WinRM-HTTP' `
                -DisplayName 'Hatchery - WinRM HTTP' `
                -Description 'Inbound WinRM rule created by Hatchery via unattend.xml FirstLogonCommands during automated OS provisioning.' `
                -Direction Inbound `
                -Protocol TCP `
                -LocalPort 5985 `
                -Action Allow `
                -Enabled True
        }
    }
    [pscustomobject]@{
        # ADR-0029 / Hatchery #518: GitHub Win32-OpenSSH MSI (not Windows Update FoD).
        # Resolves latest Win64 Server MSI; FoD Add-WindowsCapability is intentionally unused.
        Name      = "Install OpenSSH Server"
        Component = "ssh"
        Status    = "[ ]"
        Action    = {
            Install-HatcheryOpenSshServerFromGitHub
        }
    }
    [pscustomobject]@{
        Name      = "Set sshd service to Automatic startup"
        Component = "ssh"
        Status    = "[ ]"
        Action    = {
            Set-Service -Name sshd -StartupType Automatic
        }
    }
    [pscustomobject]@{
        Name      = "Start sshd service"
        Component = "ssh"
        Status    = "[ ]"
        Action    = {
            Start-Service -Name sshd
        }
    }
    [pscustomobject]@{
        Name      = "Open SSH firewall rule (port 22)"
        Component = "ssh"
        Status    = "[ ]"
        Action    = {
            New-NetFirewallRule `
                -Name 'Hatchery-SSH-Server-sshd' `
                -DisplayName 'Hatchery - SSH Server (sshd)' `
                -Description 'Inbound SSH rule created by Hatchery via unattend.xml FirstLogonCommands during automated OS provisioning.' `
                -Direction Inbound `
                -Protocol TCP `
                -LocalPort 22 `
                -Action Allow `
                -Enabled True
        }
    }
    [pscustomobject]@{
        Name      = "Write hatchery-ready flag"
        Component = "ready"
        Status    = "[ ]"
        Action    = {
            New-Item -Path (Join-Path $script:HatcheryTemp 'hatchery-ready') -ItemType File -Force | Out-Null
        }
    }
)

function Show-Steps {
    param([string]$Footer = "")
    try { Clear-Host } catch { }
    Show-HatcheryBanner
    Write-Host ("-" * 50) -ForegroundColor DarkGray
    Write-Host "  $script:UiTitle" -ForegroundColor White
    Write-Host ("-" * 50) -ForegroundColor DarkGray
    Write-Host "  Log file: $script:HatchLogFile" -ForegroundColor DarkGray
    Write-Host ("-" * 50) -ForegroundColor DarkGray
    for ($i = 0; $i -lt $script:Steps.Count; $i++) {
        $step = $script:Steps[$i]
        $color = switch ($step.Status) {
            "[>]" { "Yellow" }
            "[+]" { "Green" }
            "[!]" { "Red" }
            default { "DarkGray" }
        }
        Write-Host ("  {0} {1}. {2}" -f $step.Status, ($i + 1), $step.Name) -ForegroundColor $color
    }
    Write-Host ("-" * 50) -ForegroundColor DarkGray
    if ($Footer) { Write-Host "  $Footer" -ForegroundColor White }
}

function Invoke-Step {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Step
    )
    $Step.Status = "[>]"
    Show-Steps
    Write-HatchEvent "Step started: $($Step.Name)" -Component $Step.Component
    try {
        & $Step.Action | Out-Null
        $Step.Status = "[+]"
        Write-HatchEvent "Step succeeded: $($Step.Name)" -Component $Step.Component
    } catch {
        $Step.Status = "[!]"
        Write-HatchEvent "Step failed: $($Step.Name) -- $_" -Level ERROR -Component $Step.Component
        Show-Steps ("Step failed: {0}" -f $_)
        Write-Host ""
        Write-Host "  Press any key to close..." -ForegroundColor DarkGray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
}

try {
    Write-HatchEvent "Hatchery first boot setup started" -Component "setup"

    foreach ($step in $script:Steps) {
        Invoke-Step -Step $step
    }

    Write-HatchEvent "Hatchery first boot setup completed successfully" -Component "setup"
    Show-Steps "Setup complete. Hatchery will begin automation shortly."
    Start-Sleep -Seconds 3
    exit 0
} catch {
    Write-HatchEvent "Setup failed: $_" -Level ERROR -Component "setup"
    Show-Steps ("Setup failed: {0}" -f $_)
    Write-Host ""
    Write-Host "  Press any key to close..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

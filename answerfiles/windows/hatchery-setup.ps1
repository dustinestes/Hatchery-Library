# ============================================================
# hatchery-setup.ps1
# Companion first-boot setup packed with Autounattend.xml.
# Launched by the single FirstLogonCommand in the Answer File.
#
# Unlike automation scripts under scripts/, this runs on the guest
# console during OOBE FirstLogon - before Hatchery can inject
# Write-HatchEvent over WinRM. The shim below matches the Controller
# line format so hatchery-setup.log imports into hatch_events once
# WinRM is up and the hatchery-ready flag exists.
#
# Conventions (aligned with hatchery-script-template-windows.ps1):
#   - Use Write-HatchEvent for progress lines
#   - $ErrorActionPreference = "Stop"
#   - Keep each step's Name + Action on the same object so commenting
#     out a step cannot desync labels from Invoke-Step indexes
# ============================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "Hatchery - First Boot Setup"
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$script:HatcheryDir = "C:\Program Files\Hatchery"
$null = New-Item -Path "$script:HatcheryDir\logs" -ItemType Directory -Force
$null = New-Item -Path "$script:HatcheryDir\temp" -ItemType Directory -Force
# Same path Hatchery imports after check_setup_complete (provision.SETUP_LOG_FILE).
$script:HatchLogFile = "$script:HatcheryDir\logs\hatchery-setup.log"

# Compatible with Hatchery's injected Write-HatchEvent (stdout + timestamped log line).
# Do not rely on Controller injection here; FirstLogon has no WinRM session yet.
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
        Name      = "Install OpenSSH Server"
        Component = "ssh"
        Status    = "[ ]"
        Action    = {
            Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
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
            New-Item -Path "$script:HatcheryDir\temp\hatchery-ready" -ItemType File -Force | Out-Null
        }
    }
)

function Show-Steps {
    param([string]$Footer = "")
    Clear-Host
    Write-Host ("-" * 50)
    Write-Host "Hatchery - First Boot Setup"
    Write-Host ("-" * 50)
    Write-Host "Log file: $script:HatchLogFile"
    Write-Host ("-" * 50)
    for ($i = 0; $i -lt $script:Steps.Count; $i++) {
        $step = $script:Steps[$i]
        $color = switch ($step.Status) {
            "[>]" { "Yellow" }
            "[+]" { "Green" }
            "[!]" { "Red" }
            default { "Gray" }
        }
        Write-Host ("  {0} {1}. {2}" -f $step.Status, ($i + 1), $step.Name) -ForegroundColor $color
    }
    Write-Host ("-" * 50)
    if ($Footer) { Write-Host $Footer }
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
        Write-Host "Press any key to close..." -ForegroundColor DarkGray
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
    Write-Host "Press any key to close..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# ============================================================
# hatchery-cleanup-windows.ps1
# Restores UAC policy lowered at first boot (#543 / Library #8),
# then removes the Hatchery guest directory and all its contents.
#
# Add this as the LAST script in your Clutch's automations list
# if you want to remove all Hatchery artifacts from the guest
# after provisioning completes. Once removed, the Hatchery event
# log becomes the sole audit record.
#
# If omitted, the Hatchery guest root remains as a local audit
# record containing:
#   logs\hatchery-setup-windows.log - first-boot setup steps
#   logs\<script-name>.log          - per-script automation events
#   temp\hatchery-uac-policy.json   - prior UAC values (when set)
# and UAC stays at Never notify (lab/dev posture from setup).
#
# Conventions (aligned with hatchery-setup-windows.ps1):
#   - Use Write-HatchEvent for progress lines (injected by Hatchery)
#   - $ErrorActionPreference = "Stop"
#   - Keep each step's Name + Action on the same object so commenting
#     out a step cannot desync labels from Invoke-Step indexes
#   - Prefer HATCHERY_* env (persisted before automations, ADR-0026)
#
#   automations:
#     - name: hatchery-cleanup-windows.ps1
# ============================================================

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Reserved env is persisted before automations (#501 / ADR-0026). Fall back to
# locked Windows guest defaults when unset (manual local run).
$script:HatcheryRoot = if ($env:HATCHERY_ROOT) { $env:HATCHERY_ROOT } else { "C:\Program Files\Hatchery" }
$script:HatcheryLogs = if ($env:HATCHERY_LOGS) { $env:HATCHERY_LOGS } else { Join-Path $script:HatcheryRoot "logs" }
$script:HatcheryTemp = if ($env:HATCHERY_TEMP) { $env:HATCHERY_TEMP } else { Join-Path $script:HatcheryRoot "temp" }
$script:UiTitle = "Cleanup"

# Windows default slider: "Notify me only when apps try to make changes".
$script:DefaultConsent = 5
$script:DefaultSecureDesktop = 1
$script:SysPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'

# Guest transport (SSH/WinRM) runs NonInteractive - Clear-Host / RawUI / prompts throw.
# Keep the console banner only for a real local ConsoleHost session.
$script:InteractiveUi = $false
try {
    $script:InteractiveUi = (
        [Environment]::UserInteractive -and
        $Host.Name -eq 'ConsoleHost' -and
        $Host.UI.RawUI -and
        -not [Environment]::GetEnvironmentVariable('HATCHERY_NONINTERACTIVE')
    )
} catch {
    $script:InteractiveUi = $false
}

if ($script:InteractiveUi) {
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $Host.UI.RawUI.WindowTitle = "Hatchery - Cleanup"
        $Host.UI.RawUI.BackgroundColor = "Black"
        $Host.UI.RawUI.ForegroundColor = "White"
    } catch { }
}

function Show-HatcheryBanner {
    if (-not $script:InteractiveUi) { return }
    Write-Host @"
 _   _    _  _____  ____ _   _ _____ ______   __
| | | |  / \|_   _|/ ___| | | | ____|  _ \ \ / /
| |_| | / _ \ | | | |   | |_| |  _| | |_) \ V /
|  _  |/ ___ \| | | |___|  _  | |___|  _ < | |
|_| |_/_/   \_\_|  \____|_| |_|_____|_| \_\|_|
"@ -ForegroundColor White
    Write-Host "  Hatch. Provision. Scale." -ForegroundColor DarkGray
}

# Each step is one object: label, UI status, event component, and action stay together.
# To skip a step locally, comment out or remove the whole object from this list.
$script:Steps = @(
    [pscustomobject]@{
        Name      = "Restore UAC policy"
        Component = "uac"
        Status    = "[ ]"
        Action    = {
            $backupPath = Join-Path $script:HatcheryTemp 'hatchery-uac-policy.json'
            $consent = $script:DefaultConsent
            $secureDesktop = $script:DefaultSecureDesktop
            if (Test-Path -LiteralPath $backupPath) {
                try {
                    $backup = Get-Content -LiteralPath $backupPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($null -ne $backup.ConsentPromptBehaviorAdmin) {
                        $consent = [int]$backup.ConsentPromptBehaviorAdmin
                    }
                    if ($null -ne $backup.PromptOnSecureDesktop) {
                        $secureDesktop = [int]$backup.PromptOnSecureDesktop
                    }
                    Write-HatchEvent (
                        "Restoring UAC from first-boot backup " +
                        "(ConsentPromptBehaviorAdmin=$consent, PromptOnSecureDesktop=$secureDesktop)"
                    ) -Component 'uac'
                } catch {
                    Write-HatchEvent "UAC backup unreadable; restoring Windows defaults -- $_" `
                        -Level WARN -Component 'uac'
                }
            } else {
                Write-HatchEvent (
                    "No UAC backup found; restoring Windows defaults " +
                    "(ConsentPromptBehaviorAdmin=$($script:DefaultConsent), " +
                    "PromptOnSecureDesktop=$($script:DefaultSecureDesktop))"
                ) -Component 'uac'
            }

            New-ItemProperty `
                -Path $script:SysPath `
                -Name 'ConsentPromptBehaviorAdmin' `
                -Value $consent `
                -PropertyType DWORD `
                -Force | Out-Null
            New-ItemProperty `
                -Path $script:SysPath `
                -Name 'PromptOnSecureDesktop' `
                -Value $secureDesktop `
                -PropertyType DWORD `
                -Force | Out-Null
        }
    }
    [pscustomobject]@{
        Name      = "Remove Hatchery guest directory"
        Component = "cleanup"
        Status    = "[ ]"
        Action    = {
            if (Test-Path -LiteralPath $script:HatcheryRoot) {
                Write-HatchEvent "Removing Hatchery guest directory: $($script:HatcheryRoot)" `
                    -Component 'cleanup'
                Remove-Item -Path $script:HatcheryRoot -Recurse -Force
            } else {
                Write-HatchEvent "Hatchery guest directory not found -- nothing to remove" `
                    -Level WARN -Component 'cleanup'
            }
        }
    }
    # Optional: clear persisted reserved Machine env vars (#501 / ADR-0026).
    # Directory wipe above is the default cleanup path. Uncomment to also clear env:
    #
    # [pscustomobject]@{
    #     Name      = "Clear Hatchery Machine environment variables"
    #     Component = "cleanup"
    #     Status    = "[ ]"
    #     Action    = {
    #         foreach ($name in @(
    #             'HATCHERY_ROOT',
    #             'HATCHERY_LOGS',
    #             'HATCHERY_TEMP',
    #             'HATCHERY_SOFTWARE'
    #         )) {
    #             [Environment]::SetEnvironmentVariable($name, $null, 'Machine')
    #             Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
    #         }
    #         Write-HatchEvent "Cleared persisted Hatchery Machine environment variables" `
    #             -Component 'cleanup'
    #     }
    # }
)

function Show-Steps {
    param([string]$Footer = "")
    # Never let console UI fail a remoting run (NonInteractive / no RawUI).
    try {
        if (-not $script:InteractiveUi) { return }
        Clear-Host
        Show-HatcheryBanner
        Write-Host ("-" * 50) -ForegroundColor DarkGray
        Write-Host "  $script:UiTitle" -ForegroundColor White
        Write-Host ("-" * 50) -ForegroundColor DarkGray
        Write-Host "  Guest root: $script:HatcheryRoot" -ForegroundColor DarkGray
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
    } catch { }
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
        # Do not Out-Null: cleanup runs over Guest transport; Action events must
        # reach stdout for hatch_events (the guest log is wiped in a later step).
        & $Step.Action
        $Step.Status = "[+]"
        Write-HatchEvent "Step succeeded: $($Step.Name)" -Component $Step.Component
        Show-Steps
    } catch {
        $Step.Status = "[!]"
        Write-HatchEvent "Step failed: $($Step.Name) -- $_" -Level ERROR -Component $Step.Component
        Show-Steps ("Step failed: {0}" -f $_)
        exit 1
    }
}

try {
    Write-HatchEvent "Hatchery cleanup started" -Component "cleanup"

    foreach ($step in $script:Steps) {
        Invoke-Step -Step $step
    }

    Write-HatchEvent "Hatchery cleanup completed successfully" -Component "cleanup"
    Show-Steps "Cleanup complete."
    exit 0
} catch {
    Write-HatchEvent "Cleanup failed: $_" -Level ERROR -Component "cleanup"
    Show-Steps ("Cleanup failed: {0}" -f $_)
    exit 1
}

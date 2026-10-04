# ============================================================
# enable-hyperv-windows.ps1
# Nest-plane: enable the Hyper-V role (and management tools) so
# this Windows host can act as a Hatchery Nest.
#
# Run elevated on the Nest host (manual, MDM, or hatch automation).
# A reboot is often required; the script exits 0 after enabling and
# reports whether a restart is pending.
#
# Example:
#   .\enable-hyperv-windows.ps1
#
# Clutch (optional):
#   automations:
#     - name: enable-hyperv-windows.ps1
#       reboot_after: true
# ============================================================

param(
    [Parameter(Mandatory = $false, HelpMessage = "Also enable Hyper-V management tools when the Server feature path is used.")]
    [bool]$IncludeManagementTools = $true
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

try {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).
        IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw "enable-hyperv-windows.ps1 must run elevated (Administrator)."
    }

    Write-HatchEvent "Enabling Hyper-V Nest role" -Component "HyperV"

    $restartNeeded = $false

    if (Get-Command Install-WindowsFeature -ErrorAction SilentlyContinue) {
        # Server SKUs
        Write-HatchEvent "Installing Windows feature: Hyper-V" -Component "HyperV"
        if ($IncludeManagementTools) {
            $result = Install-WindowsFeature -Name Hyper-V -IncludeManagementTools
        } else {
            $result = Install-WindowsFeature -Name Hyper-V
        }
        if (-not $result.Success) {
            throw "Install-WindowsFeature Hyper-V failed (ExitCode=$($result.ExitCode))."
        }
        if ($result.RestartNeeded -eq "Yes" -or $result.RestartNeeded -eq $true) {
            $restartNeeded = $true
        }
    } elseif (Get-Command Get-WindowsOptionalFeature -ErrorAction SilentlyContinue) {
        # Client SKUs (Pro / Enterprise / Education)
        $featName = "Microsoft-Hyper-V-All"
        $feat = Get-WindowsOptionalFeature -Online -FeatureName $featName -ErrorAction SilentlyContinue
        if (-not $feat) {
            $featName = "Microsoft-Hyper-V"
            $feat = Get-WindowsOptionalFeature -Online -FeatureName $featName -ErrorAction SilentlyContinue
        }
        if (-not $feat) {
            throw "Hyper-V optional features are not available on this Windows SKU."
        }
        if ($feat.State -eq "Enabled") {
            Write-HatchEvent "Already enabled: $featName" -Component "HyperV"
        } else {
            Write-HatchEvent "Enabling optional feature: $featName" -Component "HyperV"
            $result = Enable-WindowsOptionalFeature -Online -FeatureName $featName -All -NoRestart
            if ($result.RestartNeeded) { $restartNeeded = $true }
        }
    } else {
        throw "Neither Install-WindowsFeature nor Get-WindowsOptionalFeature is available on this host."
    }

    if ($restartNeeded) {
        Write-HatchEvent "Hyper-V enabled - restart the Nest host before using it as a Hatchery Nest" `
            -Level WARN -Component "HyperV"
    } else {
        Write-HatchEvent "Hyper-V enable complete" -Component "HyperV"
    }
    exit 0
} catch {
    Write-HatchEvent "Script failed: $_" -Level ERROR -Component "HyperV"
    exit 1
}

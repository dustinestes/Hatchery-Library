# ============================================================
# hatchery-param-smoke-windows.ps1
# Lab fixture for Hatchery typed Clutch script parameters.
#
# Exercises every kind / constraint Hatchery discovers today
# (app repo #571 / ADR-0034):
#   string (mandatory, ValidateSet, ValidateLength),
#   bool, switch, int, float.
#
# When run on the guest it echoes bound values three ways:
#   1. Write-HatchEvent  → Hatchery Events / script feed
#   2. Write-Output      → captured script stdout in Hatchery
#   3. Local dump file   → under HATCHERY_LOGS (or TEMP) on guest
#
# Pull into automation/scripts/, then in Clutch Build/Edit pick this
# script and confirm widgets + early validation. Sample parameters:
#
#   automations:
#     - type: script
#       name: hatchery-param-smoke-windows.ps1
#       parameters:
#         SampleName: lab-dc01
#         Environment: lab
#         IncludeManagementTools: true
#         Force: false
#         RetryCount: 2
#         ScaleFactor: 1.5
#         Note: smoke-ok
# ============================================================

param(
    [Parameter(Mandatory = $true, HelpMessage = "Required short name (1-15 chars). Maps to string + ValidateLength.")]
    [ValidateLength(1, 15)]
    [string]$SampleName,

    [Parameter(Mandatory = $true, HelpMessage = "Constrained choice. Maps to ValidateSet → select in Clutch UI.")]
    [ValidateSet("dev", "lab", "prod")]
    [string]$Environment,

    [Parameter(Mandatory = $false, HelpMessage = "Typed [bool] (not switch). Checkbox; invoke as `$true/`$false.")]
    [bool]$IncludeManagementTools = $true,

    [Parameter(Mandatory = $false, HelpMessage = "PowerShell [switch]. Checkbox; present vs -Force:`$false.")]
    [switch]$Force,

    [Parameter(Mandatory = $false, HelpMessage = "Unsigned integer count (uint). Number field; min 0; invoke unquoted.")]
    [uint]$RetryCount = 1,

    [Parameter(Mandatory = $false, HelpMessage = "Floating-point scale (signed). Number field; negatives allowed; invoke unquoted.")]
    [double]$ScaleFactor = 1.0,

    [Parameter(Mandatory = $false, HelpMessage = "Optional free-text note with a default.")]
    [string]$Note = "none"
)

$ErrorActionPreference = "Stop"
$Component = "param-smoke"

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

function Get-ParamSmokeDumpPath {
    if ($env:HATCHERY_LOGS) {
        return (Join-Path $env:HATCHERY_LOGS "hatchery-param-smoke-windows.dump.txt")
    }
    if ($env:TEMP) {
        return (Join-Path $env:TEMP "hatchery-param-smoke-windows.dump.txt")
    }
    return (Join-Path (Get-Location) "hatchery-param-smoke-windows.dump.txt")
}

try {
    Write-HatchEvent "Param smoke started" -Component $Component

    # Bound values as Hatchery / PowerShell see them after param binding.
    $rows = [ordered]@{
        SampleName              = $SampleName
        Environment             = $Environment
        IncludeManagementTools  = $IncludeManagementTools
        Force                   = [bool]$Force
        RetryCount              = $RetryCount
        ScaleFactor             = $ScaleFactor
        Note                    = $Note
    }

    $dumpPath = Get-ParamSmokeDumpPath
    $dumpDir = Split-Path -Parent $dumpPath
    if ($dumpDir -and -not (Test-Path -LiteralPath $dumpDir)) {
        $null = New-Item -Path $dumpDir -ItemType Directory -Force
    }

    $lines = @(
        "hatchery-param-smoke-windows.ps1"
        "utc=$([DateTime]::UtcNow.ToString('o'))"
        "computer=$env:COMPUTERNAME"
        "HATCHERY_SCRIPT_LOG=$env:HATCHERY_SCRIPT_LOG"
        "HATCHERY_LOGS=$env:HATCHERY_LOGS"
        "dump_path=$dumpPath"
        "----- parameters -----"
    )
    foreach ($key in $rows.Keys) {
        $val = $rows[$key]
        $typeName = if ($null -eq $val) { "null" } else { $val.GetType().FullName }
        $display = if ($null -eq $val) { "<null>" } else { "$val" }
        $lines += ("{0}={1} (type={2})" -f $key, $display, $typeName)
    }

    $body = ($lines -join [Environment]::NewLine) + [Environment]::NewLine
    Set-Content -Path $dumpPath -Value $body -Encoding UTF8

    # Stdout: full dump (captured into Hatchery script output).
    Write-Output $body.TrimEnd()

    # Events feed: one line per param + dump path.
    Write-HatchEvent "Dump written: $dumpPath" -Component $Component
    foreach ($key in $rows.Keys) {
        $val = $rows[$key]
        $typeName = if ($null -eq $val) { "null" } else { $val.GetType().FullName }
        $display = if ($null -eq $val) { "<null>" } else { "$val" }
        Write-HatchEvent ("{0}={1} ({2})" -f $key, $display, $typeName) -Component $Component
    }

    Write-HatchEvent "Param smoke completed successfully" -Component $Component
    exit 0

} catch {
    Write-HatchEvent "Param smoke failed: $_" -Level ERROR -Component $Component
    exit 1
}

# ============================================================
# hatchery-cleanup-windows.ps1
# Removes the Hatchery guest directory and all its contents.
#
# Add this as the LAST script in your Clutch's automations list
# if you want to remove all Hatchery artifacts from the guest
# after provisioning completes. Once removed, the Hatchery event
# log becomes the sole audit record.
#
# If omitted, C:\Program Files\Hatchery\ remains on the guest
# as a local audit record containing:
#   logs\hatchery-setup.log    - first-boot setup steps
#   logs\<script-name>.log     - per-script automation events
#
#   automations:
#     - name: hatchery-cleanup-windows.ps1
# ============================================================

$ErrorActionPreference = "Stop"
$HatcheryDir = "C:\Program Files\Hatchery"

try {
    if (Test-Path $HatcheryDir) {
        Write-HatchEvent "Removing Hatchery guest directory: $HatcheryDir"
        Remove-Item -Path $HatcheryDir -Recurse -Force
        Write-HatchEvent "Hatchery guest directory removed"
    } else {
        Write-HatchEvent "Hatchery guest directory not found -- nothing to remove" -Level WARN
    }

    # Optional: remove persisted reserved Machine env vars written at hatch (#501 / ADR-0026).
    # Directory wipe above is the default cleanup path. Uncomment to also clear env:
    #
    # foreach ($name in @(
    #     'HATCHERY_ROOT',
    #     'HATCHERY_LOGS',
    #     'HATCHERY_TEMP',
    #     'HATCHERY_SOFTWARE'
    # )) {
    #     [Environment]::SetEnvironmentVariable($name, $null, 'Machine')
    #     Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
    # }
    # Write-HatchEvent "Cleared persisted Hatchery Machine environment variables"

    exit 0
} catch {
    Write-HatchEvent "Cleanup failed: $_" -Level ERROR
    exit 1
}

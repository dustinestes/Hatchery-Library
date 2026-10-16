# ============================================================
# test-retry-windows.ps1
# End-to-end test for Hatchery's retry mechanism.
#
# Lives under tests/scripts/ (not scripts/) so default Library
# Script bindings do not pull it. Basename prefix test-.
#
# First run:  writes a flag under $env:TEMP, then exits 1 so
#             Hatchery marks the VM failed.
# Retry run:  finds the flag, deletes it, exits 0 so Hatchery
#             marks the script succeeded and continues automation.
#
# Flag path:  $env:TEMP\test-retry-ran
#
# Usage in a Clutch (after enabling Test Scripts binding + pull):
#   automations:
#     - type: script
#       name: test-retry-windows.ps1
#     - <next script>   # only reached on the retry run
# ============================================================

$ErrorActionPreference = "Stop"
$FlagFile = Join-Path $env:TEMP "test-retry-ran"
$Component = "test-retry"

try {
    if (Test-Path $FlagFile) {
        Write-HatchEvent "Retry flag found -- this is the retry run" -Component $Component
        Remove-Item -Path $FlagFile -Force
        Write-HatchEvent "Flag removed -- retry succeeded" -Component $Component
        exit 0
    }

    Write-HatchEvent "First run -- writing retry flag and failing intentionally" -Component $Component
    $null = New-Item -Path $FlagFile -ItemType File -Force
    Write-HatchEvent "Flag written to: $FlagFile" -Component $Component
    Write-HatchEvent "Exiting with code 1 -- use Hatchery retry to continue" -Level WARN -Component $Component
    exit 1

} catch {
    Write-HatchEvent "Unexpected error: $_" -Level ERROR -Component $Component
    exit 1
}

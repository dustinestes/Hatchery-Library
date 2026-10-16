# ============================================================
# remove-appx-windows.ps1
# Remove provisioned / installed AppX packages from a Windows guest.
#
# Copy to automation/scripts/ and declare in a Clutch:
#
#   automations:
#     - name: remove-appx-windows.ps1
#       parameters:
#         PackageNames: "Microsoft.BingNews,Microsoft.XboxApp"
#         RemoveAll: "false"
#         KeepPackageNames: "Microsoft.WindowsNotepad"
#         KeepDefaults: "true"
#
# PackageNames is a comma-separated list of AppX Name values
# (Get-AppxPackage | Select Name). Matching is by -like '*Name*'.
#
# When RemoveAll is true, every removable non-framework AppX package
# for all users is removed and PackageNames is ignored. Packages with
# NonRemovable or SignatureKind System are skipped (inbox apps such as
# File Picker whose Name is a GUID, not a Microsoft.* string).
#
# KeepPackageNames / KeepDefaults skip lab-useful packages during both
# RemoveAll and PackageNames removal (substring match on Name).
#
# Use with care: RemoveAll can strip Store and inbox apps operators
# still expect. Prefer an explicit PackageNames list for lab images.
# ============================================================

param(
    [Parameter(Mandatory = $false, HelpMessage = "Comma-separated AppX package Name values to remove (substring match). Ignored when RemoveAll is true.")]
    [string]$PackageNames = "",

    [Parameter(Mandatory = $false, HelpMessage = "When true, remove all removable non-framework AppX packages for all users and ignore PackageNames.")]
    [bool]$RemoveAll = $false,

    [Parameter(Mandatory = $false, HelpMessage = "Comma-separated AppX Name substrings to never remove (merged with defaults when KeepDefaults is true).")]
    [string]$KeepPackageNames = "",

    [Parameter(Mandatory = $false, HelpMessage = "When true, merge the built-in lab keep list with KeepPackageNames.")]
    [bool]$KeepDefaults = $true
)

$ErrorActionPreference = "Stop"

# Lab keepers derived from a Win11 25H2 eval RemoveAll run (Hatchery-Library #19).
# Bloat (Bing*, Xbox*, Solitaire, Clipchamp, Teams, etc.) intentionally omitted.
$script:DefaultKeepPackageNames = @(
    "Microsoft.WindowsNotepad"
    "Microsoft.WindowsCalculator"
    "Microsoft.WindowsTerminal"
    "Microsoft.WindowsStore"
    "Microsoft.StorePurchaseApp"
    "Microsoft.Paint"
    "Microsoft.Windows.Photos"
    "Microsoft.ScreenSketch"
    "Microsoft.MicrosoftStickyNotes"
    "Microsoft.WindowsCamera"
    "Microsoft.MicrosoftEdge.Stable"
    "Microsoft.ApplicationCompatibilityEnhancements"
    "Microsoft.AV1VideoExtension"
    "Microsoft.AVCEncoderVideoExtension"
    "Microsoft.HEIFImageExtension"
    "Microsoft.HEVCVideoExtension"
    "Microsoft.MPEG2VideoExtension"
    "Microsoft.VP9VideoExtensions"
    "Microsoft.WebMediaExtensions"
    "Microsoft.WebpImageExtension"
    "Microsoft.RawImageExtension"
)

function Get-AppxKeepPatterns {
    $patterns = [System.Collections.Generic.List[string]]::new()
    if ($KeepDefaults) {
        foreach ($name in $script:DefaultKeepPackageNames) {
            if ($name) { [void]$patterns.Add($name) }
        }
    }
    foreach ($name in @($KeepPackageNames -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        [void]$patterns.Add($name)
    }
    return @($patterns | Select-Object -Unique)
}

function Test-AppxKeep {
    param(
        [Parameter(Mandatory = $true)] $Package,
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [string[]]$KeepPatterns
    )

    if ($KeepPatterns.Count -eq 0) {
        return $false
    }
    $pkgName = [string]$Package.Name
    foreach ($pattern in $KeepPatterns) {
        if ($pkgName -like "*$pattern*") {
            return $true
        }
    }
    return $false
}

function Test-AppxRemovable {
    param([Parameter(Mandatory = $true)] $Package)

    if ($Package.NonRemovable) {
        return $false
    }
    $sig = $Package.PSObject.Properties["SignatureKind"]
    if ($null -ne $sig -and [string]$Package.SignatureKind -eq "System") {
        return $false
    }
    return $true
}

function Remove-AppxByPackage {
    param(
        [Parameter(Mandatory = $true)] $Package,
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [string[]]$KeepPatterns
    )

    $full = $Package.PackageFullName
    if (Test-AppxKeep -Package $Package -KeepPatterns $KeepPatterns) {
        Write-HatchEvent "Keeping AppX '$full' (KeepPackageNames / defaults)" `
            -Level WARN -Component "AppX"
        return $false
    }
    if (-not (Test-AppxRemovable -Package $Package)) {
        Write-HatchEvent "Skipping non-removable AppX '$full' (NonRemovable or SignatureKind System)" `
            -Level WARN -Component "AppX"
        return $false
    }

    Write-HatchEvent "Removing AppX '$full'" -Component "AppX"
    try {
        try {
            Remove-AppxPackage -Package $full -AllUsers -ErrorAction Stop
        } catch {
            # Fall back to current-user removal when -AllUsers is unavailable
            Remove-AppxPackage -Package $full -ErrorAction Stop
        }
        return $true
    } catch {
        $err = "$_"
        # 0x80073CFA: package is present in the catalog but Windows refuses removal
        # (system / NonRemovable packages the property filter may still miss).
        if ($err -match '0x80073CFA') {
            Write-HatchEvent "Skipped AppX '$full' (removal refused): $err" `
                -Level WARN -Component "AppX"
            return $false
        }
        throw
    }
}

try {
    $keepPatterns = @(Get-AppxKeepPatterns)
    if ($keepPatterns.Count -gt 0) {
        Write-HatchEvent ("Keep list ($($keepPatterns.Count)): " + ($keepPatterns -join ", ")) `
            -Component "AppX"
    }

    if ($RemoveAll) {
        Write-HatchEvent "RemoveAll=true - removing removable non-framework AppX packages" `
            -Component "AppX"
        $packages = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
            Where-Object { -not $_.IsFramework }
        if (-not $packages) {
            $packages = Get-AppxPackage -ErrorAction SilentlyContinue |
                Where-Object { -not $_.IsFramework }
        }
        $count = 0
        foreach ($pkg in @($packages)) {
            if (Remove-AppxByPackage -Package $pkg -KeepPatterns $keepPatterns) {
                $count++
            }
        }
        Write-HatchEvent "Removed $count AppX package(s)" -Component "AppX"
        exit 0
    }

    $names = @($PackageNames -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($names.Count -eq 0) {
        Write-HatchEvent "No PackageNames provided and RemoveAll is false - nothing to do" `
            -Level WARN -Component "AppX"
        exit 0
    }

    $all = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
    if ($all.Count -eq 0) {
        $all = @(Get-AppxPackage -ErrorAction SilentlyContinue)
    }

    $removed = 0
    foreach ($name in $names) {
        $matches = @($all | Where-Object { $_.Name -like "*$name*" })
        if ($matches.Count -eq 0) {
            Write-HatchEvent "No AppX package matched '$name'" -Level WARN -Component "AppX"
            continue
        }
        foreach ($pkg in $matches) {
            if (Remove-AppxByPackage -Package $pkg -KeepPatterns $keepPatterns) {
                $removed++
            }
        }
    }

    Write-HatchEvent "Removed $removed AppX package(s)" -Component "AppX"
    exit 0

} catch {
    Write-HatchEvent "Script failed: $_" -Level ERROR
    exit 1
}

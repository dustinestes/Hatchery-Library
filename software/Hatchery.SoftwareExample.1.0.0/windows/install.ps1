# Select the MSI matching the guest architecture and run a quiet install.
# Staged under software_package(id); cwd is that folder (not .\windows\).
$ErrorActionPreference = 'Stop'

$arch = $env:PROCESSOR_ARCHITECTURE
if ($env:PROCESSOR_ARCHITEW6432) {
    $arch = $env:PROCESSOR_ARCHITEW6432
}

$msi = switch ($arch) {
    'AMD64' { '.\Hatchery.SoftwareExample.1.0.0-x64.msi' }
    'ARM64' { '.\Hatchery.SoftwareExample.1.0.0-arm64.msi' }
    default { '.\Hatchery.SoftwareExample.1.0.0-x86.msi' }
}

if (-not (Test-Path -LiteralPath $msi)) {
    Write-Error "MSI not found for architecture ${arch}: $msi"
    exit 1
}

$proc = Start-Process -FilePath 'msiexec.exe' `
    -ArgumentList @('/i', (Resolve-Path -LiteralPath $msi).Path, '/qn', '/norestart') `
    -Wait -PassThru
exit $proc.ExitCode

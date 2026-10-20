$ErrorActionPreference = 'Stop'

foreach ($toolName in @('flutter', 'dart', 'node')) {
    if ($null -eq (Get-Command $toolName -ErrorAction SilentlyContinue)) {
        throw "$toolName is not on PATH. Run scripts/doctor.ps1 for setup guidance."
    }
}

Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }

    $formatTargets = @('lib')
    if (Test-Path -LiteralPath 'test') { $formatTargets += 'test' }
    & dart format --output=none --set-exit-if-changed @formatTargets
    if ($LASTEXITCODE -ne 0) { throw 'Formatting failed. Run: dart format lib' }

    & flutter analyze --fatal-infos
    if ($LASTEXITCODE -ne 0) { throw 'Static analysis failed.' }

    if (Test-Path -LiteralPath 'test') {
        & flutter test
        if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
    }

    & node --test backend/tests/illustration_gateway_test.mjs backend/tests/parent_providers_test.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Gateway contract tests failed.' }

    & flutter build web
    if ($LASTEXITCODE -ne 0) { throw 'Web build failed.' }
} finally {
    Pop-Location
}

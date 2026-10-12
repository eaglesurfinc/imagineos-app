$ErrorActionPreference = 'Stop'

$missingRequiredTool = $false
foreach ($toolName in @('git', 'flutter', 'dart')) {
    $toolCommand = Get-Command $toolName -ErrorAction SilentlyContinue
    if ($null -eq $toolCommand) {
        Write-Output "MISSING: $toolName"
        $missingRequiredTool = $true
    } else {
        Write-Output "FOUND: $toolName ($($toolCommand.Source))"
    }
}

foreach ($toolName in @('supabase', 'docker')) {
    $toolCommand = Get-Command $toolName -ErrorAction SilentlyContinue
    if ($null -eq $toolCommand) {
        Write-Output "LATER, FOR LOCAL BACKEND: $toolName is not on PATH"
    } else {
        Write-Output "FOUND: $toolName ($($toolCommand.Source))"
    }
}

if ($missingRequiredTool) {
    Write-Output 'Install Flutter (includes Dart), reopen the terminal, then rerun this script.'
    Write-Output 'Official guide: https://docs.flutter.dev/install/quick'
    exit 1
}

& flutter doctor
exit $LASTEXITCODE

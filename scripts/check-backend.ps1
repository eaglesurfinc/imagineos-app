param(
    [string]$ConfigPath = 'config/supabase.local.json'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not [IO.Path]::IsPathRooted($ConfigPath)) {
    $ConfigPath = Join-Path $projectRoot $ConfigPath
}
if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw 'Development configuration is missing. Follow backend/README.md.'
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$uri = $null
if (-not [Uri]::TryCreate($config.SUPABASE_URL, [UriKind]::Absolute, [ref]$uri) -or
    $uri.Scheme -ne 'https' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or
    $config.SUPABASE_PUBLISHABLE_KEY -notmatch '^sb_publishable_[A-Za-z0-9_-]+$') {
    throw 'Use an HTTPS project URL and a modern publishable key; never a server secret.'
}

$baseUrl = $config.SUPABASE_URL.TrimEnd('/')
$headers = @{ apikey = $config.SUPABASE_PUBLISHABLE_KEY }
try {
    $auth = Invoke-RestMethod -Uri "$baseUrl/auth/v1/settings" -Headers $headers
} catch {
    throw 'Auth settings request failed. Verify the project and publishable key.'
}
Write-Output "Auth endpoint reachable. Email provider enabled: $($auth.external.email). Signup disabled: $($auth.disable_signup)."

# Schema discovery is intentionally unavailable to browser publishable keys.
try {
    $null = Invoke-WebRequest -Uri "$baseUrl/rest/v1/" -Headers $headers -UseBasicParsing
    throw 'Schema discovery unexpectedly accepted a publishable key.'
} catch {
    if (-not $_.Exception.Response -or [int]$_.Exception.Response.StatusCode -ne 401) {
        throw 'Data API discovery check failed with an unexpected response.'
    }
    $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json
    if ($errorBody.message -ne 'Secret API key required') {
        throw 'Data API rejected the request for an unexpected reason.'
    }
}
Write-Output 'Data API reachable; schema discovery correctly requires a server secret (HTTP 401).'
Write-Output 'No table query, sign-in, or family-isolation claim follows from these endpoint checks.'

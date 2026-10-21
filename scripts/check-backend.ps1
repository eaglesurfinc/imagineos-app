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

$origin = 'http://127.0.0.1:8766'
foreach ($functionName in @('parent-controls', 'parent-providers', 'child-access', 'illustration-gateway')) {
    $endpoint = "$baseUrl/functions/v1/$functionName"
    try {
        $preflight = Invoke-WebRequest -Uri $endpoint -Method Options -UseBasicParsing -Headers @{
            apikey = $config.SUPABASE_PUBLISHABLE_KEY
            Origin = $origin
            'Access-Control-Request-Method' = 'POST'
        }
        if ($preflight.StatusCode -ne 204 -or $preflight.Headers['Access-Control-Allow-Origin'] -ne $origin) {
            throw 'Invalid preflight.'
        }
    } catch {
        throw "$functionName preflight failed. Check the deployed function and allowed origin."
    }
    $requestBody = if ($functionName -eq 'child-access') { '{"action":"status"}' } else { '{"action":"overview"}' }
    try {
        $null = Invoke-WebRequest -Uri $endpoint -Method Post -UseBasicParsing -Headers @{
            apikey = $config.SUPABASE_PUBLISHABLE_KEY
            Origin = $origin
        } -ContentType 'application/json' -Body $requestBody
        throw 'Unauthenticated operation unexpectedly succeeded.'
    } catch {
        if (-not $_.Exception.Response -or [int]$_.Exception.Response.StatusCode -ne 401) {
            throw "$functionName did not reject the unauthenticated request as expected."
        }
        if ($functionName -eq 'child-access') {
            $errorText = $_.ErrorDetails.Message
            if ([string]::IsNullOrWhiteSpace($errorText)) {
                $response = $_.Exception.Response
                if ($response.PSObject.Methods['GetResponseStream']) {
                    $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
                    try { $errorText = $reader.ReadToEnd() } finally { $reader.Dispose() }
                } elseif ($null -ne $response.Content) {
                    $errorText = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                }
            }
            $denial = $errorText | ConvertFrom-Json
            if ($denial.code -ne 'CHILD_APPROVAL_REQUIRED') {
                throw 'Child access did not enforce its own approval capability.'
            }
        }
    }
    Write-Output "${functionName}: allowed-origin preflight and unauthenticated denial passed."
}
Write-Output 'No sign-in, paid provider call or family-isolation claim follows from these endpoint checks.'

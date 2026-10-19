#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $WebProjectPath,

    [string] $TerraformPath = 'terraform',

    # Build and stage files locally; no Terraform, Azure CLI or upload calls.
    [switch] $BuildOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Checked {
    param([string] $Command, [string[]] $Arguments, [string] $Operation)
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Operation failed (exit $LASTEXITCODE)."
    }
}

$root = Split-Path -Parent $PSScriptRoot
$webProject = (Resolve-Path -LiteralPath $WebProjectPath).Path
foreach ($file in @('angular.json', 'package.json', 'package-lock.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $webProject $file) -PathType Leaf)) {
        throw "The Angular project is missing $file. Pass the ecommerce-store-web source directory."
    }
}

$deployment = $null
if (-not $BuildOnly) {
    $raw = Invoke-Checked -Command $TerraformPath `
        -Arguments @("-chdir=$root", 'output', '-json', 'web_deployment') `
        -Operation 'Terraform deployment output lookup'
    $deployment = ($raw -join "`n") | ConvertFrom-Json -AsHashtable
    if (
        [string]$deployment.subscription_id -notmatch '^[0-9a-fA-F-]{36}$' -or
        [string]$deployment.name -notmatch '^swa-ecommercestore-web-(dev|test|prod)$' -or
        [string]$deployment.resource_group_name -notmatch '^rg-ecommercestore-web-(dev|test|prod)$' -or
        [string]$deployment.hostname -notmatch '^[a-z0-9.-]+\.azurestaticapps\.net$'
    ) {
        throw 'Terraform output does not describe this web hosting stack. Check its directory and backend.'
    }
}

$buildPath = Join-Path $root '.artifacts/angular-build'
$browserPath = Join-Path $buildPath 'browser'
$sitePath = Join-Path $root '.artifacts/site'
$configPath = Join-Path $root 'web/staticwebapp.config.json'

Push-Location -LiteralPath $webProject
try {
    Invoke-Checked -Command 'npm' -Arguments @('ci') -Operation 'Installing locked Angular dependencies'
    Invoke-Checked -Command 'npm' `
        -Arguments @('run', 'build', '--', '--configuration', 'production', '--output-path', $buildPath) `
        -Operation 'Building Angular production files'
} finally {
    Pop-Location
}

if (-not (Test-Path -LiteralPath (Join-Path $browserPath 'index.html') -PathType Leaf)) {
    throw 'Angular did not create browser/index.html. No files were uploaded.'
}
if (Test-Path -LiteralPath $sitePath) {
    Remove-Item -LiteralPath $sitePath -Recurse -Force
}
$null = New-Item -Path $sitePath -ItemType Directory -Force
Get-ChildItem -LiteralPath $browserPath -Force | Copy-Item -Destination $sitePath -Recurse -Force
Copy-Item -LiteralPath $configPath -Destination (Join-Path $sitePath 'staticwebapp.config.json') -Force

if ($BuildOnly) {
    [pscustomobject]@{ artifact_path = $sitePath; uploaded = $false }
    return
}

# Capture the secret in memory. It is never placed in command-line arguments,
# written into files, or included in Terraform outputs or this script's result.
$token = Invoke-Checked -Command 'az' -Arguments @(
    'staticwebapp', 'secrets', 'list',
    '--subscription', $deployment.subscription_id,
    '--resource-group', $deployment.resource_group_name,
    '--name', $deployment.name,
    '--query', 'properties.apiKey', '--output', 'tsv', '--only-show-errors'
) -Operation 'Static Web Apps deployment token lookup'
$token = ($token -join '').Trim()
if ([string]::IsNullOrWhiteSpace($token)) {
    throw 'Azure returned an empty deployment token. No files were uploaded.'
}

$previousToken = $env:SWA_CLI_DEPLOYMENT_TOKEN
try {
    $env:SWA_CLI_DEPLOYMENT_TOKEN = $token
    # Explicit production target: the SWA CLI otherwise defaults to preview.
    Invoke-Checked -Command 'npx' -Arguments @(
        '--yes', '--package=@azure/static-web-apps-cli@2.0.10',
        'swa', 'deploy', $sitePath,
        '--env', 'production', '--no-use-keychain',
        '--subscription-id', $deployment.subscription_id,
        '--resource-group', $deployment.resource_group_name,
        '--app-name', $deployment.name
    ) -Operation 'Uploading Angular to production'
} finally {
    $env:SWA_CLI_DEPLOYMENT_TOKEN = $previousToken
    $token = $null
}

Write-Warning 'This upload verifies static hosting. Verify the /api BFF integration separately; the uploader does not rewrite Angular or BFF routes.'
[pscustomobject]@{
    artifact_path = $sitePath
    uploaded      = $true
    base_url      = $deployment.base_url
}

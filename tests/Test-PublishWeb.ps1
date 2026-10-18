#Requires -Version 7.2
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceRoot = Split-Path -Parent $PSScriptRoot
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "web-publish-tests-$([guid]::NewGuid().ToString('N'))"
$originalToken = $env:SWA_CLI_DEPLOYMENT_TOKEN
$script:checks = 0

function Assert-That([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
    $script:checks++
}

# Functions shadow native tools in this test process only. No network calls,
# Terraform provider executions, npm installs or Azure credentials are used.
function global:TestWebTerraform {
    $s = $global:WebPublishTestState
    $s.terraform_calls++
    $s.terraform_args = @($args)
    $global:LASTEXITCODE = if ($s.fail -eq 'terraform') { 1 } else { 0 }
    if ($global:LASTEXITCODE -eq 0) {
        $s.deployment | ConvertTo-Json -Compress
    }
}

function global:npm {
    $s = $global:WebPublishTestState
    $nativeArgs = @($args)
    $s.npm_calls++
    $global:LASTEXITCODE = 0
    if ($nativeArgs[0] -eq 'ci') {
        if ($s.fail -eq 'install') { $global:LASTEXITCODE = 1 }
        return
    }
    $s.build_args = $nativeArgs
    if ($s.fail -eq 'build') { $global:LASTEXITCODE = 1; return }
    $outputIndex = [array]::IndexOf($nativeArgs, '--output-path')
    if ($outputIndex -lt 0) { throw 'Build must supply its own output directory' }
    $browser = Join-Path $nativeArgs[$outputIndex + 1] 'browser'
    $null = New-Item -Path $browser -ItemType Directory -Force
    if ($s.fail -ne 'missing-index') {
        '<html><head></head><body><app-root></app-root></body></html>' |
            Set-Content -LiteralPath (Join-Path $browser 'index.html') -Encoding utf8
    }
    'console.log("test build");' | Set-Content -LiteralPath (Join-Path $browser 'main-test.js') -Encoding utf8
}

function global:az {
    $s = $global:WebPublishTestState
    $s.azure_calls++
    $s.azure_args = @($args)
    $global:LASTEXITCODE = if ($s.fail -eq 'token') { 1 } else { 0 }
    if ($global:LASTEXITCODE -eq 0 -and $s.fail -ne 'empty-token') { 'test-only-deployment-secret' }
}

function global:npx {
    $s = $global:WebPublishTestState
    $s.upload_calls++
    $s.upload_args = @($args)
    $s.upload_token = $env:SWA_CLI_DEPLOYMENT_TOKEN
    $global:LASTEXITCODE = if ($s.fail -eq 'upload') { 1 } else { 0 }
}

function Invoke-Case {
    param([string] $Name, [string] $Failure, [switch] $BuildOnly, [scriptblock] $Before, [scriptblock] $Verify)
    $caseRoot = Join-Path $fixtureRoot $Name
    $null = New-Item -Path (Join-Path $caseRoot 'scripts') -ItemType Directory -Force
    $null = New-Item -Path (Join-Path $caseRoot 'web') -ItemType Directory -Force
    $project = Join-Path $caseRoot 'Angular źródła with spaces'
    $null = New-Item -Path $project -ItemType Directory -Force
    foreach ($requiredFile in @('angular.json', 'package.json', 'package-lock.json')) {
        '{}' | Set-Content -LiteralPath (Join-Path $project $requiredFile) -Encoding utf8
    }
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'scripts/Publish-Web.ps1') -Destination (Join-Path $caseRoot 'scripts/Publish-Web.ps1')
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'web/staticwebapp.config.json') -Destination (Join-Path $caseRoot 'web/staticwebapp.config.json')
    $global:WebPublishTestState = @{
        fail = $Failure; terraform_calls = 0; npm_calls = 0; azure_calls = 0; upload_calls = 0
        terraform_args = @(); build_args = @(); azure_args = @(); upload_args = @(); upload_token = $null
        deployment = @{
            subscription_id = '11111111-1111-1111-1111-111111111111'
            resource_group_name = 'rg-ecommercestore-web-dev'
            name = 'swa-ecommercestore-web-dev'
            hostname = 'test-site.azurestaticapps.net'
            base_url = 'https://test-site.azurestaticapps.net'
        }
    }
    $env:SWA_CLI_DEPLOYMENT_TOKEN = 'previous-test-token'
    if ($Before) { & $Before $global:WebPublishTestState $project $caseRoot }
    $beforeLocation = (Get-Location).Path
    $errorRecord = $null
    $result = @()
    try {
        $result = @(& (Join-Path $caseRoot 'scripts/Publish-Web.ps1') `
            -WebProjectPath $project -TerraformPath 'TestWebTerraform' -BuildOnly:$BuildOnly `
            -WarningAction SilentlyContinue)
    } catch { $errorRecord = $_ }
    Assert-That ((Get-Location).Path -eq $beforeLocation) "$Name changed the caller's directory"
    & $Verify $global:WebPublishTestState $result $errorRecord $caseRoot
    Write-Host "PASS $Name"
}

try {
    Invoke-Case -Name 'build-only' -BuildOnly -Verify {
        param($s, $result, $errorRecord)
        Assert-That ($null -eq $errorRecord) "Build-only failed: $errorRecord"
        Assert-That ($s.terraform_calls -eq 0 -and $s.azure_calls -eq 0 -and $s.upload_calls -eq 0) 'Build-only called a cloud/deployment tool'
        Assert-That ($s.npm_calls -eq 2 -and -not $result[-1].uploaded) 'Build-only must install, build and stop before upload'
        Assert-That (Test-Path -LiteralPath (Join-Path $result[-1].artifact_path 'main-test.js')) 'Compiled files were not staged'
        $config = Get-Content -LiteralPath (Join-Path $result[-1].artifact_path 'staticwebapp.config.json') -Raw | ConvertFrom-Json
        Assert-That ($config.navigationFallback.rewrite -eq '/index.html') 'Angular deep-link fallback was lost'
        Assert-That ('/api/*' -in $config.navigationFallback.exclude -and '/backend/*' -in $config.navigationFallback.exclude) 'API errors must not fall back to Angular HTML'
        Assert-That ($env:SWA_CLI_DEPLOYMENT_TOKEN -eq 'previous-test-token') 'Build-only changed the deployment token'
    }

    Invoke-Case -Name 'production-upload' -Verify {
        param($s, $result, $errorRecord)
        Assert-That ($null -eq $errorRecord -and $result[-1].uploaded) "Production upload failed: $errorRecord"
        Assert-That ($s.terraform_calls -eq 1 -and $s.upload_calls -eq 1) 'Expected exactly one target lookup and upload'
        Assert-That ($s.upload_token -eq 'test-only-deployment-secret') 'SWA token was not passed through the environment'
        Assert-That ($env:SWA_CLI_DEPLOYMENT_TOKEN -eq 'previous-test-token') 'Previous token was not restored'
        Assert-That ('--package=@azure/static-web-apps-cli@2.0.10' -in $s.upload_args -and '--no-use-keychain' -in $s.upload_args) 'Uploader must use a pinned CLI without storing credentials in the keychain'
        $envIndex = [array]::IndexOf($s.upload_args, '--env')
        Assert-That ($envIndex -ge 0 -and $s.upload_args[$envIndex + 1] -eq 'production') 'Upload targeted a preview environment'
        Assert-That ('test-only-deployment-secret' -notin $s.upload_args) 'Secret leaked into process arguments'
        Assert-That (($result | ConvertTo-Json -Depth 5) -notmatch 'test-only-deployment-secret') 'Secret leaked into script output'
        Assert-That ('--subscription' -in $s.azure_args -and $s.deployment.subscription_id -in $s.azure_args) 'Token lookup must select the target subscription explicitly'
        Assert-That ('production' -in $s.build_args -and '--output-path' -in $s.build_args) 'The Angular production build was not selected'
    }

    foreach ($failure in @('terraform', 'install', 'build', 'missing-index', 'token', 'empty-token')) {
        Invoke-Case -Name "reject-$failure" -Failure $failure -Verify {
            param($s, $result, $errorRecord)
            Assert-That ($null -ne $errorRecord) "Expected failure for $($s.fail)"
            Assert-That ($s.upload_calls -eq 0) "Uploaded after failure at $($s.fail)"
            Assert-That ($env:SWA_CLI_DEPLOYMENT_TOKEN -eq 'previous-test-token') 'Failure changed the caller token'
        }
    }

    Invoke-Case -Name 'restore-token-after-upload-failure' -Failure 'upload' -Verify {
        param($s, $result, $errorRecord)
        Assert-That ($null -ne $errorRecord -and $s.upload_calls -eq 1) 'Upload failure did not propagate'
        Assert-That ($env:SWA_CLI_DEPLOYMENT_TOKEN -eq 'previous-test-token') 'Failed upload left its token in the environment'
        Assert-That ($errorRecord.ToString() -notmatch 'test-only-deployment-secret') 'Failure message exposed the secret'
    }

    Invoke-Case -Name 'reject-wrong-stack' -Before {
        param($s)
        $s.deployment.name = 'ca-ecommercestore-products-dev'
    } -Verify {
        param($s, $result, $errorRecord)
        Assert-That ($null -ne $errorRecord -and $s.npm_calls -eq 0 -and $s.azure_calls -eq 0) 'Wrong Terraform stack was accepted'
    }

    Invoke-Case -Name 'reject-missing-lock' -Before {
        param($s, $project)
        Remove-Item -LiteralPath (Join-Path $project 'package-lock.json')
    } -Verify {
        param($s, $result, $errorRecord)
        Assert-That ($null -ne $errorRecord -and $s.terraform_calls -eq 0 -and $s.npm_calls -eq 0) 'Project without a lockfile was accepted'
    }

    Write-Host "All $script:checks offline uploader checks passed. No Azure resources were accessed."
} finally {
    $env:SWA_CLI_DEPLOYMENT_TOKEN = $originalToken
    foreach ($name in @('TestWebTerraform', 'npm', 'az', 'npx')) {
        Remove-Item -LiteralPath "Function:global:$name" -ErrorAction SilentlyContinue
    }
    Remove-Variable -Name WebPublishTestState -Scope Global -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
}

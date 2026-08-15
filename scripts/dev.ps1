<#
.SYNOPSIS
    Everyday SafeHer dev commands for Windows.

.DESCRIPTION
    The Makefile in the repo root covers the same ground, but `make` is not
    installed on Windows by default. This script is the equivalent that runs
    here.

.EXAMPLE
    .\scripts\dev.ps1 backend     # start the API the mobile app talks to
    .\scripts\dev.ps1 doctor      # is anything actually running / configured?
#>

param(
    [Parameter(Position = 0)]
    [ValidateSet('backend', 'backend-stop', 'doctor', 'test', 'test-backend',
                 'test-mobile', 'analyze', 'web', 'run', 'migrate', 'help')]
    [string]$Command = 'help'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Show-Help {
    Write-Host ""
    Write-Host "SafeHer dev commands" -ForegroundColor Cyan
    Write-Host "===================="
    Write-Host ""
    Write-Host "  backend       Start the FastAPI backend on :5000"
    Write-Host "                The mobile app calls http://127.0.0.1:5000/api/v1 --"
    Write-Host "                without this, sign-in fails with 'Cannot reach SafeHer'."
    Write-Host "  backend-stop  Stop whatever is listening on :5000"
    Write-Host "  doctor        Check the backend and platform config"
    Write-Host "  web           Run the app in Chrome"
    Write-Host "  run           Run the app on a connected device"
    Write-Host "  test          Backend + mobile suites"
    Write-Host "  analyze       flutter analyze"
    Write-Host "  migrate       alembic upgrade head"
    Write-Host ""
}

function Get-BackendPids {
    # `netstat` rather than Get-NetTCPConnection: available in every shell and
    # does not need elevation.
    netstat -ano |
        Select-String ':5000\s' |
        Select-String 'LISTENING' |
        ForEach-Object { ($_ -split '\s+')[-1] } |
        Sort-Object -Unique
}

function Invoke-Doctor {
    Write-Host ""
    Write-Host "Backend (:5000)" -ForegroundColor Cyan
    try {
        $r = Invoke-WebRequest -Uri 'http://127.0.0.1:5000/api/v1/health' `
            -TimeoutSec 5 -UseBasicParsing
        Write-Host "  health -> HTTP $($r.StatusCode)" -ForegroundColor Green
    } catch {
        Write-Host "  DOWN - run: .\scripts\dev.ps1 backend" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Firebase platform config" -ForegroundColor Cyan

    $androidCfg = 'mobile/android/app/google-services.json'
    if (Test-Path $androidCfg) {
        $json = Get-Content $androidCfg -Raw | ConvertFrom-Json
        $types = @($json.client[0].oauth_client | ForEach-Object { $_.client_type })
        if ($types -contains 1) {
            Write-Host "  android  Google sign-in READY (SHA-1 registered)" -ForegroundColor Green
        } else {
            Write-Host "  android  BLOCKED - no OAuth client; register the SHA-1" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  android  google-services.json MISSING" -ForegroundColor Red
    }

    if (Test-Path 'mobile/ios/Runner/GoogleService-Info.plist') {
        Write-Host "  ios      config present (unverified by a build)" -ForegroundColor Green
    } else {
        Write-Host "  ios      GoogleService-Info.plist MISSING" -ForegroundColor Red
    }
    Write-Host "  web      uses firebase_options.dart - no extra config" -ForegroundColor Green
    Write-Host ""
}

switch ($Command) {
    'backend' {
        Write-Host "Starting backend on http://127.0.0.1:5000 (Ctrl+C to stop)..." -ForegroundColor Cyan
        python -m uvicorn fastapi_app.main:app --host 127.0.0.1 --port 5000 --reload
    }
    'backend-stop' {
        $pids = Get-BackendPids
        if (-not $pids) {
            Write-Host "Nothing listening on :5000"
        } else {
            foreach ($processId in $pids) {
                taskkill /PID $processId /F | Out-Null
                Write-Host "Stopped PID $processId" -ForegroundColor Green
            }
        }
    }
    'doctor'       { Invoke-Doctor }
    'web'          { Set-Location mobile; flutter run -d chrome }
    'run'          { Set-Location mobile; flutter run }
    'analyze'      { Set-Location mobile; flutter analyze }
    'migrate'      { python -m alembic upgrade head }
    'test-backend' {
        # test_api_gateway / test_integration drive a live server over HTTP,
        # so they are excluded here; run them with the backend up.
        python -m pytest tests/ -q --ignore=tests/test_api_gateway.py `
            --ignore=tests/test_integration.py
    }
    'test-mobile'  { Set-Location mobile; flutter test }
    'test' {
        python -m pytest tests/ -q --ignore=tests/test_api_gateway.py `
            --ignore=tests/test_integration.py
        Set-Location mobile
        flutter test
    }
    default { Show-Help }
}

param(
    [switch]$SkipDocker,
    [switch]$SkipBackend,
    [switch]$StartMobile,
    [string]$DeviceId = "chrome"
)

$ErrorActionPreference = "Stop"

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$composeFile = Join-Path $projectRoot "deployment\docker\docker-compose.yml"
$mobilePath = Join-Path $projectRoot "mobile"
$defaultDatabaseUrl = "postgresql://safeher:safeher@localhost:5432/safeher"
$fallbackDatabaseUrl = "sqlite:///./safeher.db"

function Resolve-Python {
    $candidates = @(
        (Join-Path $projectRoot "..\.venv\Scripts\python.exe"),
        (Join-Path $projectRoot ".venv\Scripts\python.exe"),
        "python"
    )

    foreach ($candidate in $candidates) {
        if ($candidate -eq "python") {
            try {
                python --version | Out-Null
                return "python"
            } catch {
                continue
            }
        }

        if (Test-Path $candidate) {
            return $candidate
        }
    }

    throw "Python executable not found."
}

$pythonCmd = Resolve-Python

function Resolve-BackendHostForDevice([string]$targetDevice) {
    if ($targetDevice -eq "chrome") {
        return "localhost"
    }

    if ($targetDevice -match "emulator|android") {
        return "10.0.2.2"
    }

    return "localhost"
}

function Test-PostgresReachable {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect("127.0.0.1", 5432, $null, $null)
        $connected = $iar.AsyncWaitHandle.WaitOne(1500, $false)
        if (-not $connected) {
            $client.Close()
            return $false
        }
        $client.EndConnect($iar)
        $client.Close()
        return $true
    } catch {
        return $false
    }
}

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "  SafeHer Unified Launcher" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Project root: $projectRoot"

if (-not $SkipDocker) {
    Write-Host "Starting Docker services (Postgres, Redis, MQTT)..." -ForegroundColor Yellow
    docker compose -f "$composeFile" up -d postgres redis mqtt
}

if (-not $SkipBackend) {
    $selectedDatabaseUrl = $defaultDatabaseUrl
    if (-not (Test-PostgresReachable)) {
        $selectedDatabaseUrl = $fallbackDatabaseUrl
        Write-Warning "PostgreSQL not reachable on localhost:5432. Falling back to SQLite ($fallbackDatabaseUrl)."
    }

    $backendCmd = "cd `"$projectRoot`"; `$env:DATABASE_URL=`"$selectedDatabaseUrl`"; $pythonCmd -m uvicorn fastapi_app.main:app --host 0.0.0.0 --port 5000"
    Write-Host "Starting FastAPI backend on port 5000..." -ForegroundColor Yellow
    Write-Host "Using DATABASE_URL=$selectedDatabaseUrl" -ForegroundColor DarkGray
    Start-Process pwsh -ArgumentList "-NoExit", "-Command", $backendCmd | Out-Null
}

if ($StartMobile) {
    $backendHost = Resolve-BackendHostForDevice $DeviceId
    $apiBase = "http://$backendHost:5000/api/v1"
    $wsBase = "ws://$backendHost:5000/api/v1/ws/alerts"
    $mobileCmd = "cd `"$mobilePath`"; flutter run -d $DeviceId --dart-define=API_BASE_URL=$apiBase --dart-define=WS_BASE_URL=$wsBase --dart-define=MQTT_HOST=$backendHost"
    Write-Host "Starting Flutter mobile app on '$DeviceId'..." -ForegroundColor Yellow
    Write-Host "Using API base URL: $apiBase" -ForegroundColor DarkGray
    Start-Process pwsh -ArgumentList "-NoExit", "-Command", $mobileCmd | Out-Null
}

Start-Sleep -Seconds 2

Write-Host ""
Write-Host "Health checks:" -ForegroundColor Cyan

try {
    $apiHealth = Invoke-RestMethod -Uri "http://localhost:5000/api/v1/health" -TimeoutSec 5
    Write-Host "  API:      reachable" -ForegroundColor Green
} catch {
    Write-Host "  API:      unreachable" -ForegroundColor Red
}

try {
    $processorHealth = Invoke-RestMethod -Uri "http://localhost:8080/health" -TimeoutSec 5
    Write-Host "  Processor: reachable" -ForegroundColor Green
} catch {
    Write-Host "  Processor: unreachable" -ForegroundColor Red
}

Write-Host ""
Write-Host "Done. Use 'docker compose -f $composeFile down' to stop containers." -ForegroundColor Cyan

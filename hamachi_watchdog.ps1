## produccion

# ============================================================
#  Hamachi Watchdog
#  by Aaron Galarza — github.com/Aaron-Galarza
#
#  Verifica estado de Hamachi cada 30s.
#  Si detecta redes offline o Hamachi apagado, las reactiva.
# ============================================================

param(
    [string]$LogFile = (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "hamachi_watchdog.log"),
    [string]$TargetNetwork = "",
    [string]$targetIP      = ""
)

$HAMACHI        = "C:\Program Files (x86)\LogMeIn Hamachi\x64\hamachi-2.exe"
$MAX_LOG_KB     = 512
$CHECK_INTERVAL = 5
$FAIL_THRESHOLD = 3

# ── Helpers ──────────────────────────────────────────────────

function Write-Log {
    param([string]$msg, [string]$level = "INFO")
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$level] $msg"
    Add-Content -Path $LogFile -Value $line
    Write-Host $line
}

function Rotate-Log {
    if (Test-Path $LogFile) {
        $kb = (Get-Item $LogFile).Length / 1KB
        if ($kb -gt $MAX_LOG_KB) {
            $backup = $LogFile -replace "\.log$", "_old.log"
            Move-Item $LogFile $backup -Force
            Write-Log "Log rotado (supero $MAX_LOG_KB KB)."
        }
    }
}

# ── Parsear estado de Hamachi ─────────────────────────────────
# Devuelve objeto con:
#   .PoweredOn    : bool
#   .Online       : lista de nombres de redes online
#   .Offline      : lista de nombres de redes offline

function Get-HamachiState {
    $raw   = & $HAMACHI --cli list 2>&1
    $state = @{ PoweredOn = $false; Online = @(); Offline = @() }

    foreach ($line in $raw) {
        if ($line -match '^\s*\*\s*\[(.+?)\]') {
            $state.PoweredOn = $true
            $netName = $Matches[1]
            if (-not $TargetNetwork -or $netName -eq $TargetNetwork) {
                $state.Online += $netName
            }
        } elseif ($line -match '^\s*\[(.+?)\]') {
            $state.PoweredOn = $true
            $netName = $Matches[1]
            if (-not $TargetNetwork -or $netName -eq $TargetNetwork) {
                $state.Offline += $netName
            }
        }
    }
    return $state
}

# ── Recuperar Hamachi ─────────────────────────────────────────

function Restore-Hamachi {
    param($state)

    # 1. Si esta apagado, encender
    if (-not $state.PoweredOn) {
        Write-Log "Hamachi apagado. Ejecutando logon..." "WARN"
        & $HAMACHI --cli logon | Out-Null
        Start-Sleep -Seconds 5
        Write-Log "Logon ejecutado."
        # Re-parsear estado tras logon
        $state = Get-HamachiState
    }

    # 2. Reconectar redes offline
    if ($state.Offline.Count -gt 0) {
        foreach ($net in $state.Offline) {
            Write-Log "Red offline: '$net'. Reconectando..." "WARN"
            & $HAMACHI --cli go-online $net | Out-Null
            Start-Sleep -Seconds 3
            Write-Log "go-online '$net' ejecutado."
        }
    }
}

# ── Main loop ─────────────────────────────────────────────────

$logDir = Split-Path $LogFile
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

$scope = if ($TargetNetwork) { "Red: $TargetNetwork | IP: $TargetIP" } else { "Todas las redes" }
Write-Log "=== Watchdog iniciado | $scope | Chequeo cada ${CHECK_INTERVAL}s | Recuperacion tras $FAIL_THRESHOLD fallos ==="

$failCount = 0

while ($true) {
    Rotate-Log

    $state = Get-HamachiState

    if (-not $state.PoweredOn) {
        $failCount++
        Write-Log "FALLO $failCount/$FAIL_THRESHOLD - Hamachi apagado." "WARN"
    } elseif ($state.Offline.Count -gt 0) {
        $failCount++
        $offlineList = $state.Offline -join ", "
        Write-Log "FALLO $failCount/$FAIL_THRESHOLD - Redes offline: $offlineList" "WARN"
    } else {
        $failCount = 0
        $onlineList = $state.Online -join ", "
        $ipInfo = if ($TargetIP) { " | IP: $TargetIP" } else { "" }
        Write-Log "OK - Red online: $onlineList$ipInfo"
    }

    if ($failCount -ge $FAIL_THRESHOLD) {
        Write-Log "CRITICO - $FAIL_THRESHOLD fallos consecutivos. Recuperando Hamachi..." "ERROR"
        Restore-Hamachi $state
        $failCount = 0

        Start-Sleep -Seconds 10

        # Verificacion post-recuperacion
        $statePost = Get-HamachiState
        if ($statePost.PoweredOn -and $statePost.Offline.Count -eq 0) {
            Write-Log "RECUPERADO - todas las redes online: $($statePost.Online -join ', ')"
        } else {
            Write-Log "CRITICO - no se pudo recuperar. Revisar manualmente." "ERROR"
        }
    }

    Start-Sleep -Seconds $CHECK_INTERVAL
}
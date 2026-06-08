# ============================================================
#  Hamachi Watchdog - by Aaron Galarza
#  github.com/Aaron-Galarza
#
#  Verifica conectividad Hamachi cada 30s.
#  Reinicia el servicio tras 3 fallos consecutivos.
# ============================================================

param(
    [string]$TargetIP = "",
    [string]$LogFile  = "C:\HamachiMonitor\hamachi_watchdog.log"
)

$HAMACHI_SVC    = "Hamachi2Svc"
$HAMACHI_GUI    = "C:\Program Files (x86)\LogMeIn Hamachi\hamachi-2-ui.exe"
$MAX_LOG_KB     = 512
$CHECK_INTERVAL = 30
$FAIL_THRESHOLD = 3

# ── Helpers ─────────────────────────────────────────────────

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

function Test-HamachiPing {
    param([string]$ip)
    $result = ping -n 2 -w 3000 $ip 2>&1
    return ($result -match "TTL=")
}

function Get-FirstPeerIP {
    $hamachi = "C:\Program Files (x86)\LogMeIn Hamachi\x64\hamachi-2.exe"
    $raw = & $hamachi --cli list 2>&1
    foreach ($line in $raw) {
        if ($line -match '(\d+\.\d+\.\d+\.\d+)') {
            return $Matches[1]
        }
    }
    return $null
}

function Restart-Hamachi {
    Write-Log "Reiniciando Hamachi..." "WARN"

    $gui = Get-Process -Name "hamachi-2-ui" -ErrorAction SilentlyContinue
    if ($gui) { $gui | Stop-Process -Force; Write-Log "GUI cerrada." }

    Stop-Service -Name $HAMACHI_SVC -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
    Start-Service -Name $HAMACHI_SVC -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 8

    $svc = Get-Service -Name $HAMACHI_SVC
    if ($svc.Status -ne "Running") {
        Write-Log "FALLO: el servicio no levanto despues del reinicio." "ERROR"
        return $false
    }
    Write-Log "Servicio reiniciado OK."

    $sessions = query session 2>&1 | Select-String "Active"
    if ($sessions) {
        Start-Process -FilePath $HAMACHI_GUI -ArgumentList "--auto-start" -WindowStyle Minimized
        Write-Log "GUI relanzada."
    } else {
        Write-Log "Sin sesion interactiva activa, GUI no relanzada."
    }

    return $true
}

# ── Resoler IP target ────────────────────────────────────────

$logDir = Split-Path $LogFile
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

if (-not $TargetIP) {
    $TargetIP = Get-FirstPeerIP
    if (-not $TargetIP) {
        Write-Log "No se pudo detectar ningun peer. Verifica que Hamachi este conectado." "ERROR"
        exit 1
    }
    Write-Log "IP target detectada automaticamente: $TargetIP"
}

# ── Main loop ────────────────────────────────────────────────

Write-Log "=== Watchdog iniciado. Target: $TargetIP | Chequeo cada ${CHECK_INTERVAL}s | Reinicio tras $FAIL_THRESHOLD fallos consecutivos ==="

$failCount = 0

while ($true) {
    Rotate-Log

    if (Test-HamachiPing $TargetIP) {
        $failCount = 0
        Write-Log "OK - ping a $TargetIP respondio."
    } else {
        $failCount++
        Write-Log "FALLO $failCount/$FAIL_THRESHOLD - sin respuesta de $TargetIP." "WARN"

        if ($failCount -ge $FAIL_THRESHOLD) {
            Write-Log "CRITICO - $FAIL_THRESHOLD fallos consecutivos. Reiniciando Hamachi..." "ERROR"
            $ok = Restart-Hamachi
            $failCount = 0

            Start-Sleep -Seconds 20

            if ($ok -and (Test-HamachiPing $TargetIP)) {
                Write-Log "RECUPERADO - ping OK tras reinicio."
            } else {
                Write-Log "CRITICO - sigue sin ping tras reinicio. Revisar manualmente." "ERROR"
            }
        }
    }

    Start-Sleep -Seconds $CHECK_INTERVAL
}

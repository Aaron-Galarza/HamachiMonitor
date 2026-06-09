# ============================================================
#  Hamachi Monitor (audHam)
#  by Aaron Galarza — github.com/Aaron-Galarza
# ============================================================

param(
    [switch]$Test
)

$HAMACHI    = "C:\Program Files (x86)\LogMeIn Hamachi\x64\hamachi-2.exe"
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$LOG_FILE   = if ($Test) { Join-Path $SCRIPT_DIR "hamachi_watchdog.log" } else { "C:\HamachiMonitor\hamachi_watchdog.log" }

function Show-Header {
    param([string]$subtitle = "")
    Clear-Host
    Write-Host ""
    Write-Host "  +======================================================+" -ForegroundColor Cyan
    Write-Host "  |          ARANDUSOFT - HAMACHI MONITOR                |" -ForegroundColor Cyan
    Write-Host "  |          github.com/Aaron-Galarza                    |" -ForegroundColor DarkCyan
    Write-Host "  +======================================================+" -ForegroundColor Cyan
    Write-Host ""
    Write-Host ("  Equipo : " + $env:COMPUTERNAME) -ForegroundColor White
    Write-Host ("  Fecha  : " + (Get-Date -Format "dd/MM/yyyy HH:mm:ss")) -ForegroundColor White
    if ($subtitle) { Write-Host ("  Red    : " + $subtitle) -ForegroundColor White }
    Write-Host ""
}

# ── Parsear redes ────────────────────────────────────────────
$raw        = & $HAMACHI --cli list 2>&1
$networks   = @()
$currentNet = $null

foreach ($line in $raw) {
    if ($line -match '^\s*\*\s*\[(.+?)\](.*)') {
        if ($currentNet) { $networks += $currentNet }
        $currentNet = @{ Name = $Matches[1]; Info = $line.Trim(); Peers = @() }
    } elseif ($line -match '^\s*\*\s' -and $currentNet) {
        $currentNet.Peers += $line.Trim()
    }
}
if ($currentNet) { $networks += $currentNet }

# ── Pantalla principal ───────────────────────────────────────
Show-Header
Write-Host "  REDES DETECTADAS:" -ForegroundColor Yellow
Write-Host "  ------------------------------------------------------" -ForegroundColor DarkGray

if ($networks.Count -eq 0) {
    Write-Host "  [!] No se detectaron redes. Hamachi esta apagado o sin redes." -ForegroundColor Red
    Write-Host ""
    exit
}

for ($i = 0; $i -lt $networks.Count; $i++) {
    $n = $networks[$i]
    Write-Host ("  [" + ($i + 1) + "] " + $n.Name) -ForegroundColor Green
    foreach ($p in $n.Peers) {
        if ($p -match '\*\s+(\S+)\s+(\S+)\s+(\d+\.\d+\.\d+\.\d+)\s+.*?(direct|relayed|via)\s+(\S+)') {
            $pName  = $Matches[2]
            $pIP    = $Matches[3]
            $pMode  = $Matches[4]
            $pProto = $Matches[5]
            $color  = if ($pMode -eq "direct") { "Gray" } else { "Yellow" }
            Write-Host ("      - " + $pName.PadRight(25) + $pIP.PadRight(18) + $pMode.PadRight(10) + $pProto) -ForegroundColor $color
        } else {
            Write-Host ("      " + $p) -ForegroundColor Gray
        }
    }
    Write-Host ""
}

Write-Host "  ------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""
Write-Host ("  Selecciona red a auditar (1-" + $networks.Count + "), o 0 para log general: ") -ForegroundColor Cyan -NoNewline
$sel = Read-Host

# ── Seleccion de red y IP target ─────────────────────────────
$targetIP   = $null
$selName    = ""
$suggestedIP = $null

if ($sel -eq "0") {
    $selName = "LOG GENERAL"
} elseif ($sel -match "^\d+$" -and [int]$sel -ge 1 -and [int]$sel -le $networks.Count) {
    $net     = $networks[[int]$sel - 1]
    $selName = $net.Name

    # Sugerir IP del primer peer
    foreach ($p in $net.Peers) {
        if ($p -match '(\d+\.\d+\.\d+\.\d+)') {
            $suggestedIP = $Matches[1]
            break
        }
    }

    Write-Host ""
    Write-Host " Peers en '$($net.Name)':" -ForegroundColor Yellow
    $peerIPs = @()
    foreach ($p in $net.Peers) {
        if ($p -match '\*?\s*\S+\s+(\S+)\s+(\d+\.\d+\.\d+\.\d+)') {
            $peerIPs += $Matches[2]
            Write-Host ("   [" + $peerIPs.Count + "] " + $Matches[1].PadRight(25) + $Matches[2]) -ForegroundColor Gray
        }
    }

    Write-Host ""
    if ($peerIPs.Count -ge 1) {
        Write-Host ("  Selecciona peer a targetear (1-" + $peerIPs.Count + ") o Enter para el primero: ") -ForegroundColor Cyan -NoNewline
        $selPeer = Read-Host
        if ($selPeer -eq "") {
            $targetIP = $peerIPs[0]
        } elseif ($selPeer -match '^\d+$' -and [int]$selPeer -ge 1 -and [int]$selPeer -le $peerIPs.Count) {
            $targetIP = $peerIPs[[int]$selPeer - 1]
        } else {
            Write-Host "  Seleccion invalida." -ForegroundColor Red
            exit
        }
    } else {
        Write-Host "  No hay peers conectados en esta red." -ForegroundColor Red
        exit
    }

    # Verificacion rapida de ping antes de arrancar
    Write-Host ""
    Write-Host ("  Verificando ping a " + $targetIP + "...") -ForegroundColor DarkGray -NoNewline
    $pingOk = (ping -n 1 -w 2000 $targetIP 2>&1) -match "TTL="
    if ($pingOk) {
        Write-Host " OK" -ForegroundColor Green
    } else {
        Write-Host " Sin respuesta (puede estar offline)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  Seleccion invalida." -ForegroundColor Red
    exit
}

# ── Actualizar watchdog con la IP elegida ────────────────────
# ── Modo watchdog ─────────────────────────────────────────────
$watchdogScript = if ($Test) { Join-Path $SCRIPT_DIR "hamachi_watchdog.ps1" } else { "C:\HamachiMonitor\hamachi_watchdog.ps1" }

Write-Host ""
Write-Host "  MODO WATCHDOG:" -ForegroundColor Yellow
Write-Host "  ------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "  [1] Solo esta sesion    (se detiene al cerrar terminal)" -ForegroundColor White
Write-Host "  [2] Siempre automatico  (corre aunque no haya sesion)  " -ForegroundColor White
Write-Host "  [3] Desactivar watchdog automatico                     " -ForegroundColor White
Write-Host ""
Write-Host "  Selecciona modo (1-3): " -ForegroundColor Cyan -NoNewline
$selModo = Read-Host

if ($selModo -eq "1") {
    # Arrancar watchdog como job en esta sesion
    $job = Start-Job -ScriptBlock {
        param($script)
        powershell -ExecutionPolicy Bypass -File $script
    } -ArgumentList $watchdogScript
    Write-Host "  Watchdog iniciado en esta sesion (Job ID: $($job.Id))." -ForegroundColor Green

} elseif ($selModo -eq "2") {
    # Registrar o actualizar tarea programada
    if ($Test) {
        Write-Host "  [TEST] Se omite registro de tarea programada." -ForegroundColor DarkGray
    } else {
        $taskAction = New-ScheduledTaskAction `
            -Execute "powershell.exe" `
            -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$watchdogScript`""
        if (Get-ScheduledTask -TaskName "HamachiWatchdog" -ErrorAction SilentlyContinue) {
            Set-ScheduledTask -TaskName "HamachiWatchdog" -Action $taskAction | Out-Null
        } else {
            Write-Host "  No existe tarea programada. Ejecuta el instalador primero." -ForegroundColor Red
            exit
        }
        Start-ScheduledTask -TaskName "HamachiWatchdog"
        Write-Host "  Watchdog automatico activado." -ForegroundColor Green
    }

} elseif ($selModo -eq "3") {
    # Desactivar tarea programada y matar procesos watchdog
    if ($Test) {
        Write-Host "  [TEST] Se omite desactivacion de tarea programada." -ForegroundColor DarkGray
    } else {
        Stop-ScheduledTask -TaskName "HamachiWatchdog" -ErrorAction SilentlyContinue
        Write-Host "  Watchdog automatico desactivado." -ForegroundColor Green
    }
    # Matar jobs de watchdog de esta sesion si existen
    Get-Job | Where-Object { $_.State -eq "Running" } | Stop-Job
    Get-Job | Remove-Job
    Write-Host "  Jobs de sesion detenidos." -ForegroundColor Green
    exit

} else {
    Write-Host "  Seleccion invalida." -ForegroundColor Red
    exit
}

# ── Pantalla de auditoria ────────────────────────────────────
# ── Pantalla de auditoria ────────────────────────────────────
Write-Host ""
Write-Host ("  Red    : " + $selName) -ForegroundColor White
if ($targetIP) { Write-Host ("  Target : " + $targetIP) -ForegroundColor White }
Write-Host ("  Log    : " + $LOG_FILE) -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Ctrl+C para salir" -ForegroundColor DarkGray
Write-Host "  ------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

if (-not (Test-Path $LOG_FILE)) { New-Item -ItemType File -Path $LOG_FILE -Force | Out-Null }
Get-Content $LOG_FILE -Wait

Clear-Content $LOG_FILE -ErrorAction SilentlyContinue
Get-Content $LOG_FILE -Wait
# ============================================================
#  Hamachi Monitor (audHam)
#  by Aaron Galarza — github.com/Aaron-Galarza
# ============================================================

$HAMACHI  = "C:\Program Files (x86)\LogMeIn Hamachi\x64\hamachi-2.exe"
$LOG_FILE = "C:\HamachiMonitor\hamachi_watchdog.log"

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
    if ($suggestedIP) {
        Write-Host ("  IP target para monitorear [Enter para usar " + $suggestedIP + "]: ") -ForegroundColor Cyan -NoNewline
    } else {
        Write-Host "  IP target para monitorear: " -ForegroundColor Cyan -NoNewline
    }
    $inputIP = Read-Host

    if ($inputIP -eq "" -and $suggestedIP) {
        $targetIP = $suggestedIP
    } elseif ($inputIP -match '^\d+\.\d+\.\d+\.\d+$') {
        $targetIP = $inputIP
    } else {
        Write-Host "  IP invalida." -ForegroundColor Red
        exit
    }
} else {
    Write-Host "  Seleccion invalida." -ForegroundColor Red
    exit
}

# ── Actualizar watchdog con la IP elegida ────────────────────
if ($targetIP) {
    $watchdogScript = "C:\HamachiMonitor\hamachi_watchdog.ps1"
    $wContent = Get-Content $watchdogScript -Raw
    # Reemplazar el parametro TargetIP en la tarea programada
    $taskAction = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$watchdogScript`" -TargetIP `"$targetIP`""
    Set-ScheduledTask -TaskName "HamachiWatchdog" -Action $taskAction -ErrorAction SilentlyContinue | Out-Null
}

# ── Pantalla de auditoria ────────────────────────────────────
Show-Header $selName
if ($targetIP) { Write-Host ("  Target : " + $targetIP) -ForegroundColor White }
Write-Host ("  Log    : " + $LOG_FILE) -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Ctrl+C para salir" -ForegroundColor DarkGray
Write-Host "  ------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

Clear-Content $LOG_FILE -ErrorAction SilentlyContinue
Get-Content $LOG_FILE -Wait

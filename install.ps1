# ============================================================
#  Hamachi Monitor - Installer
#  by Aaron Galarza — github.com/Aaron-Galarza
#
#  Uso: ejecutar como Administrador en PowerShell
#  iex (iwr "https://raw.githubusercontent.com/Aaron-Galarza/hamachi-monitor/main/install.ps1").Content
# ============================================================

$BASE      = "C:\HamachiMonitor"
$BIN       = "$BASE\bin"
$REPO      = "https://raw.githubusercontent.com/Aaron-Galarza/hamachi-monitor/main"
$TASK_NAME = "HamachiWatchdog"

Write-Host ""
Write-Host "  +======================================================+" -ForegroundColor Cyan
Write-Host "  |       HAMACHI MONITOR - INSTALADOR                   |" -ForegroundColor Cyan
Write-Host "  |       github.com/Aaron-Galarza                       |" -ForegroundColor DarkCyan
Write-Host "  +======================================================+" -ForegroundColor Cyan
Write-Host ""

# ── 1. Crear carpetas ────────────────────────────────────────
New-Item -ItemType Directory -Path $BASE -Force | Out-Null
New-Item -ItemType Directory -Path $BIN  -Force | Out-Null
Write-Host "[OK] Carpetas creadas." -ForegroundColor Green

# ── 2. Descargar archivos ────────────────────────────────────
$files = @(
    @{ url = "$REPO/hamachi_watchdog.ps1"; dest = "$BASE\hamachi_watchdog.ps1" },
    @{ url = "$REPO/audHam_runner.ps1";    dest = "$BIN\audHam_runner.ps1"    },
    @{ url = "$REPO/audHam.bat";           dest = "$BIN\audHam.bat"           }
)

foreach ($f in $files) {
    Invoke-WebRequest -Uri $f.url -OutFile $f.dest -UseBasicParsing
    Write-Host ("[OK] Descargado: " + (Split-Path $f.dest -Leaf)) -ForegroundColor Green
}

# ── 3. ExecutionPolicy ──────────────────────────────────────
Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy Bypass -Force
Write-Host "[OK] ExecutionPolicy configurada." -ForegroundColor Green

# ── 4. Agregar bin al PATH ───────────────────────────────────
$currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($currentPath -notlike "*HamachiMonitor\bin*") {
    [Environment]::SetEnvironmentVariable("Path", "$currentPath;$BIN", "Machine")
    Write-Host "[OK] PATH actualizado." -ForegroundColor Green
} else {
    Write-Host "[OK] PATH ya configurado." -ForegroundColor Green
}

# ── 5. Registrar tarea programada ───────────────────────────
Write-Host ""
Write-Host "  Ingresa el usuario de Windows para la tarea programada: " -ForegroundColor Cyan -NoNewline
$user = Read-Host
Write-Host "  Ingresa la contrasena de Windows: " -ForegroundColor Cyan -NoNewline
$passSecure = Read-Host -AsSecureString
$pass = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($passSecure))

Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false -ErrorAction SilentlyContinue

$action   = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$BASE\hamachi_watchdog.ps1`""
$trigger  = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 2) -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask -TaskName $TASK_NAME -Action $action -Trigger $trigger -RunLevel Highest -User "$env:COMPUTERNAME\$user" -Password $pass -Settings $settings | Out-Null
Start-ScheduledTask -TaskName $TASK_NAME

Write-Host "[OK] Tarea '$TASK_NAME' registrada e iniciada." -ForegroundColor Green

# ── 6. Listo ─────────────────────────────────────────────────
Write-Host ""
Write-Host "  +======================================================+" -ForegroundColor Green
Write-Host "  |  Instalacion completada.                             |" -ForegroundColor Green
Write-Host "  |  Abri una terminal nueva y ejecuta: audHam           |" -ForegroundColor Green
Write-Host "  +======================================================+" -ForegroundColor Green
Write-Host ""

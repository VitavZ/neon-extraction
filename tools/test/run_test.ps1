# Bezpieczne uruchomienie testu gry (plik celowo bez polskich znakow - PowerShell 5.1 czyta go jako ANSI).
# Slot 4 = kopia slotu 1, kopie settings.cfg/achievements.cfg, po tescie sprzatanie slotu 4,
# przywrocenie plikow i kontrola hashy slotow 1-3.
# Uzycie:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\test\run_test.ps1 [-Script res://tools/test/smoke.gd] [-Out <katalog>] [-TimeoutSec 120]
param(
	[string]$Script = "res://tools/test/smoke.gd",
	[string]$Out = "",
	[int]$TimeoutSec = 120
)
$ErrorActionPreference = "Stop"
$godot = "C:\Users\Kamil\Desktop\Godot\Godot_v4.7.2-stable_win64_console.exe"
$project = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$data = Join-Path $env:APPDATA "Godot\app_userdata\Neon Extraction"
if ($Out -eq "") { $Out = Join-Path $env:TEMP "neon_test_shots" }
New-Item -ItemType Directory -Force $Out | Out-Null
Get-ChildItem $Out -Filter *.png -ErrorAction SilentlyContinue | Remove-Item -Force

$backup = Join-Path $env:TEMP ("neon_test_backup_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force $backup | Out-Null

function Get-SlotHashes {
	$h = @{}
	Get-ChildItem $data -File | Where-Object { $_.Name -match '^neon_extraction_save_[123]\.json' } | ForEach-Object {
		$h[$_.Name] = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
	}
	return $h
}

$before = Get-SlotHashes
foreach ($f in "settings.cfg", "achievements.cfg") {
	$p = Join-Path $data $f
	if (Test-Path $p) { Copy-Item $p (Join-Path $backup $f) }
}
$slot4 = Join-Path $data "neon_extraction_save_4.json"
Copy-Item (Join-Path $data "neon_extraction_save_1.json") $slot4 -Force

$log = Join-Path $Out "godot_log.txt"
$exit = -1
try {
	$p = Start-Process -FilePath $godot -ArgumentList @("--path", "`"$project`"", "--script", $Script, "--", "`"$Out`"") `
		-RedirectStandardOutput $log -RedirectStandardError "$log.err" -PassThru -NoNewWindow
	$null = $p.Handle  # bez tego ExitCode bywa pusty
	if (-not $p.WaitForExit($TimeoutSec * 1000)) {
		$p.Kill()
		Write-Output "TIMEOUT po $TimeoutSec s"
	} else {
		$exit = $p.ExitCode
	}
} finally {
	# sprzatanie slotu 4 i przywrocenie ustawien - zawsze, takze po bledzie
	foreach ($suffix in "", ".bak", ".tmp", ".v1_backup") {
		$f = $slot4 + $suffix
		if (Test-Path $f) { Remove-Item $f -Force }
	}
	foreach ($f in "settings.cfg", "achievements.cfg") {
		$b = Join-Path $backup $f
		$p2 = Join-Path $data $f
		if (Test-Path $b) { Copy-Item $b $p2 -Force } elseif (Test-Path $p2) { Remove-Item $p2 -Force }
	}
	Remove-Item $backup -Recurse -Force
}

$after = Get-SlotHashes
$ok = $true
foreach ($k in $before.Keys) {
	if ($after[$k] -ne $before[$k]) { Write-Output "UWAGA: zmienil sie $k !"; $ok = $false }
}
Write-Output ("Sloty 1-3: " + $(if ($ok) { "bez zmian" } else { "ZMIENIONE" }))
Write-Output "Kod wyjscia Godota: $exit"
$all = @(Get-Content $log -Encoding UTF8 -ErrorAction SilentlyContinue) + @(Get-Content "$log.err" -Encoding UTF8 -ErrorAction SilentlyContinue)
$errs = $all | Where-Object { $_ -match 'SCRIPT ERROR|^ERROR|Parse Error|Invalid call|Invalid access|Nonexistent function|WARNING' -and $_ -notmatch '2D MSAA is enabled while there is no 2D content' }
if ($errs) { Write-Output "--- BLEDY / OSTRZEZENIA ---"; $errs | Select-Object -First 40 }
$all | Where-Object { $_ -match '^\[TEST\]' }
Write-Output "Zrzuty: $Out"


# =====================================
# OpenSteamTool Installer
# =====================================

# Relaunch with administrator rights when started from a regular PowerShell window.
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
$isAdministrator = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdministrator) {
    $temporaryElevationScript = $false
    try {
        $workingDirectory = (Get-Location).Path
        if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
            # `irm <url> | iex` has no script path. Persist the in-memory script
            # temporarily so Windows can relaunch it through UAC.
            $scriptPath = Join-Path $env:TEMP ("install-skytools-elevated-{0}.ps1" -f [Guid]::NewGuid().ToString("N"))
            $temporaryElevationScript = $true
            $scriptContent = [string]$MyInvocation.MyCommand.Definition
            if ([string]::IsNullOrWhiteSpace($scriptContent)) {
                throw "The installer content could not be prepared for administrator mode."
            }
            [System.IO.File]::WriteAllText(
                $scriptPath,
                $scriptContent,
                (New-Object System.Text.UTF8Encoding($true)))
        } else {
            $scriptPath = [System.IO.Path]::GetFullPath($PSCommandPath)
            if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
                $workingDirectory = $PSScriptRoot
            }
        }
        $argumentList = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argumentList -WorkingDirectory $workingDirectory -ErrorAction Stop
    } catch {
        if ($temporaryElevationScript -and $scriptPath -and (Test-Path -LiteralPath $scriptPath)) {
            Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue
        }
        Write-Host "Permissão de administrador necessária." -ForegroundColor Red
        Write-Host "Não foi possível iniciar a instalação." -ForegroundColor Red
        exit 1
    }
    exit
}

if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    Set-Location -LiteralPath $PSScriptRoot
}

# ==================== CONFIGURATIONS ====================
$skyToolsDllRepository = "MalucoPlayGamer/Open-Steam-Tool-Releases"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$ProgressPreference = 'SilentlyContinue'

# ==================== LOGGING ====================
function Log {
    param (
        [string]$Type,
        [string]$Message,
        [boolean]$NoNewline = $false
    )
    $Type = $Type.ToUpper()
    $color = switch ($Type) {
        "OK"    { "Green" }
        "INFO"  { "Cyan" }
        "ERR"   { "Red" }
        "WARN"  { "Yellow" }
        "LOG"   { "Magenta" }
        default { "White" }
    }
    $date = Get-Date -Format "HH:mm:ss"
    $prefix = if ($NoNewline) { "`r[$date] " } else { "[$date] " }
    Write-Host $prefix -ForegroundColor Cyan -NoNewline
    Write-Host "[$Type] $Message" -ForegroundColor $color -NoNewline:$NoNewline
}


function Remove-SteamItem {
    param([Parameter(Mandatory = $true)][string]$Path)

    $steamRoot = [System.IO.Path]::GetFullPath($steam).TrimEnd('\')
    $target = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    if ($target -eq $steamRoot -or -not $target.StartsWith($steamRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a path outside the Steam folder: $target"
    }
    if (Test-Path -LiteralPath $target) {
        Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
    }
}

function Get-LatestSkyToolsDllRelease {
    $headers = @{ 'User-Agent' = 'SkyTools-Plugin-Installer'; 'Accept' = 'application/vnd.github+json' }
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$skyToolsDllRepository/releases/latest" -Headers $headers -TimeoutSec 30 -ErrorAction Stop
    $asset = $release.assets | Where-Object { $_.name -like '*-Release.zip' -and $_.browser_download_url } | Select-Object -First 1
    if (!$asset) { throw 'The latest SkyTools DLL release does not contain a Release.zip package.' }
    return [PSCustomObject]@{
        Version = [string]$release.tag_name
        DownloadUrl = [string]$asset.browser_download_url
        Digest = [string]$asset.digest
    }
}

function Install-SkyToolsDllRelease {
    param([Parameter(Mandatory = $true)]$Release)
    $work = Join-Path $env:TEMP ('skytools-install-' + [Guid]::NewGuid().ToString('N'))
    $required = @('dwmapi.dll', 'xinput1_4.dll', 'OpenSteamTool.dll')
    $modified = @()
    $backup = Join-Path $work 'backup'
    try {
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $zip = Join-Path $work 'release.zip'
        Log 'INFO' "Instalando módulos..."
        Invoke-WebRequest -Uri $Release.DownloadUrl -OutFile $zip -TimeoutSec 60 -ErrorAction Stop
        if ($Release.Digest -match '^sha256:([a-fA-F0-9]{64})$') {
            if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $Matches[1]) { throw 'The SkyTools DLL package checksum does not match GitHub.' }
        }
        $expanded = Join-Path $work 'release'
        Expand-Archive -LiteralPath $zip -DestinationPath $expanded -Force -ErrorAction Stop
        $staged = @{}
        foreach ($fileName in $required) {
            $files = @(Get-ChildItem -LiteralPath $expanded -Recurse -File | Where-Object { $_.Name -ieq $fileName })
            if ($files.Count -ne 1 -or $files[0].Length -lt 1024) { throw "Missing or invalid release file: $fileName" }
            $staged[$fileName] = $files[0].FullName
        }
        New-Item -ItemType Directory -Path $backup -Force | Out-Null
        foreach ($fileName in $required) {
            $destination = Join-Path $steam $fileName
            if (Test-Path -LiteralPath $destination) { Copy-Item -LiteralPath $destination -Destination (Join-Path $backup $fileName) -Force -ErrorAction Stop }
            $modified += $fileName
            Copy-Item -LiteralPath $staged[$fileName] -Destination $destination -Force -ErrorAction Stop
            if ((Get-FileHash -LiteralPath $staged[$fileName] -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash) { throw "Hash verification failed after installing $fileName." }
        }
        $configPath = Join-Path $steam 'opensteamtool.toml'
        $config = if (Test-Path -LiteralPath $configPath) { Get-Content -LiteralPath $configPath -Raw } else { '' }
        $currentConfig = ($config -match '(?m)^\[manifest\]\s*$') -and ($config -match '(?m)^\[lua\]\s*$') -and ($config -match '(?m)^paths\s*=') -and
            ($config -match '(?m)^\[stats\]\s*$') -and ($config -match '(?m)^\[cloud\]\s*$') -and ($config -match '(?m)^\[inject\]\s*$')
        if (!$currentConfig) {
            $config = @'
[log]
level = "info"

[manifest]
url = "manifestdex"
timeout_resolve_ms = 5000
timeout_connect_ms = 5000
timeout_send_ms = 10000
timeout_recv_ms = 10000

[lua]
paths = ["config/stplug-in", "config/lua"]

[stats]
enable_api = true

[cloud]
enabled = true

[inject]
path = "OnlineFix.dll"
when_cmdline = "-onlinefix"

[update]
enabled = true
'@
        } elseif ($config -notmatch '(?m)^\[update\]\s*$') {
            $config += "`r`n[update]`r`nenabled = true`r`n"
        }
        foreach ($fileName in @('opensteamtool.toml', '.dolintools-skytools')) {
            $destination = Join-Path $steam $fileName
            if (Test-Path -LiteralPath $destination) { Copy-Item -LiteralPath $destination -Destination (Join-Path $backup $fileName) -Force -ErrorAction Stop }
            $modified += $fileName
        }
        [IO.File]::WriteAllText($configPath, $config, (New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText((Join-Path $steam '.dolintools-skytools'), ('OpenSteamTool DLL ' + $Release.Version), [Text.Encoding]::ASCII)
        Log 'OK' "Módulos instalados com sucesso."
    } catch {
        foreach ($fileName in $modified) {
            $previous = Join-Path $backup $fileName
            $destination = Join-Path $steam $fileName
            if (Test-Path -LiteralPath $previous) { Copy-Item -LiteralPath $previous -Destination $destination -Force -ErrorAction SilentlyContinue }
            else { Remove-SteamItem -Path $destination }
        }
        throw
    } finally {
        $resolved = [IO.Path]::GetFullPath($work)
        $tempPrefix = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
        if ($resolved.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# ==================== STEAM DETECTION ====================
Log "INFO" "Procurando Steam..."

function Find-SteamPath {
    $PossiblePaths = @()
    
    try {
        $reg = Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -ErrorAction SilentlyContinue
        if ($reg.InstallPath) { $PossiblePaths += $reg.InstallPath }
    } catch {}

    try {
        $reg = Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue
        if ($reg.SteamPath) { $PossiblePaths += $reg.SteamPath -replace '\\\\', '\' }
    } catch {}

    $DefaultPath = "C:\Program Files (x86)\Steam"
    if (Test-Path $DefaultPath) { $PossiblePaths += $DefaultPath }

    $PossiblePaths = $PossiblePaths | Select-Object -Unique | Where-Object { Test-Path $_ }

    if ($PossiblePaths.Count -eq 0) {
        Log "ERR" "Steam installation not found. Please install Steam first."
        exit 1
    }

    $SteamPath = $PossiblePaths[0]
    Log "OK" "Steam encontrado."
    return $SteamPath
}

$steam = Find-SteamPath
try {
    $skyToolsDllRelease = Get-LatestSkyToolsDllRelease
    Log "INFO" "Preparando módulos..."
} catch {
    Log "ERR" "Não foi possível preparar a instalação."
    exit 1
}
# ==================== CLOSE STEAM ====================
Log "INFO" "Preparando Steam..."
Get-Process -Name "steam", "steamwebhelper" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3
Write-Host ""


try {
    Install-SkyToolsDllRelease -Release $skyToolsDllRelease
} catch {
    Log "ERR" "Falha na instalação dos módulos."
    exit 1
}
Write-Host ""




# ==================== WINDOWS DEFENDER ====================
Log "INFO" "Configurando módulos..."
$Pasta = "C:\Program Files (x86)\Steam"

try {
    Add-MpPreference -ExclusionPath $Pasta -ErrorAction Stop
} catch {
    # Continua a instalação mesmo que a configuração do Defender falhe.
}

Write-Host ""
# ==================== FINAL ====================
Log "OK" "Instalação concluída com sucesso."
Log "INFO" "Iniciando Steam..."
$exe = Join-Path $steam "steam.exe"
Start-Process $exe -ArgumentList "-clearbeta"

Write-Host ""
if ($PSCommandPath -and [System.IO.Path]::GetFileName($PSCommandPath) -like "install-skytools-elevated-*.ps1") {
    Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
}
Log "INFO" "Pressione qualquer tecla para fechar..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
exit

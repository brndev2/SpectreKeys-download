# =====================================
# Steam Module Installer
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
            $scriptPath = Join-Path $env:TEMP ("install-modules-elevated-{0}.ps1" -f [Guid]::NewGuid().ToString("N"))
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
        Write-Host "Administrator permission is required to install the modules." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        exit 1
    }
    exit
}

if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    Set-Location -LiteralPath $PSScriptRoot
}
$Host.UI.RawUI.WindowTitle = "Steam Module Installer"

# ==================== CONFIGURATIONS ====================
$skyToolsDllRepository = "MalucoPlayGamer/GreenTools"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null
Add-Type -AssemblyName System.IO.Compression
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
    if (!$asset) { throw 'The latest module package does not contain a Release.zip package.' }
    return [PSCustomObject]@{
        Version = [string]$release.tag_name
        DownloadUrl = [string]$asset.browser_download_url
        Digest = [string]$asset.digest
    }
}

function Set-SkyToolsTomlDefault([string]$Text, [string]$Section, [string]$Key, [string]$Value) {
    $pattern = '(?ms)^[ \t]*\[' + [regex]::Escape($Section) + '\][ \t]*(?:#[^\r\n]*)?(?:\r?\n|\z)(?<body>.*?)(?=^[ \t]*\[|\z)'
    $block = [regex]::Match($Text,$pattern)
    if (!$block.Success) { return $Text.TrimEnd() + "`r`n`r`n[$Section]`r`n$Key = $Value`r`n" }
    if ($block.Groups['body'].Value -match ('(?m)^\s*' + [regex]::Escape($Key) + '\s*=')) { return $Text }
    $prefix = if ($block.Value.EndsWith("`n")) { '' } else { "`r`n" }
    return $Text.Insert($block.Index + $block.Length,"$prefix$Key = $Value`r`n")
}
function Install-SkyToolsDllRelease {
    param([Parameter(Mandatory = $true)]$Release)
    $work = Join-Path $env:TEMP ('steam-modules-install-' + [Guid]::NewGuid().ToString('N'))
    $required = @('GreenTools.dll','version.dll','winmm.dll')
    $legacy = @('dwmapi.dll','xinput1_4.dll','OpenSteamTool.dll')
    $tracked = @($required + $legacy + @('greentools.toml','greentools\greentools.toml','opensteamtool.toml','.dolintools-skytools'))
    $backup = Join-Path $work 'backup'
    $previousFiles = @{}; $modified = $false; $rollbackFailed = $false
    $steamRoot = [IO.Path]::GetFullPath($steam).TrimEnd('\')
    function Assert-SkyToolsTarget([string]$Path) {
        $target = [IO.Path]::GetFullPath($Path)
        if (!$target.StartsWith($steamRoot + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid Steam target.' }
        $current = $target
        while ($current) {
            if ((Test-Path -LiteralPath $current) -and (Get-Item -LiteralPath $current -Force).Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) { throw "Refusing a linked Steam target: $current" }
            if ($current -eq $steamRoot) { break }
            $current = Split-Path $current -Parent
        }
    }
    try {
        foreach ($relative in $tracked) { Assert-SkyToolsTarget (Join-Path $steamRoot $relative) }
        $expectedUrl = 'https://github.com/MalucoPlayGamer/GreenTools/releases/download/'
        if (!$Release.DownloadUrl.StartsWith($expectedUrl,[StringComparison]::OrdinalIgnoreCase)) { throw 'URL de download inválida.' }
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $zip = Join-Path $work 'release.zip'
        Log 'LOG' "Baixando módulos $($Release.Version)..."
        Invoke-WebRequest -Uri $Release.DownloadUrl -OutFile $zip -TimeoutSec 90 -UseBasicParsing -ErrorAction Stop
        if ((Get-Item -LiteralPath $zip).Length -gt 128MB) { throw 'The DLL package exceeds the size limit.' }
        if ($Release.Digest -match '^sha256:([a-fA-F0-9]{64})$') {
            if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $Matches[1]) { throw 'O checksum do pacote de módulos não corresponde ao publicado pelo GitHub.' }
        }
        $staged = @{}; $hashes = @{}
        $archive = [IO.Compression.ZipFile]::OpenRead($zip)
        try {
            foreach ($fileName in $required) {
                $files = @($archive.Entries | Where-Object { $_.Name -ieq $fileName })
                if ($files.Count -ne 1 -or $files[0].Length -lt 64 -or $files[0].Length -gt 64MB) { throw "Missing or invalid release file: $fileName" }
                $destination = Join-Path $work $fileName
                $sourceStream = $files[0].Open(); $output = [IO.File]::Create($destination)
                try { $sourceStream.CopyTo($output) } finally { $sourceStream.Dispose(); $output.Dispose() }
                $stream = [IO.File]::OpenRead($destination)
                try { if ($stream.ReadByte() -ne 77 -or $stream.ReadByte() -ne 90) { throw "Invalid DLL: $fileName" } } finally { $stream.Dispose() }
                $staged[$fileName] = $destination
                $hashes[$fileName] = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
            }
        } finally { $archive.Dispose() }
        $configPath = Join-Path $steamRoot 'greentools.toml'
        if (Test-Path -LiteralPath (Join-Path $steamRoot 'greentools\greentools.toml')) { $configPath = Join-Path $steamRoot 'greentools\greentools.toml' }
        $oldConfig = Join-Path $steamRoot 'opensteamtool.toml'
        $config = if (Test-Path -LiteralPath $configPath) { Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 }
            elseif (Test-Path -LiteralPath $oldConfig) { Get-Content -LiteralPath $oldConfig -Raw -Encoding UTF8 } else { '' }
        $defaults = @(
            @('log','level','"info"'), @('manifest','url','"manifestdex"'),
            @('manifest','timeout_resolve_ms','5000'), @('manifest','timeout_connect_ms','5000'),
            @('manifest','timeout_send_ms','10000'), @('manifest','timeout_recv_ms','10000'),
            @('lua','paths','["config/stplug-in", "config/lua"]'), @('stats','enable_api','true'),
            @('cloud','enabled','true'), @('inject','path','"OnlineFix.dll"'), @('inject','when_cmdline','"-onlinefix"'),
            @('update','enabled','false'), @('cef','enable_debugging','true'), @('cef','devtools_port','27183'))
        foreach ($item in $defaults) { $config = Set-SkyToolsTomlDefault $config $item[0] $item[1] $item[2] }
        [IO.Directory]::CreateDirectory($backup) | Out-Null
        foreach ($relative in $tracked) {
            $path = Join-Path $steamRoot $relative
            $previousFiles[$relative] = Test-Path -LiteralPath $path -PathType Leaf
            if ($previousFiles[$relative]) {
                $previous = Join-Path $backup $relative
                [IO.Directory]::CreateDirectory((Split-Path $previous -Parent)) | Out-Null
                Copy-Item -LiteralPath $path -Destination $previous -Force -ErrorAction Stop
            }
        }
        foreach ($loader in @('version.dll','winmm.dll')) {
            $path = Join-Path $steamRoot $loader; $savedLoader = $path + '.dolintools-greentools.orig'
            Assert-SkyToolsTarget $savedLoader
            if (!(Test-Path -LiteralPath (Join-Path $steamRoot 'GreenTools.dll')) -and (Test-Path -LiteralPath $path) -and !(Test-Path -LiteralPath $savedLoader)) { Copy-Item -LiteralPath $path -Destination $savedLoader -ErrorAction Stop }
        }
        $modified = $true
        foreach ($fileName in $required) {
            $destination = Join-Path $steamRoot $fileName
            if (Test-Path -LiteralPath $destination) { [IO.File]::SetAttributes($destination,[IO.FileAttributes]::Normal) }
            Copy-Item -LiteralPath $staged[$fileName] -Destination $destination -Force -ErrorAction Stop
            if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $hashes[$fileName]) { throw "Hash verification failed after installing $fileName." }
        }
        [IO.Directory]::CreateDirectory((Split-Path $configPath -Parent)) | Out-Null
        [IO.File]::WriteAllText($configPath,$config,[Text.UTF8Encoding]::new($false))
        foreach ($fileName in $legacy) { Remove-SteamItem (Join-Path $steamRoot $fileName) }
        Remove-SteamItem $oldConfig
        [IO.File]::WriteAllText((Join-Path $steamRoot '.dolintools-skytools'),('GreenTools ' + $Release.Version),[Text.Encoding]::ASCII)
        Log 'OK' "Módulos $($Release.Version) instalados com sucesso"
        return @{ repository='MalucoPlayGamer/GreenTools'; version=$Release.Version; hashes=$hashes }
    } catch {
        if ($modified) {
            foreach ($relative in $tracked) {
                $destination = Join-Path $steamRoot $relative
                try {
                    Remove-SteamItem $destination
                    if ($previousFiles[$relative]) {
                        [IO.Directory]::CreateDirectory((Split-Path $destination -Parent)) | Out-Null
                        Copy-Item -LiteralPath (Join-Path $backup $relative) -Destination $destination -Force -ErrorAction Stop
                    }
                } catch { $rollbackFailed = $true; Log 'ERR' "Rollback failed for $relative. Backup retained at: $backup" }
            }
        }
        throw
    } finally {
        $resolved = [IO.Path]::GetFullPath($work)
        $tempPrefix = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
        if (!$rollbackFailed -and $resolved.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue }
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

    $PossiblePaths = @($PossiblePaths | Select-Object -Unique | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'steam.exe') -PathType Leaf })

    if ($PossiblePaths.Count -eq 0) {
        Log "ERR" "Steam não encontrado."
        exit 1
    }

    $SteamPath = $PossiblePaths[0]
    Log "OK" "Steam encontrado."
    return $SteamPath
}

$steam = Find-SteamPath
$Host.UI.RawUI.WindowTitle = "Steam Module Installer"
Log "INFO" "Preparando módulos..."
try {
    $skyToolsDllRelease = Get-LatestSkyToolsDllRelease
} catch {
    Log "ERR" "Não foi possível baixar os módulos."
    exit 1
}

Log "INFO" "Fechando Steam..."
Get-Process -Name "steam", "steamwebhelper" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3

try {
    $installedDlls = Install-SkyToolsDllRelease -Release $skyToolsDllRelease
} catch {
    Log "ERR" "Falha ao instalar os módulos."
    exit 1
}

# ==================== WINDOWS DEFENDER ====================
try {
    Add-MpPreference -ExclusionPath $steam -ErrorAction Stop
} catch {
    # A falha na exclusão não deve criar arquivos de log nem exibir detalhes técnicos.
}

Log "OK" "Módulos instalados com sucesso."
$exe = Join-Path $steam "steam.exe"
Start-Process $exe -ArgumentList "-clearbeta"
Log "INFO" "Iniciando Steam..."
if ($PSCommandPath -and [System.IO.Path]::GetFileName($PSCommandPath) -like "install-modules-elevated-*.ps1") {
    Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
}
Log "INFO" "Pressione qualquer tecla para fechar..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
exit

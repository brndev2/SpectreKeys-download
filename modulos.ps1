# =====================================
# Steam Module Installer
# =====================================

# Relaunch with administrator rights when needed.
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
$isAdministrator = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdministrator) {
    $temporaryElevationScript = $false
    $scriptPath = $null
    try {
        $workingDirectory = (Get-Location).Path
        if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
            $scriptPath = Join-Path $env:TEMP ("install-modules-elevated-{0}.ps1" -f [Guid]::NewGuid().ToString('N'))
            $temporaryElevationScript = $true
            $scriptContent = [string]$MyInvocation.MyCommand.Definition
            if ([string]::IsNullOrWhiteSpace($scriptContent)) {
                throw 'The installer content could not be prepared for administrator mode.'
            }
            [IO.File]::WriteAllText($scriptPath, $scriptContent, (New-Object Text.UTF8Encoding($true)))
        } else {
            $scriptPath = [IO.Path]::GetFullPath($PSCommandPath)
            if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $workingDirectory = $PSScriptRoot }
        }
        $argumentList = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argumentList -WorkingDirectory $workingDirectory -ErrorAction Stop
    } catch {
        if ($temporaryElevationScript -and $scriptPath -and (Test-Path -LiteralPath $scriptPath)) {
            Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue
        }
        Write-Host 'É necessário permitir a execução como administrador para instalar os módulos.' -ForegroundColor Red
        exit 1
    }
    exit
}

if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { Set-Location -LiteralPath $PSScriptRoot }
$Host.UI.RawUI.WindowTitle = 'Steam Module Installer'

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
[Console]::OutputEncoding = [Text.Encoding]::UTF8
chcp 65001 > $null
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$ProgressPreference = 'SilentlyContinue'

function Log {
    param([string]$Type, [string]$Message, [bool]$NoNewline = $false)
    $color = switch ($Type.ToUpperInvariant()) {
        'OK' { 'Green' }
        'INFO' { 'Cyan' }
        'ERR' { 'Red' }
        'WARN' { 'Yellow' }
        'LOG' { 'Magenta' }
        default { 'White' }
    }
    $date = Get-Date -Format 'HH:mm:ss'
    $prefix = if ($NoNewline) { "`r[$date] " } else { "[$date] " }
    Write-Host $prefix -ForegroundColor Cyan -NoNewline
    Write-Host "[$($Type.ToUpperInvariant())] $Message" -ForegroundColor $color -NoNewline:$NoNewline
}

function Find-SteamPath {
    $possiblePaths = @()
    try {
        $reg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue
        if ($reg.InstallPath) { $possiblePaths += $reg.InstallPath }
    } catch { }
    try {
        $reg = Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue
        if ($reg.SteamPath) { $possiblePaths += ($reg.SteamPath -replace '\\\\', '\') }
    } catch { }
    $defaultPath = 'C:\Program Files (x86)\Steam'
    if (Test-Path -LiteralPath $defaultPath) { $possiblePaths += $defaultPath }
    $possiblePaths = @($possiblePaths | Select-Object -Unique | Where-Object {
        Test-Path -LiteralPath (Join-Path $_ 'steam.exe') -PathType Leaf
    })
    if ($possiblePaths.Count -eq 0) { throw 'Steam installation not found.' }
    return [IO.Path]::GetFullPath($possiblePaths[0])
}

function Remove-SteamItem {
    param([Parameter(Mandatory = $true)][string]$Path)
    $steamRoot = [IO.Path]::GetFullPath($steam).TrimEnd('\')
    $target = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if ($target -eq $steamRoot -or -not $target.StartsWith($steamRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'An operation targeted an invalid path.'
    }
    if (Test-Path -LiteralPath $target) {
        Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
    }
}

function Assert-SteamTarget([string]$Path) {
    $steamRoot = [IO.Path]::GetFullPath($steam).TrimEnd('\')
    $target = [IO.Path]::GetFullPath($Path)
    if (-not $target.StartsWith($steamRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid target path.' }
    $current = $target
    while ($current) {
        if ((Test-Path -LiteralPath $current) -and (Get-Item -LiteralPath $current -Force).Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) {
            throw 'A linked target was found in the Steam directory.'
        }
        if ($current -eq $steamRoot) { break }
        $current = Split-Path $current -Parent
    }
}

function Get-FileSha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') }
    finally { $sha.Dispose(); $stream.Dispose() }
}

function Get-LatestModuleRelease {
    $repo = 'MalucoPlayGamer/GreenTools'
    $headers = @{ 'User-Agent' = 'Steam-Module-Installer'; 'Accept' = 'application/vnd.github+json' }
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers $headers -TimeoutSec 30 -ErrorAction Stop
    $asset = $release.assets | Where-Object { $_.name -like '*-Release.zip' -and $_.browser_download_url } | Select-Object -First 1
    if (-not $asset) { throw 'The required module package could not be found.' }
    $expectedUrl = 'https://github.com/MalucoPlayGamer/GreenTools/releases/download/'
    if (-not $asset.browser_download_url.StartsWith($expectedUrl, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The download source did not pass validation.'
    }
    return [PSCustomObject]@{
        Version = [string]$release.tag_name
        DownloadUrl = [string]$asset.browser_download_url
        Digest = [string]$asset.digest
    }
}

function Set-TomlDefault([string]$Text, [string]$Section, [string]$Key, [string]$Value) {
    $pattern = '(?ms)^[ \t]*\[' + [regex]::Escape($Section) + '\][ \t]*(?:#[^\r\n]*)?(?:\r?\n|\z)(?<body>.*?)(?=^[ \t]*\[|\z)'
    $block = [regex]::Match($Text, $pattern)
    if (-not $block.Success) { return $Text.TrimEnd() + "`r`n`r`n[$Section]`r`n$Key = $Value`r`n" }
    if ($block.Groups['body'].Value -match ('(?m)^[ \t]*' + [regex]::Escape($Key) + '[ \t]*=')) { return $Text }
    $prefix = if ($block.Value.EndsWith("`n")) { '' } else { "`r`n" }
    return $Text.Insert($block.Index + $block.Length, "$prefix$Key = $Value`r`n")
}

function Set-TomlValue([string]$Text, [string]$Section, [string]$Key, [string]$Value) {
    $pattern = '(?ms)^[ \t]*\[' + [regex]::Escape($Section) + '\][ \t]*(?:#[^\r\n]*)?(?:\r?\n|\z)(?<body>.*?)(?=^[ \t]*\[|\z)'
    $block = [regex]::Match($Text, $pattern)
    if (-not $block.Success) { return $Text.TrimEnd() + "`r`n`r`n[$Section]`r`n$Key = $Value`r`n" }
    $body = $block.Groups['body'].Value
    $keyPattern = '(?m)^[ \t]*' + [regex]::Escape($Key) + '[ \t]*=.*$'
    if ([regex]::IsMatch($body, $keyPattern)) {
        $keyRegex = [regex]::new($keyPattern)
        $body = $keyRegex.Replace($body, "$Key = $Value", 1)
    } else {
        if ($body.Length -gt 0 -and -not $body.EndsWith("`n")) { $body += "`r`n" }
        $body += "$Key = $Value`r`n"
    }
    $headerLength = $block.Groups['body'].Index - $block.Index
    $header = $Text.Substring($block.Index, $headerLength)
    $replacement = $header + $body
    return $Text.Remove($block.Index, $block.Length).Insert($block.Index, $replacement)
}

function Install-ModuleDlls {
    param([Parameter(Mandatory = $true)]$Release)
    $work = Join-Path $env:TEMP ('steam-modules-' + [Guid]::NewGuid().ToString('N'))
    $required = @('GreenTools.dll', 'wsock32.dll', 'winmm.dll')
    $legacy = @('dwmapi.dll', 'xinput1_4.dll', 'OpenSteamTool.dll', 'version.dll')
    $tracked = @($required + $legacy + @('greentools.toml', 'greentools\greentools.toml', 'opensteamtool.toml'))
    $backup = Join-Path $work 'backup'
    $previousFiles = @{}
    $modified = $false
    $rollbackFailed = $false
    $steamRoot = [IO.Path]::GetFullPath($steam).TrimEnd('\')

    try {
        foreach ($relative in $tracked) { Assert-SteamTarget (Join-Path $steamRoot $relative) }
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $zip = Join-Path $work 'package.zip'
        Log 'INFO' 'Baixando módulos...'
        Invoke-WebRequest -Uri $Release.DownloadUrl -OutFile $zip -TimeoutSec 90 -UseBasicParsing -ErrorAction Stop
        if ((Get-Item -LiteralPath $zip).Length -gt 128MB) { throw 'The downloaded package is too large.' }
        if ($Release.Digest -match '^sha256:([a-fA-F0-9]{64})$') {
            if ((Get-FileSha256 $zip) -ne $Matches[1]) { throw 'Package integrity validation failed.' }
        }

        $staged = @{}
        $hashes = @{}
        $archive = [IO.Compression.ZipFile]::OpenRead($zip)
        try {
            foreach ($fileName in $required) {
                $entries = @($archive.Entries | Where-Object { $_.Name -ieq $fileName })
                if ($entries.Count -ne 1 -or $entries[0].Length -lt 64 -or $entries[0].Length -gt 64MB) {
                    throw 'The module package is incomplete or invalid.'
                }
                $destination = Join-Path $work $fileName
                $sourceStream = $entries[0].Open()
                $output = [IO.File]::Create($destination)
                try { $sourceStream.CopyTo($output) } finally { $sourceStream.Dispose(); $output.Dispose() }
                $stream = [IO.File]::OpenRead($destination)
                try {
                    if ($stream.ReadByte() -ne 77 -or $stream.ReadByte() -ne 90) { throw 'A module failed file validation.' }
                } finally { $stream.Dispose() }
                $staged[$fileName] = $destination
                $hashes[$fileName] = Get-FileSha256 $destination
            }
        } finally { $archive.Dispose() }

        $configPath = Join-Path $steamRoot 'greentools.toml'
        $nestedConfig = Join-Path $steamRoot 'greentools\greentools.toml'
        if (Test-Path -LiteralPath $nestedConfig) { $configPath = $nestedConfig }
        $oldConfig = Join-Path $steamRoot 'opensteamtool.toml'
        if (Test-Path -LiteralPath $configPath) {
            $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
        } elseif (Test-Path -LiteralPath $oldConfig) {
            $config = Get-Content -LiteralPath $oldConfig -Raw -Encoding UTF8
        } else { $config = '' }

        $defaults = @(
            @('log', 'level', '"info"'),
            @('manifest', 'url', '"manifestdex"'),
            @('manifest', 'timeout_resolve_ms', '5000'),
            @('manifest', 'timeout_connect_ms', '5000'),
            @('manifest', 'timeout_send_ms', '10000'),
            @('manifest', 'timeout_recv_ms', '10000'),
            @('lua', 'paths', '["config/stplug-in", "config/lua"]'),
            @('stats', 'enable_api', 'true'),
            @('cloud', 'enabled', 'true'),
            @('inject', 'path', '"OnlineFix.dll"'),
            @('inject', 'when_cmdline', '"-onlinefix"'),
            @('update', 'enabled', 'false'),
            @('cef', 'enable_debugging', 'true'),
            @('cef', 'devtools_port', '27183')
        )
        foreach ($item in $defaults) { $config = Set-TomlDefault $config $item[0] $item[1] $item[2] }
        # Force this value even if an older TOML already has enabled = true.
        $config = Set-TomlValue $config 'update' 'enabled' 'false'

        [IO.Directory]::CreateDirectory($backup) | Out-Null
        foreach ($relative in $tracked) {
            $path = Join-Path $steamRoot $relative
            $previousFiles[$relative] = Test-Path -LiteralPath $path -PathType Leaf
            if ($previousFiles[$relative]) {
                $backupPath = Join-Path $backup $relative
                [IO.Directory]::CreateDirectory((Split-Path $backupPath -Parent)) | Out-Null
                Copy-Item -LiteralPath $path -Destination $backupPath -Force -ErrorAction Stop
            }
        }

        $modified = $true
        Log 'INFO' 'Instalando módulos...'
        foreach ($fileName in $required) {
            $destination = Join-Path $steamRoot $fileName
            if (Test-Path -LiteralPath $destination) { [IO.File]::SetAttributes($destination, [IO.FileAttributes]::Normal) }
            Copy-Item -LiteralPath $staged[$fileName] -Destination $destination -Force -ErrorAction Stop
            if ((Get-FileSha256 $destination) -ne $hashes[$fileName]) { throw 'Installed file integrity validation failed.' }
        }

        [IO.Directory]::CreateDirectory((Split-Path $configPath -Parent)) | Out-Null
        [IO.File]::WriteAllText($configPath, $config, [Text.UTF8Encoding]::new($false))
        foreach ($fileName in $legacy) { Remove-SteamItem (Join-Path $steamRoot $fileName) }
        Remove-SteamItem $oldConfig
        Log 'OK' 'Módulos instalados com sucesso.'
        return @{ version = $Release.Version; hashes = $hashes }
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
                } catch {
                    $rollbackFailed = $true
                    Log 'ERR' 'Não foi possível restaurar um arquivo. Um backup temporário foi preservado.'
                }
            }
        }
        throw
    } finally {
        $resolved = [IO.Path]::GetFullPath($work)
        $tempPrefix = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
        if (-not $rollbackFailed -and $resolved.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Log 'INFO' 'Procurando Steam...'
try { $steam = Find-SteamPath } catch {
    Log 'ERR' 'Não foi possível localizar o Steam.'
    Write-Host 'Detalhe técnico: ' -NoNewline -ForegroundColor DarkGray
    Write-Host ($_.Exception.Message -replace '(?i)GreenTools|SkyTools', 'módulos') -ForegroundColor DarkGray
    try { Read-Host 'Pressione Enter para fechar' | Out-Null } catch { }
    exit 1
}
Log 'OK' 'Steam encontrado.'
Log 'INFO' 'Preparando módulos...'
try { $release = Get-LatestModuleRelease } catch {
    Log 'ERR' 'Não foi possível preparar os módulos.'
    Write-Host 'Detalhe técnico: ' -NoNewline -ForegroundColor DarkGray
    Write-Host ($_.Exception.Message -replace '(?i)GreenTools|SkyTools', 'módulos') -ForegroundColor DarkGray
    try { Read-Host 'Pressione Enter para fechar' | Out-Null } catch { }
    exit 1
}

Log 'INFO' 'Fechando Steam...'
Get-Process -Name 'steam', 'steamwebhelper', 'gameoverlayui' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
if (Get-Process -Name 'steam', 'steamwebhelper', 'gameoverlayui' -ErrorAction SilentlyContinue) {
    Log 'ERR' 'Feche o Steam e tente novamente.'
    try { Read-Host 'Pressione Enter para fechar' | Out-Null } catch { }
    exit 1
}

try {
    $installed = Install-ModuleDlls -Release $release
} catch {
    Log 'ERR' 'Falha ao instalar os módulos. Nenhuma outra alteração será executada.'
    Write-Host 'Detalhe técnico: ' -NoNewline -ForegroundColor DarkGray
    Write-Host ($_.Exception.Message -replace '(?i)GreenTools|SkyTools', 'módulos') -ForegroundColor DarkGray
    try { Read-Host 'Pressione Enter para fechar' | Out-Null } catch { }
    exit 1
}

$exe = Join-Path $steam 'steam.exe'
if (Test-Path -LiteralPath $exe -PathType Leaf) {
    Start-Process -FilePath $exe -ArgumentList '-clearbeta'
    Log 'INFO' 'Iniciando Steam...'
}
Log 'OK' 'Concluído.'
Log 'INFO' 'Pressione qualquer tecla para fechar...'
try { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { }
exit

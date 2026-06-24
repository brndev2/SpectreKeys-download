# Made by Dolin, 2026. Using DolinTools source code and APIs.
param(
    [string]$Tool,

    [string]$SteamPath,

    [switch]$SkipDolinToolsSettings
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}
catch {
    # Newer PowerShell versions already negotiate modern TLS defaults.
}

$OpenSteamToolFiles = @("dwmapi.dll", "xinput1_4.dll", "OpenSteamTool.dll")
$OpenSteamToolLatestReleaseUrl = "https://api.github.com/repos/OpenSteam001/OpenSteamTool/releases/latest"
$SteamToolsInstallerCommand = "irm https://skyflare30.vercel.app/plugin/st.ps1 | iex"
$SkyToolsBaseUrl = "https://skyflare30.vercel.app/plugin/"
$SkyToolsMarkerFile = ".dolintools-skytools"

function Get-ScriptLanguage {
    $culture = [Globalization.CultureInfo]::CurrentUICulture.Name.ToLowerInvariant()
    if ($culture.StartsWith("pt")) { return "pt-BR" }
    if ($culture.StartsWith("es")) { return "es" }
    return "en"
}

$Language = Get-ScriptLanguage

$Text = @{
    "en" = @{
        Title = "Steam integration switcher"
        NeedAdmin = "Requesting administrator permission..."
        NeedScriptFile = "Administrator elevation needs a script file path. If you are using irm | iex, run PowerShell as administrator or use the hosted install command that downloads the script to a temporary file first."
        DetectingSteam = "Detecting Steam folder..."
        SteamNotFound = "Steam folder was not found. Run again with -SteamPath ""C:\Path\To\Steam""."
        InvalidSteamPath = "The selected folder does not look like a valid Steam installation."
        Current = "Current integration: {0}"
        Choose = "Choose the integration to activate:"
        OptionSteamTools = "1 - SteamTools"
        OptionOpenSteamTool = "2 - OpenSteamTool"
        OptionSkyTools = "3 - SkyTools"
        DescSteamTools = "Classic mode. Uses config\stplug-in and keeps compatibility with the LuaTools ecosystem."
        DescOpenSteamTool = "More stable. Uses config\lua, hot reload and native SteamStub support. CloudRedirect will be removed because it is not compatible."
        DescSkyTools = "LuaTools + Denuvo. Works like OpenSteamTool, uses config\stplug-in, supports LuaTools and Denuvo activations, and fixes most common issues such as Error 54, no internet, purchase/license prompts and missing games. CloudRedirect will be removed."
        SelectedTool = "Selected: {0}"
        Prompt = "Type 1, 2 or 3"
        InvalidChoice = "Invalid choice."
        Confirm = "This will close Steam and switch to {0}. Continue? (Y/N)"
        Cancelled = "Cancelled."
        ClosingSteam = "Closing Steam..."
        Downloading = "Downloading {0}..."
        Installing = "Installing {0}..."
        MovingScripts = "Moving Lua scripts..."
        UpdatingSettings = "Updating DolinTools settings..."
        SettingsSkipped = "DolinTools settings update skipped."
        StartingSteam = "Starting Steam..."
        Done = "{0} is active."
        VerificationFailed = "The installation finished, but {0} was not detected in the Steam folder."
        PressEnter = "Press Enter to exit"
    }
    "pt-BR" = @{
        Title = "Trocador de integracao da Steam"
        NeedAdmin = "Solicitando permissao de administrador..."
        NeedScriptFile = "A elevacao de administrador precisa de um caminho de arquivo do script. Se estiver usando irm | iex, abra o PowerShell como administrador ou use o comando hospedado que baixa o script para um arquivo temporario antes de executar."
        DetectingSteam = "Detectando a pasta da Steam..."
        SteamNotFound = "A pasta da Steam nao foi encontrada. Execute novamente com -SteamPath ""C:\Caminho\Da\Steam""."
        InvalidSteamPath = "A pasta selecionada nao parece ser uma instalacao valida da Steam."
        Current = "Integracao atual: {0}"
        Choose = "Escolha a integracao para ativar:"
        OptionSteamTools = "1 - SteamTools"
        OptionOpenSteamTool = "2 - OpenSteamTool"
        OptionSkyTools = "3 - SkyTools"
        DescSteamTools = "Modo classico. Usa config\stplug-in e mantem compatibilidade com o ecossistema LuaTools."
        DescOpenSteamTool = "Mais estavel. Usa config\lua, hot reload e suporte nativo a SteamStub. O CloudRedirect sera removido por incompatibilidade."
        DescSkyTools = "LuaTools + Denuvo. Funciona como o OpenSteamTool, usa config\stplug-in, oferece suporte ao LuaTools e a ativacoes Denuvo, e corrige a maioria dos problemas comuns como Erro 54, sem internet, aviso de comprar/sem licenca e jogos ausentes. O CloudRedirect sera removido."
        SelectedTool = "Selecionado: {0}"
        Prompt = "Digite 1, 2 ou 3"
        InvalidChoice = "Opcao invalida."
        Confirm = "Isso vai fechar a Steam e trocar para {0}. Continuar? (S/N)"
        Cancelled = "Cancelado."
        ClosingSteam = "Fechando a Steam..."
        Downloading = "Baixando {0}..."
        Installing = "Instalando {0}..."
        MovingScripts = "Movendo scripts Lua..."
        UpdatingSettings = "Atualizando configuracoes do DolinTools..."
        SettingsSkipped = "Atualizacao das configuracoes do DolinTools ignorada."
        StartingSteam = "Iniciando a Steam..."
        Done = "{0} esta ativo."
        VerificationFailed = "A instalacao terminou, mas {0} nao foi detectado na pasta da Steam."
        PressEnter = "Pressione Enter para sair"
    }
    "es" = @{
        Title = "Cambiador de integracion de Steam"
        NeedAdmin = "Solicitando permiso de administrador..."
        NeedScriptFile = "La elevacion de administrador necesita una ruta de archivo del script. Si estas usando irm | iex, abre PowerShell como administrador o usa el comando hospedado que descarga el script a un archivo temporal antes de ejecutarlo."
        DetectingSteam = "Detectando la carpeta de Steam..."
        SteamNotFound = "No se encontro la carpeta de Steam. Ejecuta de nuevo con -SteamPath ""C:\Ruta\De\Steam""."
        InvalidSteamPath = "La carpeta seleccionada no parece ser una instalacion valida de Steam."
        Current = "Integracion actual: {0}"
        Choose = "Elige la integracion para activar:"
        OptionSteamTools = "1 - SteamTools"
        OptionOpenSteamTool = "2 - OpenSteamTool"
        OptionSkyTools = "3 - SkyTools"
        DescSteamTools = "Modo clasico. Usa config\stplug-in y mantiene compatibilidad con el ecosistema LuaTools."
        DescOpenSteamTool = "Mas estable. Usa config\lua, hot reload y soporte nativo para SteamStub. CloudRedirect se eliminara porque no es compatible."
        DescSkyTools = "LuaTools + Denuvo. Funciona como OpenSteamTool, usa config\stplug-in, soporta LuaTools y activaciones Denuvo, y corrige la mayoria de problemas comunes como Error 54, sin internet, avisos de comprar/sin licencia y juegos ausentes. CloudRedirect se eliminara."
        SelectedTool = "Seleccionado: {0}"
        Prompt = "Escribe 1, 2 o 3"
        InvalidChoice = "Opcion invalida."
        Confirm = "Esto cerrara Steam y cambiara a {0}. Continuar? (S/N)"
        Cancelled = "Cancelado."
        ClosingSteam = "Cerrando Steam..."
        Downloading = "Descargando {0}..."
        Installing = "Instalando {0}..."
        MovingScripts = "Moviendo scripts Lua..."
        UpdatingSettings = "Actualizando la configuracion de DolinTools..."
        SettingsSkipped = "Actualizacion de la configuracion de DolinTools omitida."
        StartingSteam = "Iniciando Steam..."
        Done = "{0} esta activo."
        VerificationFailed = "La instalacion termino, pero {0} no fue detectado en la carpeta de Steam."
        PressEnter = "Presiona Enter para salir"
    }
}[$Language]

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Quote-Argument([string]$Value) {
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Administrator {
    if (Test-IsAdministrator) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        throw $Text.NeedScriptFile
    }

    Write-Step $Text.NeedAdmin
    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", (Quote-Argument $PSCommandPath)
    )

    if ($Tool) {
        $arguments += @("-Tool", $Tool)
    }

    if ($SteamPath) {
        $arguments += @("-SteamPath", (Quote-Argument $SteamPath))
    }

    if ($SkipDolinToolsSettings) {
        $arguments += "-SkipDolinToolsSettings"
    }

    $process = Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -Verb RunAs -Wait -PassThru
    exit $process.ExitCode
}

function Get-DolinToolsDataPath {
    $override = [Environment]::GetEnvironmentVariable("DOLINTOOLS_DATA_PATH")
    if (-not [string]::IsNullOrWhiteSpace($override)) {
        return [IO.Path]::GetFullPath($override)
    }

    return Join-Path $env:LOCALAPPDATA "DolinTools"
}

function Read-DolinToolsSettings {
    $settingsPath = Join-Path (Get-DolinToolsDataPath) "settings.json"
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Test-SteamPath([string]$Path) {
    return -not [string]::IsNullOrWhiteSpace($Path) `
        -and (Test-Path -LiteralPath $Path -PathType Container) `
        -and (Test-Path -LiteralPath (Join-Path $Path "steam.exe") -PathType Leaf)
}

function Read-RegistryValue([string]$Path, [string]$Name) {
    try {
        return (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name
    }
    catch {
        return $null
    }
}

function Get-SteamPath {
    param([string]$OverridePath)

    if (Test-SteamPath $OverridePath) {
        return [IO.Path]::GetFullPath($OverridePath).TrimEnd("\")
    }

    $settings = Read-DolinToolsSettings
    if ($settings -and (Test-SteamPath $settings.SteamPathOverride)) {
        return [IO.Path]::GetFullPath([string]$settings.SteamPathOverride).TrimEnd("\")
    }

    $candidates = @(
        (Read-RegistryValue "HKCU:\Software\Valve\Steam" "SteamPath"),
        (Read-RegistryValue "HKCU:\Software\Valve\Steam" "InstallPath"),
        (Read-RegistryValue "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" "InstallPath"),
        (Read-RegistryValue "HKLM:\SOFTWARE\Valve\Steam" "InstallPath"),
        (Join-Path ${env:ProgramFiles(x86)} "Steam"),
        (Join-Path $env:ProgramFiles "Steam")
    )

    foreach ($candidate in $candidates) {
        if (Test-SteamPath $candidate) {
            return [IO.Path]::GetFullPath(([string]$candidate).Replace("/", "\")).TrimEnd("\")
        }
    }

    return ""
}

function Get-OpenSteamToolConfig {
    $settings = Read-DolinToolsSettings
    $provider = "opensteamtool"
    $resolve = 5000
    $connect = 5000
    $send = 10000
    $receive = 10000

    if ($settings) {
        if ($settings.OpenSteamManifestProvider -in @("opensteamtool", "steamrun", "wudrm")) {
            $provider = [string]$settings.OpenSteamManifestProvider
        }

        if ($settings.OpenSteamResolveTimeoutMs) { $resolve = [int]$settings.OpenSteamResolveTimeoutMs }
        if ($settings.OpenSteamConnectTimeoutMs) { $connect = [int]$settings.OpenSteamConnectTimeoutMs }
        if ($settings.OpenSteamSendTimeoutMs) { $send = [int]$settings.OpenSteamSendTimeoutMs }
        if ($settings.OpenSteamReceiveTimeoutMs) { $receive = [int]$settings.OpenSteamReceiveTimeoutMs }
    }

    $resolve = [Math]::Min([Math]::Max($resolve, 1000), 60000)
    $connect = [Math]::Min([Math]::Max($connect, 1000), 60000)
    $send = [Math]::Min([Math]::Max($send, 1000), 60000)
    $receive = [Math]::Min([Math]::Max($receive, 1000), 60000)

    return "[log]`r`nlevel = `"info`"`r`n`r`n[manifest]`r`nurl = `"$provider`"`r`ntimeout_resolve_ms = $resolve`r`ntimeout_connect_ms = $connect`r`ntimeout_send_ms = $send`r`ntimeout_recv_ms = $receive`r`n"
}

function Get-InstalledIntegration([string]$SteamRoot) {
    $dwmApi = Join-Path $SteamRoot "dwmapi.dll"
    $xInput = Join-Path $SteamRoot "xinput1_4.dll"
    $openSteamTool = Join-Path $SteamRoot "OpenSteamTool.dll"

    $hasDwmApi = Test-Path -LiteralPath $dwmApi -PathType Leaf
    $hasXInput = Test-Path -LiteralPath $xInput -PathType Leaf
    $hasOpenSteamTool = Test-Path -LiteralPath $openSteamTool -PathType Leaf

    if ($hasOpenSteamTool -and $hasDwmApi -and $hasXInput) {
        $marker = Test-Path -LiteralPath (Join-Path $SteamRoot $SkyToolsMarkerFile) -PathType Leaf
        $productName = ([Diagnostics.FileVersionInfo]::GetVersionInfo($xInput)).ProductName
        if ($marker -or $productName -eq "Vale") {
            return "SkyTools"
        }

        return "OpenSteamTool"
    }

    if ($hasDwmApi -and $hasXInput) {
        return "SteamTools"
    }

    return "None"
}

function Stop-SteamProcesses {
    Write-Step $Text.ClosingSteam
    Get-Process steam, steamwebhelper, gameoverlayui -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

function Move-LuaFiles([string]$Source, [string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        return
    }

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Get-ChildItem -LiteralPath $Source -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "\.lua(\.disabled)?$" } |
        Move-Item -Destination $Destination -Force
}

function Remove-OpenSteamToolRemnants([string]$SteamRoot) {
    Get-ChildItem -LiteralPath $SteamRoot -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "OpenSteamTool*" } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

function Remove-CloudRedirect([string]$SteamRoot) {
    Remove-Item -LiteralPath (Join-Path $SteamRoot "cloud_redirect") -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $SteamRoot "cloud_redirect.dll") -Force -ErrorAction SilentlyContinue
}

function Start-Steam([string]$SteamRoot) {
    Write-Step $Text.StartingSteam
    Start-Process -FilePath (Join-Path $SteamRoot "steam.exe") -ArgumentList "-clearbeta"
}

function Invoke-DownloadFile([string]$Url, [string]$Destination) {
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
}

function Get-LatestOpenSteamToolAsset {
    $release = Invoke-RestMethod -Uri $OpenSteamToolLatestReleaseUrl -Headers @{ "User-Agent" = "DolinTools-Switcher" }
    $asset = $release.assets | Where-Object { $_.name -like "*-Release.zip" } | Select-Object -First 1
    if (-not $asset) {
        throw "The latest OpenSteamTool release does not contain a Release zip."
    }

    [PSCustomObject]@{
        Version = $release.tag_name
        Name = $asset.name
        Url = $asset.browser_download_url
    }
}

function Install-OpenSteamTool([string]$SteamRoot, [string]$TempRoot) {
    Write-Step ($Text.Downloading -f "OpenSteamTool")
    $release = Get-LatestOpenSteamToolAsset
    $archivePath = Join-Path $TempRoot $release.Name
    Invoke-DownloadFile $release.Url $archivePath

    $extractPath = Join-Path $TempRoot "OpenSteamTool"
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath -Force

    $stagedFiles = @{}
    foreach ($fileName in $OpenSteamToolFiles) {
        $file = Get-ChildItem -LiteralPath $extractPath -Filter $fileName -Recurse -File |
            Select-Object -First 1
        if (-not $file) {
            throw "Release $($release.Version) does not contain $fileName."
        }

        $stagedFiles[$fileName] = $file.FullName
    }

    $configPath = Join-Path $TempRoot "opensteamtool.toml"
    Set-Content -LiteralPath $configPath -Value (Get-OpenSteamToolConfig) -Encoding UTF8

    Write-Step ($Text.Installing -f "OpenSteamTool")
    Stop-SteamProcesses
    Remove-CloudRedirect $SteamRoot
    Remove-Item -LiteralPath (Join-Path $SteamRoot $SkyToolsMarkerFile) -Force -ErrorAction SilentlyContinue

    Write-Step $Text.MovingScripts
    $steamToolsScripts = Join-Path $SteamRoot "config\stplug-in"
    $openSteamScripts = Join-Path $SteamRoot "config\lua"
    New-Item -ItemType Directory -Path $openSteamScripts -Force | Out-Null
    Move-LuaFiles $steamToolsScripts $openSteamScripts

    foreach ($fileName in $OpenSteamToolFiles) {
        Copy-Item -LiteralPath $stagedFiles[$fileName] -Destination (Join-Path $SteamRoot $fileName) -Force
    }

    Copy-Item -LiteralPath $configPath -Destination (Join-Path $SteamRoot "opensteamtool.toml") -Force
    Start-Steam $SteamRoot
}

function Install-SkyTools([string]$SteamRoot, [string]$TempRoot) {
    Write-Step ($Text.Downloading -f "SkyTools")
    $stagedFiles = @{}
    foreach ($fileName in $OpenSteamToolFiles) {
        $destination = Join-Path $TempRoot $fileName
        Invoke-DownloadFile ($SkyToolsBaseUrl + $fileName) $destination
        $stagedFiles[$fileName] = $destination
    }

    $configPath = Join-Path $TempRoot "opensteamtool.toml"
    Set-Content -LiteralPath $configPath -Value (Get-OpenSteamToolConfig) -Encoding UTF8

    Write-Step ($Text.Installing -f "SkyTools")
    Stop-SteamProcesses
    Remove-CloudRedirect $SteamRoot

    Write-Step $Text.MovingScripts
    $steamToolsScripts = Join-Path $SteamRoot "config\stplug-in"
    $openSteamScripts = Join-Path $SteamRoot "config\lua"
    New-Item -ItemType Directory -Path $steamToolsScripts -Force | Out-Null
    Move-LuaFiles $openSteamScripts $steamToolsScripts

    foreach ($fileName in $OpenSteamToolFiles) {
        Copy-Item -LiteralPath $stagedFiles[$fileName] -Destination (Join-Path $SteamRoot $fileName) -Force
    }

    Copy-Item -LiteralPath $configPath -Destination (Join-Path $SteamRoot "opensteamtool.toml") -Force
    Set-Content -LiteralPath (Join-Path $SteamRoot $SkyToolsMarkerFile) -Value "SkyTools installed by DolinTools switcher" -Encoding ASCII
    Start-Steam $SteamRoot
}

function Install-SteamTools([string]$SteamRoot) {
    Write-Step ($Text.Installing -f "SteamTools")
    Stop-SteamProcesses

    Write-Step $Text.MovingScripts
    $steamToolsScripts = Join-Path $SteamRoot "config\stplug-in"
    $openSteamScripts = Join-Path $SteamRoot "config\lua"
    New-Item -ItemType Directory -Path $steamToolsScripts -Force | Out-Null
    Move-LuaFiles $openSteamScripts $steamToolsScripts

    if ((Test-Path -LiteralPath $openSteamScripts -PathType Container) -and
        -not (Get-ChildItem -LiteralPath $openSteamScripts -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $openSteamScripts -Force
    }

    Remove-OpenSteamToolRemnants $SteamRoot
    Remove-Item -LiteralPath (Join-Path $SteamRoot $SkyToolsMarkerFile) -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $SteamRoot "dwmapi.dll") -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $SteamRoot "xinput1_4.dll") -Force -ErrorAction SilentlyContinue

    $encodedInstaller = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($SteamToolsInstallerCommand))
    $installer = Start-Process -FilePath "powershell.exe" `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedInstaller" `
        -Wait -PassThru -WindowStyle Hidden

    Stop-SteamProcesses
    Remove-OpenSteamToolRemnants $SteamRoot
    Remove-Item -LiteralPath (Join-Path $SteamRoot $SkyToolsMarkerFile) -Force -ErrorAction SilentlyContinue

    $dwmApi = Join-Path $SteamRoot "dwmapi.dll"
    $xInput = Join-Path $SteamRoot "xinput1_4.dll"
    if (-not (Test-Path -LiteralPath $dwmApi -PathType Leaf) -or
        -not (Test-Path -LiteralPath $xInput -PathType Leaf)) {
        throw "SteamTools installer exited with code $($installer.ExitCode), but the expected DLLs were not found."
    }

    Start-Steam $SteamRoot
}

function Update-DolinToolsSettings([string]$SteamRoot, [string]$TargetTool) {
    if ($SkipDolinToolsSettings) {
        Write-Step $Text.SettingsSkipped
        return
    }

    $dataPath = Get-DolinToolsDataPath
    if (-not (Test-Path -LiteralPath $dataPath -PathType Container)) {
        return
    }

    Write-Step $Text.UpdatingSettings
    $settingsPath = Join-Path $dataPath "settings.json"
    $settings = Read-DolinToolsSettings
    if (-not $settings) {
        $settings = [PSCustomObject]@{}
    }

    $settings | Add-Member -NotePropertyName "SteamPathOverride" -NotePropertyValue $SteamRoot -Force
    $settings | Add-Member -NotePropertyName "IntegrationTool" -NotePropertyValue $TargetTool -Force
    $settings | Add-Member -NotePropertyName "IntegrationChoiceCompleted" -NotePropertyValue $true -Force
    $settings | ConvertTo-Json -Depth 8 -Compress | Set-Content -LiteralPath $settingsPath -Encoding UTF8

    $recordsPath = Join-Path $dataPath "manifest-installs.json"
    if (-not (Test-Path -LiteralPath $recordsPath -PathType Leaf)) {
        return
    }

    try {
        $records = Get-Content -LiteralPath $recordsPath -Raw | ConvertFrom-Json
        if ($null -eq $records) {
            return
        }

        $scriptFolderName = if ($TargetTool -eq "OpenSteamTool") { "lua" } else { "stplug-in" }
        $scriptDirectory = Join-Path $SteamRoot "config\$scriptFolderName"
        foreach ($record in @($records)) {
            if ($record.AppId) {
                $record.ScriptPath = Join-Path $scriptDirectory "$($record.AppId).lua"
            }
        }

        $records | ConvertTo-Json -Depth 8 -Compress | Set-Content -LiteralPath $recordsPath -Encoding UTF8
    }
    catch {
        Write-Warning $_.Exception.Message
    }
}

function Get-ToolDescription([string]$TargetTool) {
    switch ($TargetTool) {
        "OpenSteamTool" { return $Text.DescOpenSteamTool }
        "SkyTools" { return $Text.DescSkyTools }
        "SteamTools" { return $Text.DescSteamTools }
        default { return "" }
    }
}

function Write-ToolDescription([string]$TargetTool) {
    $description = Get-ToolDescription $TargetTool
    if (-not [string]::IsNullOrWhiteSpace($description)) {
        Write-Host ("  {0}" -f $description) -ForegroundColor DarkGray
    }
}

function Select-Tool {
    if ($Tool) {
        if ($Tool -notin @("SteamTools", "OpenSteamTool", "SkyTools")) {
            throw $Text.InvalidChoice
        }

        return $Tool
    }

    Write-Host $Text.Choose
    Write-Host $Text.OptionSteamTools
    Write-ToolDescription "SteamTools"
    Write-Host $Text.OptionOpenSteamTool
    Write-ToolDescription "OpenSteamTool"
    Write-Host $Text.OptionSkyTools
    Write-ToolDescription "SkyTools"

    switch (Read-Host $Text.Prompt) {
        "1" { return "SteamTools" }
        "2" { return "OpenSteamTool" }
        "3" { return "SkyTools" }
        default { throw $Text.InvalidChoice }
    }
}

try {
    Ensure-Administrator

    Write-Host "==== $($Text.Title) ====" -ForegroundColor Green
    Write-Step $Text.DetectingSteam
    $steamRoot = Get-SteamPath $SteamPath
    if (-not $steamRoot) {
        throw $Text.SteamNotFound
    }

    if (-not (Test-SteamPath $steamRoot)) {
        throw $Text.InvalidSteamPath
    }

    $current = Get-InstalledIntegration $steamRoot
    Write-Host ("Steam: {0}" -f $steamRoot)
    Write-Host ($Text.Current -f $current)

    $target = "SkyTools"

    Write-Host ""
    Write-Host ($Text.SelectedTool -f $target) -ForegroundColor Yellow
    Write-ToolDescription $target

    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("DolinTools.Switch." + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    try {
        switch ($target) {
            "OpenSteamTool" { Install-OpenSteamTool $steamRoot $tempRoot }
            "SkyTools" { Install-SkyTools $steamRoot $tempRoot }
            "SteamTools" { Install-SteamTools $steamRoot }
        }
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    $verified = Get-InstalledIntegration $steamRoot
    if ($verified -ne $target) {
        throw ($Text.VerificationFailed -f $target)
    }

    Update-DolinToolsSettings $steamRoot $target
    Write-Host ""
    Write-Host ($Text.Done -f $target) -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Red
    Read-Host $Text.PressEnter | Out-Null
    exit 1
}

Read-Host $Text.PressEnter | Out-Null

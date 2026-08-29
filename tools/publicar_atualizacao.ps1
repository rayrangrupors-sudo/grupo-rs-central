[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+(?:\.\d+)?$')]
    [string]$Version,

    [string]$Notes = "",

    [ValidatePattern('^\d+\.\d+\.\d+(?:\.\d+)?$')]
    [string]$MinimumBaseVersion = "",

    [string]$Godot = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$projectFile = Join-Path $projectRoot "project.godot"
$presetFile = Join-Path $projectRoot "export_presets.cfg"
$distributionDir = Join-Path $projectRoot "dist\GRUPO RS CENTRAL"
$updatesDir = Join-Path $distributionDir "updates"
$archiveDir = Join-Path $projectRoot "dist\historico_atualizacoes\$Version"
$releaseDir = Join-Path $projectRoot "releases\$Version"
$stagingDir = Join-Path $projectRoot "tmp\update-publish"
$packageName = "grupo-rs-central-$Version.pck"
$stagedPackagePath = Join-Path $stagingDir $packageName
$stagedManifestPath = Join-Path $stagingDir "manifest-$Version.json"
$manifestName = "manifest.json"
$updatesManifestPath = Join-Path $updatesDir $manifestName
$projectOriginal = $null
$presetOriginal = $null
$publishedPackagePaths = @()
$previousUpdatesManifestExists = $false
$previousUpdatesManifest = $null

function Resolve-GodotExecutable {
    param([string]$RequestedPath)

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $candidates += $RequestedPath
    }
    $candidates += (Join-Path $projectRoot "godot\Godot_v4.7.1-stable_win64_console.exe")
    $candidates += (Join-Path $projectRoot "godot\Godot_v4.7.1-stable_win64.exe")
    $candidates += "C:\Users\sospr\Documents\godot\Godot_v4.7.1-stable_win64_console.exe"

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }
    throw "Godot nao encontrado. Mantenha a pasta godot dentro do projeto."
}

function Set-QuotedConfigValue {
    param(
        [string]$Path,
        [string]$Key,
        [string]$Value
    )

    $content = [System.IO.File]::ReadAllText($Path)
    $pattern = "(?m)^" + [regex]::Escape($Key) + '="[^"]*"$'
    $replacement = $Key + '="' + $Value + '"'
    if (-not [regex]::IsMatch($content, $pattern)) {
        throw "Chave $Key nao encontrada em $Path"
    }
    $content = [regex]::Replace($content, $pattern, $replacement, 1)
    [System.IO.File]::WriteAllText($Path, $content, [System.Text.UTF8Encoding]::new($false))
}

function Assert-RequiredFiles {
    $requiredFiles = @(
        "project.godot",
        "export_presets.cfg",
        "src\update_bootstrap.gd",
        "src\local_database_sync.gd",
        "src\inventory_store.gd",
        "src\inventory_dashboard.gd",
        "src\anatel_coverage.gd",
        "data\anatel_smp_2g4g_brasil.json",
        "data\anatel_smp_2g4g_regional.json",
        "src\core\app_event_bus.gd",
        "src\core\module_registry.gd",
        "src\integrations\integration_manager.gd",
        "src\ui\app_design_system.gd",
        "src\security\secret_vault.gd",
        "ai\ai_manager.gd"
    )

    $missingFiles = @()
    foreach ($relativePath in $requiredFiles) {
        $absolutePath = Join-Path $projectRoot $relativePath
        if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
            $missingFiles += $relativePath
        }
    }
    if ($missingFiles.Count -gt 0) {
        throw "Publicacao bloqueada. Arquivos obrigatorios ausentes: $($missingFiles -join ', ')"
    }
}

function Assert-PackageCopy {
    param(
        [string]$Path,
        [int64]$ExpectedSize,
        [string]$ExpectedSha256
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Copia do pacote nao encontrada: $Path"
    }
    $item = Get-Item -LiteralPath $Path
    if ([int64]$item.Length -ne $ExpectedSize) {
        throw "Tamanho incorreto em $Path"
    }
    $actualSha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualSha256 -ne $ExpectedSha256) {
        throw "SHA-256 incorreto em $Path"
    }
}

function Resolve-FixedExecutableBaseVersion {
    $candidates = @()
    $preferred = Join-Path $distributionDir "GRUPO RS CENTRAL.exe"
    if (Test-Path -LiteralPath $preferred -PathType Leaf) {
        $candidates += Get-Item -LiteralPath $preferred
    }
    $candidates += @(Get-ChildItem -LiteralPath $distributionDir -Filter "*.exe" -File -ErrorAction SilentlyContinue)

    foreach ($candidate in ($candidates | Sort-Object FullName -Unique)) {
        $versionInfo = $candidate.VersionInfo
        $rawVersion = @($versionInfo.ProductVersion, $versionInfo.FileVersion) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -First 1
        if ($null -eq $rawVersion) {
            continue
        }
        $match = [regex]::Match([string]$rawVersion, '^\d+\.\d+\.\d+(?:\.\d+)?')
        if ($match.Success) {
            return $match.Value
        }
    }
    return ""
}

$resolvedGodot = Resolve-GodotExecutable -RequestedPath $Godot
Assert-RequiredFiles

$projectContent = [System.IO.File]::ReadAllText($projectFile)
$versionMatch = [regex]::Match($projectContent, '(?m)^config/version="([^"]+)"$')
if (-not $versionMatch.Success) {
    throw "config/version nao encontrada em project.godot"
}
$currentVersion = [version]$versionMatch.Groups[1].Value
if ([version]$Version -le $currentVersion) {
    throw "A nova versao ($Version) deve ser maior que a versao atual ($currentVersion)."
}
if (Test-Path -LiteralPath $releaseDir) {
    throw "A versao $Version ja possui uma copia permanente em releases. Use um novo numero."
}

$versionParts = @($Version.Split("."))
while ($versionParts.Count -lt 4) {
    $versionParts += "0"
}
$windowsVersion = ($versionParts[0..3] -join ".")
if ([string]::IsNullOrWhiteSpace($Notes)) {
    $Notes = "Correcoes e melhorias da versao $Version."
}

$fixedBaseVersion = Resolve-FixedExecutableBaseVersion
if ([string]::IsNullOrWhiteSpace($MinimumBaseVersion)) {
    $MinimumBaseVersion = if ($fixedBaseVersion -ne "") { $fixedBaseVersion } else { "3.8.0" }
}
if ($fixedBaseVersion -ne "" -and [version]$MinimumBaseVersion -gt [version]$fixedBaseVersion) {
    throw "MinimumBaseVersion ($MinimumBaseVersion) nao pode ser maior que o executavel-base distribuido ($fixedBaseVersion)."
}

[System.IO.Directory]::CreateDirectory($updatesDir) | Out-Null
[System.IO.Directory]::CreateDirectory($stagingDir) | Out-Null

if (Test-Path -LiteralPath $stagedPackagePath -PathType Leaf) {
    Remove-Item -LiteralPath $stagedPackagePath -Force
}
if (Test-Path -LiteralPath $stagedManifestPath -PathType Leaf) {
    Remove-Item -LiteralPath $stagedManifestPath -Force
}

$projectOriginal = [System.IO.File]::ReadAllText($projectFile)
$presetOriginal = [System.IO.File]::ReadAllText($presetFile)
$previousUpdatesManifestExists = Test-Path -LiteralPath $updatesManifestPath -PathType Leaf
if ($previousUpdatesManifestExists) {
    $previousUpdatesManifest = [System.IO.File]::ReadAllBytes($updatesManifestPath)
}

try {
    Set-QuotedConfigValue -Path $projectFile -Key "config/version" -Value $Version
    Set-QuotedConfigValue -Path $presetFile -Key "application/file_version" -Value $windowsVersion
    Set-QuotedConfigValue -Path $presetFile -Key "application/product_version" -Value $windowsVersion

    Write-Host "Gerando pacote temporario $packageName..." -ForegroundColor Cyan
    & $resolvedGodot --headless --path $projectRoot --export-pack "Windows Desktop" $stagedPackagePath -- --update-test-mode
    if ($LASTEXITCODE -ne 0) {
        throw "O Godot falhou ao exportar o pacote. Codigo: $LASTEXITCODE"
    }
    if (-not (Test-Path -LiteralPath $stagedPackagePath -PathType Leaf)) {
        throw "O pacote temporario nao foi criado."
    }

    $packageInfo = Get-Item -LiteralPath $stagedPackagePath
    if ([int64]$packageInfo.Length -lt 1MB) {
        throw "O pacote gerado e pequeno demais e provavelmente esta incompleto."
    }
    $sha256 = (Get-FileHash -LiteralPath $stagedPackagePath -Algorithm SHA256).Hash.ToLowerInvariant()

    Write-Host "Validando inicializacao do pacote..." -ForegroundColor Cyan
    & $resolvedGodot --headless --main-pack $stagedPackagePath --quit-after 120 -- --update-test-mode
    if ($LASTEXITCODE -ne 0) {
        throw "O pacote foi gerado, mas nao conseguiu iniciar. Codigo: $LASTEXITCODE"
    }

    [System.IO.Directory]::CreateDirectory($archiveDir) | Out-Null
    [System.IO.Directory]::CreateDirectory($releaseDir) | Out-Null
    $publicationDirs = @($updatesDir, $archiveDir, $releaseDir)
    foreach ($targetDir in $publicationDirs) {
        [System.IO.Directory]::CreateDirectory($targetDir) | Out-Null
        $targetPackage = Join-Path $targetDir $packageName
        Copy-Item -LiteralPath $stagedPackagePath -Destination $targetPackage -Force
        $publishedPackagePaths += $targetPackage
        Assert-PackageCopy -Path $targetPackage -ExpectedSize ([int64]$packageInfo.Length) -ExpectedSha256 $sha256
    }

    $manifest = [ordered]@{
        app = "grupo-rs-central"
        channel = "stable"
        version = $Version
        minimum_base_version = $MinimumBaseVersion
        package = $packageName
        sha256 = $sha256
        size = [int64]$packageInfo.Length
        notes = $Notes
        created_at = [DateTime]::Now.ToString("yyyy-MM-ddTHH:mm:sszzz")
        requires_restart = $true
    }
    $manifestJson = $manifest | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($stagedManifestPath, $manifestJson, [System.Text.UTF8Encoding]::new($false))
    $null = Get-Content -LiteralPath $stagedManifestPath -Raw | ConvertFrom-Json

    # O manifesto e publicado por ultimo. Assim nunca aponta para um pacote ausente.
    foreach ($targetDir in $publicationDirs) {
        $targetManifest = Join-Path $targetDir $manifestName
        Copy-Item -LiteralPath $stagedManifestPath -Destination $targetManifest -Force

        $publishedManifest = Get-Content -LiteralPath $targetManifest -Raw | ConvertFrom-Json
        $publishedPackage = Join-Path $targetDir ([string]$publishedManifest.package)
        Assert-PackageCopy `
            -Path $publishedPackage `
            -ExpectedSize ([int64]$publishedManifest.size) `
            -ExpectedSha256 ([string]$publishedManifest.sha256).ToLowerInvariant()
    }

    Remove-Item -LiteralPath $stagedPackagePath -Force
    Remove-Item -LiteralPath $stagedManifestPath -Force

    Write-Host ""
    Write-Host "ATUALIZACAO PRONTA E VERIFICADA" -ForegroundColor Green
    Write-Host "Versao:     $Version"
    Write-Host "Pacote:     $(Join-Path $updatesDir $packageName)"
    Write-Host "Permanente: $releaseDir"
    Write-Host "SHA-256:    $sha256"
    Write-Host ""
    Write-Host "Abra o sistema, entre em Config. > Atualizacoes e clique em Verificar agora."
}
catch {
    if ($null -ne $projectOriginal) {
        [System.IO.File]::WriteAllText($projectFile, $projectOriginal, [System.Text.UTF8Encoding]::new($false))
    }
    if ($null -ne $presetOriginal) {
        [System.IO.File]::WriteAllText($presetFile, $presetOriginal, [System.Text.UTF8Encoding]::new($false))
    }
    foreach ($publishedPath in $publishedPackagePaths) {
        if (Test-Path -LiteralPath $publishedPath -PathType Leaf) {
            Remove-Item -LiteralPath $publishedPath -Force
        }
    }
    foreach ($manifestPath in @(
        (Join-Path $archiveDir $manifestName),
        (Join-Path $releaseDir $manifestName)
    )) {
        if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
            Remove-Item -LiteralPath $manifestPath -Force
        }
    }
    if ($previousUpdatesManifestExists) {
        [System.IO.File]::WriteAllBytes($updatesManifestPath, [byte[]]$previousUpdatesManifest)
    }
    elseif (Test-Path -LiteralPath $updatesManifestPath -PathType Leaf) {
        Remove-Item -LiteralPath $updatesManifestPath -Force
    }
    foreach ($temporaryPath in @($stagedPackagePath, $stagedManifestPath)) {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
    foreach ($createdDir in @($releaseDir, $archiveDir)) {
        if (Test-Path -LiteralPath $createdDir -PathType Container) {
            $remainingItems = @(Get-ChildItem -LiteralPath $createdDir -Force)
            if ($remainingItems.Count -eq 0) {
                Remove-Item -LiteralPath $createdDir -Force
            }
        }
    }
    throw
}

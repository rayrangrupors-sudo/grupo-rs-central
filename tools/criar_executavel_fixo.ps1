[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+(?:\.\d+)?$')]
    [string]$BaseVersion = "3.8.0",

    [string]$Godot = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$projectFile = Join-Path $projectRoot "project.godot"
$presetFile = Join-Path $projectRoot "export_presets.cfg"
$distributionDir = Join-Path $projectRoot "dist\GRUPO RS CENTRAL"
$updatesDir = Join-Path $distributionDir "updates"
$executablePath = Join-Path $distributionDir "GRUPO RS CENTRAL.exe"

function Resolve-GodotExecutable {
    param([string]$RequestedPath)

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $candidates += $RequestedPath
    }
    $candidates += (Join-Path $projectRoot "godot\Godot_v4.7.1-stable_win64_console.exe")
    $candidates += (Join-Path $projectRoot "godot\Godot_v4.7.1-stable_win64.exe")

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

$resolvedGodot = Resolve-GodotExecutable -RequestedPath $Godot
foreach ($requiredPath in @($projectFile, $presetFile, (Join-Path $projectRoot "src\update_bootstrap.gd"))) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Arquivo obrigatorio ausente: $requiredPath"
    }
}

[System.IO.Directory]::CreateDirectory($distributionDir) | Out-Null
[System.IO.Directory]::CreateDirectory($updatesDir) | Out-Null

$parts = @($BaseVersion.Split("."))
while ($parts.Count -lt 4) {
    $parts += "0"
}
$windowsVersion = ($parts[0..3] -join ".")
Set-QuotedConfigValue -Path $projectFile -Key "config/version" -Value $BaseVersion
Set-QuotedConfigValue -Path $presetFile -Key "application/file_version" -Value $windowsVersion
Set-QuotedConfigValue -Path $presetFile -Key "application/product_version" -Value $windowsVersion

Write-Host "Criando o executavel fixo v$BaseVersion..." -ForegroundColor Cyan
& $resolvedGodot --headless --path $projectRoot --export-release "Windows Desktop" $executablePath -- --update-test-mode
if ($LASTEXITCODE -ne 0) {
    throw "O Godot falhou ao criar o executavel fixo. Codigo: $LASTEXITCODE"
}
if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
    throw "Executavel nao encontrado apos a exportacao."
}

Write-Host ""
Write-Host "EXECUTAVEL FIXO PRONTO" -ForegroundColor Green
Write-Host $executablePath
Write-Host "As proximas versoes devem ser geradas com tools\publicar_atualizacao.ps1."

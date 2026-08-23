param(
    [ValidateSet('Import', 'Export')]
    [string]$Mode = 'Import',
    [string]$BundlePath = ''
)

$ErrorActionPreference = 'Stop'
$distPath = Join-Path $PSScriptRoot '..\dist\GRUPO RS CENTRAL'
$scriptLocalExe = Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'GRUPO RS CENTRAL *.exe' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne 'GRUPO RS CENTRAL.exe' } |
    Select-Object -First 1
if ($null -ne $scriptLocalExe) {
    # Copia publicada: o script esta na mesma pasta do executavel.
    $distPath = $PSScriptRoot
}
$exePath = Join-Path $distPath 'GRUPO RS CENTRAL.exe'
if (-not (Test-Path -LiteralPath $exePath)) {
	$exePath = Join-Path $distPath 'GRUPO RS CENTRAL 4.0.48.exe'
}
if (-not (Test-Path -LiteralPath $exePath)) {
    $exePath = Join-Path $distPath 'GRUPO RS CENTRAL 4.0.38.exe'
}
if (-not (Test-Path -LiteralPath $exePath)) {
    $exePath = Join-Path $distPath 'GRUPO RS CENTRAL 4.0.37.exe'
}
if (-not (Test-Path -LiteralPath $exePath)) {
    $exePath = Join-Path $distPath 'GRUPO RS CENTRAL.exe'
}
if (-not (Test-Path -LiteralPath $exePath)) {
    throw 'Executavel nao encontrado ao lado deste script.'
}

if ($BundlePath -eq '') {
    $BundlePath = Join-Path $distPath 'secrets-transfer.enc'
}
$BundlePath = [IO.Path]::GetFullPath($BundlePath)
if ($Mode -eq 'Import' -and -not (Test-Path -LiteralPath $BundlePath)) {
    throw "Pacote de transferencia nao encontrado: $BundlePath"
}

function ConvertFrom-SecureText([Security.SecureString]$SecureText) {
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureText)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

try {
    if ($Mode -eq 'Import') {
        $transferPassword = ConvertFrom-SecureText (Read-Host 'Senha do pacote de transferencia' -AsSecureString)
        $vaultPassword = ConvertFrom-SecureText (Read-Host 'Nova senha local do cofre' -AsSecureString)
    } else {
        $vaultPassword = ConvertFrom-SecureText (Read-Host 'Senha atual do cofre' -AsSecureString)
        $transferPassword = ConvertFrom-SecureText (Read-Host 'Nova senha do pacote de transferencia' -AsSecureString)
    }

    $env:GRUPO_RS_TRANSFER_MODE = $Mode.ToLowerInvariant()
    $env:GRUPO_RS_TRANSFER_BUNDLE_PATH = $BundlePath
    $env:GRUPO_RS_TRANSFER_PASSWORD = $transferPassword
    $env:GRUPO_RS_VAULT_PASSWORD = $vaultPassword
    $env:GRUPO_RS_VAULT_PATH = Join-Path $distPath '.secrets\integrations.vault'
    # O executavel trata GRUPO_RS_TRANSFER_MODE no autoload SecretVault; nao
    # passamos a senha como argumento de linha de comando.
    & $exePath --headless
    exit $LASTEXITCODE
} finally {
    Remove-Item Env:GRUPO_RS_TRANSFER_MODE -ErrorAction SilentlyContinue
    Remove-Item Env:GRUPO_RS_TRANSFER_BUNDLE_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:GRUPO_RS_TRANSFER_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:GRUPO_RS_VAULT_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:GRUPO_RS_VAULT_PATH -ErrorAction SilentlyContinue
}

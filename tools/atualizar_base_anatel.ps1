param(
    [string]$SourceUrl = "https://www.anatel.gov.br/dadosabertos/paineis_de_dados/outorga_e_licenciamento/estacoes_smp.zip",
    [string]$OutputPath = "",
    [string]$ExistingZip = "",
    [string]$Generations = "2G,4G",
    [ValidateSet("Brasil", "Regional")]
    [string]$Scope = "Brasil"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    if ($Scope -eq "Brasil") {
        $defaultFile = "anatel_smp_2g4g_brasil.json"
    } else {
        $defaultFile = "anatel_smp_2g4g_regional.json"
    }
    $OutputPath = Join-Path $PSScriptRoot "..\data\$defaultFile"
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$resolvedOutput = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
    [System.IO.Path]::GetFullPath($OutputPath)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $projectRoot $OutputPath))
}
$outputDirectory = Split-Path -Parent $resolvedOutput
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$allowedGenerations = @($Generations -split "," | ForEach-Object { $_.Trim().ToUpperInvariant() } | Where-Object { $_ -in @("2G", "4G") })
if ($allowedGenerations.Count -eq 0) {
    throw "Informe pelo menos uma geracao valida: 2G ou 4G."
}

$tempDirectory = Join-Path $env:TEMP "grupo-rs-anatel"
New-Item -ItemType Directory -Force -Path $tempDirectory | Out-Null
$zipPath = if ([string]::IsNullOrWhiteSpace($ExistingZip)) {
    Join-Path $tempDirectory "estacoes_smp.zip"
} else {
    [System.IO.Path]::GetFullPath($ExistingZip)
}

if (-not (Test-Path -LiteralPath $zipPath) -or (Get-Item -LiteralPath $zipPath).Length -lt 90000000) {
    Write-Host "Baixando a base oficial de estacoes SMP da Anatel..."
    & curl.exe -L --fail --retry 2 --output $zipPath $SourceUrl
    if ($LASTEXITCODE -ne 0) {
        throw "Nao foi possivel baixar a base da Anatel."
    }
}

$sourceLastModified = ""
try {
    $head = Invoke-WebRequest -UseBasicParsing -Method Head -Uri $SourceUrl -TimeoutSec 30
    $sourceLastModified = [string]$head.Headers["Last-Modified"]
} catch {
    $sourceLastModified = (Get-Item -LiteralPath $zipPath).LastWriteTimeUtc.ToString("R")
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName Microsoft.VisualBasic

function Normalize-Operator([string]$value) {
    $clean = $value.Trim().ToUpperInvariant()
    if ($clean -match "CLARO") { return "CLARO" }
    if ($clean -match "TIM") { return "TIM" }
    if ($clean -match "VIVO|TELEFONICA") { return "VIVO" }
    return "OUTRAS"
}

function Add-UniqueValue([System.Collections.ArrayList]$list, [string]$value) {
    $clean = $value.Trim()
    if (-not [string]::IsNullOrWhiteSpace($clean) -and -not $list.Contains($clean)) {
        [void]$list.Add($clean)
    }
}

$archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $entry = $archive.Entries | Where-Object { $_.FullName -like "*.csv" } | Select-Object -First 1
    if ($null -eq $entry) {
        throw "O ZIP oficial nao contem o CSV esperado."
    }

    $parser = [Microsoft.VisualBasic.FileIO.TextFieldParser]::new(
        $entry.Open(),
        [System.Text.Encoding]::UTF8,
        $true
    )
    $parser.TextFieldType = [Microsoft.VisualBasic.FileIO.FieldType]::Delimited
    $parser.SetDelimiters(";")
    $parser.HasFieldsEnclosedInQuotes = $true

    try {
        $headers = $parser.ReadFields()
        if ($headers.Count -lt 40 -or $headers[1] -notmatch "Esta") {
            throw "O formato do CSV da Anatel mudou. A geracao foi interrompida com seguranca."
        }

        # O catalogo nacional pode conter muitas linhas. Escrevemos o JSON em fluxo
        # e mantemos somente as chaves ja emitidas para deduplicacao.
        $stationKeys = [System.Collections.Generic.HashSet[string]]::new()
        $sourceRows = 0
        $selectedRows = 0
        $uniqueStations = 0
        $temporaryOutput = "$resolvedOutput.tmp"
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        $writer = [System.IO.StreamWriter]::new($temporaryOutput, $false, $utf8NoBom)
        $writer.Write('{"stations":[')
        $firstStation = $true

        try {
            while (-not $parser.EndOfData) {
                $fields = $parser.ReadFields()
                $sourceRows++
                if ($fields.Count -lt 41) { continue }
                if ($Scope -eq "Regional" -and $fields[39].Trim().ToUpperInvariant() -ne "MA") { continue }
                $generation = $fields[35].Trim().ToUpperInvariant()
                if ($generation -notin $allowedGenerations) { continue }
                if ($fields[30].Trim().ToUpperInvariant() -ne "LICENCIADA") { continue }

                $latitude = 0.0
                $longitude = 0.0
                $culture = [System.Globalization.CultureInfo]::InvariantCulture
                $numberStyle = [System.Globalization.NumberStyles]::Float
                if (-not [double]::TryParse($fields[19], $numberStyle, $culture, [ref]$latitude)) { continue }
                if (-not [double]::TryParse($fields[20], $numberStyle, $culture, [ref]$longitude)) { continue }

                if ($Scope -eq "Regional") {
                    # Regional footprint used by Imperatriz and the neighboring bases in the app.
                    if ($latitude -lt -7.25 -or $latitude -gt -4.0) { continue }
                    if ($longitude -lt -49.0 -or $longitude -gt -46.5) { continue }
                }

                $selectedRows++
                $operatorName = Normalize-Operator $fields[32]
                $key = "{0}|{1}|{2}|{3:F6}|{4:F6}" -f $fields[1], $operatorName, $generation, $latitude, $longitude
                if (-not $stationKeys.Add($key)) { continue }

                $station = [ordered]@{
                    id = $fields[1].Trim()
                    operator = $operatorName
                    generation = $generation
                    lat = [math]::Round($latitude, 6)
                    lng = [math]::Round($longitude, 6)
                    city = $fields[38].Trim()
                    district = $fields[22].Trim()
                    address = $fields[21].Trim()
                    bands = @($fields[33].Trim() | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                    technologies = @($fields[15].Trim() | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                }
                if (-not $firstStation) { $writer.Write(',') }
                $writer.Write(($station | ConvertTo-Json -Depth 6 -Compress))
                $firstStation = $false
                $uniqueStations++
            }

            $metadata = [ordered]@{
                provider = "Agencia Nacional de Telecomunicacoes - Anatel"
                dataset = "Estacoes do Servico Movel Pessoal - SMP"
                source_url = $SourceUrl
                source_last_modified = $sourceLastModified
                generated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                generation = ($allowedGenerations -join ",")
                generations = @($allowedGenerations)
                status = "Licenciada"
                scope = $Scope
                coverage = if ($Scope -eq "Brasil") { "Brasil" } else { "Maranhao e regiao de Imperatriz" }
                source_rows = $sourceRows
                selected_rows = $selectedRows
                unique_stations = $uniqueStations
            }
            $writer.Write('],"metadata":')
            $writer.Write(($metadata | ConvertTo-Json -Depth 6 -Compress))
            $writer.Write('}')
            $writer.Flush()
            $writer.Dispose()
            Move-Item -LiteralPath $temporaryOutput -Destination $resolvedOutput -Force
        } catch {
            if ($null -ne $writer) { $writer.Dispose() }
            if (Test-Path -LiteralPath $temporaryOutput) { Remove-Item -LiteralPath $temporaryOutput -Force }
            throw
        }

        Write-Host "Base $Scope criada: $resolvedOutput"
        Write-Host "Estacoes $($allowedGenerations -join '/') unicas: $uniqueStations"
    } finally {
        $parser.Close()
    }
} finally {
    $archive.Dispose()
}

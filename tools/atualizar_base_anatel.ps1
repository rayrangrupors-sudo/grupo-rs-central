param(
    [string]$SourceUrl = "https://www.anatel.gov.br/dadosabertos/paineis_de_dados/outorga_e_licenciamento/estacoes_smp.zip",
    [string]$OutputPath = "",
    [string]$ExistingZip = "",
    [string]$Generations = "2G,3G,4G,5G",
    [ValidateSet("Brasil", "Regional")]
    [string]$Scope = "Brasil"
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    if ($Scope -eq "Brasil") {
        $defaultFile = "anatel_smp_brasil.json"
    } else {
        $defaultFile = "anatel_smp_regional.json"
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
$allowedGenerations = @($Generations -split "," | ForEach-Object { $_.Trim().ToUpperInvariant() } | Where-Object { $_ -in @("2G", "3G", "4G", "5G") })
if ($allowedGenerations.Count -eq 0) {
    throw "Informe pelo menos uma geracao valida: 2G, 3G, 4G ou 5G."
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
$sourceZipSha256 = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
$sourceZipBytes = (Get-Item -LiteralPath $zipPath).Length

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

function Normalize-Header([string]$value) {
    $formD = $value.Trim().Normalize([System.Text.NormalizationForm]::FormD)
    $builder = [System.Text.StringBuilder]::new()
    foreach ($character in $formD.ToCharArray()) {
        $category = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($character)
        if ($category -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($character)
        }
    }
    return $builder.ToString().Normalize([System.Text.NormalizationForm]::FormC)
}

function Get-RequiredColumnIndex([hashtable]$columns, [string]$name) {
    if (-not $columns.ContainsKey($name)) {
        throw "O formato do CSV da Anatel mudou: coluna obrigatoria ausente: $name"
    }
    return [int]$columns[$name]
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
        $columns = @{}
        for ($headerIndex = 0; $headerIndex -lt $headers.Count; $headerIndex++) {
            $columns[(Normalize-Header $headers[$headerIndex])] = $headerIndex
        }
        $stationIdIndex = Get-RequiredColumnIndex $columns "Numero Estacao"
        $frequencyIndex = Get-RequiredColumnIndex $columns "Frequencia (MHz)"
        $bandMhzIndex = Get-RequiredColumnIndex $columns "Banda_MHZ"
        $frequencyInitialIndex = Get-RequiredColumnIndex $columns "Frequencia Inicial"
        $frequencyFinalIndex = Get-RequiredColumnIndex $columns "Frequencia Final"
        $frequencyTxIndex = Get-RequiredColumnIndex $columns "FreqTxMHz"
        $frequencyRxIndex = Get-RequiredColumnIndex $columns "FreqRxMHz"
        $validityIndex = Get-RequiredColumnIndex $columns "Data Validade"
        $entityIndex = Get-RequiredColumnIndex $columns "Entidade"
        $technologyIndex = Get-RequiredColumnIndex $columns "Tecnologia"
        $technology5gIndex = Get-RequiredColumnIndex $columns "Tipo de Tecnologia 5G"
        $latitudeIndex = Get-RequiredColumnIndex $columns "Latitude decimal"
        $longitudeIndex = Get-RequiredColumnIndex $columns "Longitude decimal"
        $addressIndex = Get-RequiredColumnIndex $columns "EnderecoEstacao"
        $districtIndex = Get-RequiredColumnIndex $columns "EndBairro"
        $addressNumberIndex = Get-RequiredColumnIndex $columns "EndNumero"
        $addressComplementIndex = Get-RequiredColumnIndex $columns "EndComplemento"
        $infrastructureIndex = Get-RequiredColumnIndex $columns "ClassInfraFisica"
        $firstLicenseIndex = Get-RequiredColumnIndex $columns "Data Primeiro Licenciamento"
        $licenseDateIndex = Get-RequiredColumnIndex $columns "Data Licenciamento"
        $statusIndex = Get-RequiredColumnIndex $columns "Situacao"
        $providerIndex = Get-RequiredColumnIndex $columns "Empresa Estacao"
        $stationBandIndex = Get-RequiredColumnIndex $columns "Faixa Estacao"
        $stationSubBandIndex = Get-RequiredColumnIndex $columns "Subfaixa Estacao"
        $generationIndex = Get-RequiredColumnIndex $columns "Geracao"
        $cityIndex = Get-RequiredColumnIndex $columns "Municipio-UF"
        $stateIndex = Get-RequiredColumnIndex $columns "UF"

        # O CSV e sempre lido em fluxo. No recorte regional, retemos apenas as
        # poucas centenas de ERBs deduplicadas para agregar campos que aparecem
        # em linhas de frequencia diferentes. Nunca retemos as 3 milhoes de linhas.
        $stationKeys = [System.Collections.Generic.HashSet[string]]::new()
        $regionalStations = [ordered]@{}
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
                if ($fields.Count -lt $headers.Count) { continue }
                if ($Scope -eq "Regional" -and $fields[$stateIndex].Trim().ToUpperInvariant() -ne "MA") { continue }
                $generation = $fields[$generationIndex].Trim().ToUpperInvariant()
                if ($generation -notin $allowedGenerations) { continue }
                if ($fields[$statusIndex].Trim().ToUpperInvariant() -ne "LICENCIADA") { continue }

                $latitude = 0.0
                $longitude = 0.0
                $culture = [System.Globalization.CultureInfo]::InvariantCulture
                $numberStyle = [System.Globalization.NumberStyles]::Float
                if (-not [double]::TryParse($fields[$latitudeIndex], $numberStyle, $culture, [ref]$latitude)) { continue }
                if (-not [double]::TryParse($fields[$longitudeIndex], $numberStyle, $culture, [ref]$longitude)) { continue }

                if ($Scope -eq "Regional") {
                    # Regional footprint used by Imperatriz and the neighboring bases in the app.
                    if ($latitude -lt -7.25 -or $latitude -gt -4.0) { continue }
                    if ($longitude -lt -49.0 -or $longitude -gt -46.5) { continue }
                }

                $selectedRows++
                $providerName = $fields[$providerIndex].Trim()
                $operatorName = Normalize-Operator $providerName
                $technologyValues = [System.Collections.ArrayList]::new()
                Add-UniqueValue $technologyValues $fields[$technologyIndex]
                Add-UniqueValue $technologyValues $fields[$technology5gIndex]
                $bandValues = [System.Collections.ArrayList]::new()
                Add-UniqueValue $bandValues $fields[$stationBandIndex]
                Add-UniqueValue $bandValues $fields[$stationSubBandIndex]
                Add-UniqueValue $bandValues $fields[$bandMhzIndex]

                $key = "{0}|{1}|{2}|{3:F6}|{4:F6}" -f $fields[$stationIdIndex], $operatorName, $generation, $latitude, $longitude
                $isNewStation = $stationKeys.Add($key)
                if (-not $isNewStation) {
                    if ($Scope -eq "Regional") {
                        $existing = $regionalStations[$key]
                        foreach ($fieldName in @(
                            "provider_name", "entity", "city", "uf", "district", "address",
                            "address_number", "address_complement", "status", "infrastructure_class",
                            "first_license_date", "license_date", "license_valid_until", "frequency_mhz",
                            "frequency_initial_mhz", "frequency_final_mhz", "frequency_tx_mhz", "frequency_rx_mhz"
                        )) {
                            if ([string]::IsNullOrWhiteSpace([string]$existing[$fieldName])) {
                                $sourceFieldIndex = switch ($fieldName) {
                                    "provider_name" { $providerIndex }
                                    "entity" { $entityIndex }
                                    "city" { $cityIndex }
                                    "uf" { $stateIndex }
                                    "district" { $districtIndex }
                                    "address" { $addressIndex }
                                    "address_number" { $addressNumberIndex }
                                    "address_complement" { $addressComplementIndex }
                                    "status" { $statusIndex }
                                    "infrastructure_class" { $infrastructureIndex }
                                    "first_license_date" { $firstLicenseIndex }
                                    "license_date" { $licenseDateIndex }
                                    "license_valid_until" { $validityIndex }
                                    "frequency_mhz" { $frequencyIndex }
                                    "frequency_initial_mhz" { $frequencyInitialIndex }
                                    "frequency_final_mhz" { $frequencyFinalIndex }
                                    "frequency_tx_mhz" { $frequencyTxIndex }
                                    "frequency_rx_mhz" { $frequencyRxIndex }
                                }
                                $existing[$fieldName] = $fields[$sourceFieldIndex].Trim()
                            }
                        }
                        $existing["bands"] = @($existing["bands"] + @($bandValues) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
                        $existing["technologies"] = @($existing["technologies"] + @($technologyValues) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
                        $regionalStations[$key] = $existing
                    }
                    continue
                }

                $station = [ordered]@{
                    id = $fields[$stationIdIndex].Trim()
                    operator = $operatorName
                    provider_name = $providerName
                    entity = $fields[$entityIndex].Trim()
                    generation = $generation
                    lat = [math]::Round($latitude, 6)
                    lng = [math]::Round($longitude, 6)
                    city = $fields[$cityIndex].Trim()
                    uf = $fields[$stateIndex].Trim()
                    district = $fields[$districtIndex].Trim()
                    address = $fields[$addressIndex].Trim()
                    address_number = $fields[$addressNumberIndex].Trim()
                    address_complement = $fields[$addressComplementIndex].Trim()
                    status = $fields[$statusIndex].Trim()
                    infrastructure_class = $fields[$infrastructureIndex].Trim()
                    first_license_date = $fields[$firstLicenseIndex].Trim()
                    license_date = $fields[$licenseDateIndex].Trim()
                    license_valid_until = $fields[$validityIndex].Trim()
                    frequency_mhz = $fields[$frequencyIndex].Trim()
                    frequency_initial_mhz = $fields[$frequencyInitialIndex].Trim()
                    frequency_final_mhz = $fields[$frequencyFinalIndex].Trim()
                    frequency_tx_mhz = $fields[$frequencyTxIndex].Trim()
                    frequency_rx_mhz = $fields[$frequencyRxIndex].Trim()
                    bands = @($bandValues)
                    technologies = @($technologyValues)
                }
                if ($Scope -eq "Regional") {
                    $regionalStations[$key] = $station
                } else {
                    if (-not $firstStation) { $writer.Write(',') }
                    $writer.Write(($station | ConvertTo-Json -Depth 6 -Compress))
                    $firstStation = $false
                }
                $uniqueStations++
            }

            if ($Scope -eq "Regional") {
                foreach ($station in $regionalStations.Values) {
                    if (-not $firstStation) { $writer.Write(',') }
                    $writer.Write(($station | ConvertTo-Json -Depth 6 -Compress))
                    $firstStation = $false
                }
            }

            $metadata = [ordered]@{
                provider = "Agencia Nacional de Telecomunicacoes - Anatel"
                dataset = "Estacoes do Servico Movel Pessoal - SMP"
                source_url = $SourceUrl
                source_last_modified = $sourceLastModified
                source_zip_sha256 = $sourceZipSha256
                source_zip_bytes = $sourceZipBytes
                source_entry = $entry.FullName
                generated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                generation = ($allowedGenerations -join ",")
                generations = @($allowedGenerations)
                status = "Licenciada"
                schema_version = 2
                scope = $Scope
                coverage = if ($Scope -eq "Brasil") { "Brasil" } else { "Maranhao e regiao de Imperatriz" }
                selection_rule = if ($Scope -eq "Brasil") { "Situacao LICENCIADA; geracoes selecionadas; coordenadas decimais validas" } else { "UF MA; Situacao LICENCIADA; geracoes selecionadas; latitude -7.25..-4.0; longitude -49.0..-46.5; coordenadas decimais validas" }
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

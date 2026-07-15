param(
  [string]$OutputPath = "$PSScriptRoot\..\entry\src\main\resources\rawfile\visible_stars.json",
  [double]$MagnitudeLimit = 6.5
)

$ErrorActionPreference = 'Stop'
$sourceUrl = 'https://raw.githubusercontent.com/astronexus/HYG-Database/main/hyg/CURRENT/hygdata_v41.csv'
$temporaryFile = Join-Path $env:TEMP 'starfinding-hygdata-v41.csv'

if (-not (Test-Path -LiteralPath $temporaryFile)) {
  Invoke-WebRequest -Uri $sourceUrl -OutFile $temporaryFile -UseBasicParsing
}

# Import-Csv handles quoting correctly when a catalog name contains commas.
$stars = @(Import-Csv -LiteralPath $temporaryFile | Where-Object {
  $_.mag -ne '' -and ([double]($_.mag)) -le $MagnitudeLimit -and $_.ra -ne '' -and $_.dec -ne ''
} | ForEach-Object {
  $catalogId = if ($_.hip -ne '') { "HIP$($_.hip)" } else { "HYG$($_.id)" }
  [ordered]@{
    id = $catalogId
    name = $_.proper
    raHours = [Math]::Round([double]($_.ra), 6)
    decDegrees = [Math]::Round([double]($_.dec), 6)
    pmra = if ($_.pmra -eq '') { 0 } else { [Math]::Round([double]($_.pmra), 3) }
    pmdec = if ($_.pmdec -eq '') { 0 } else { [Math]::Round([double]($_.pmdec), 3) }
    magnitude = [Math]::Round([double]($_.mag), 2)
    constellation = $_.con
    spectralType = $_.spect
    distanceParsec = if ($_.dist -eq '') { 0 } else { [Math]::Round([double]($_.dist), 3) }
  }
})

$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$payload = [ordered]@{
  source = 'HYG Database v4.1'
  sourceUrl = $sourceUrl
  license = 'CC BY-SA 4.0'
  sourceEpochYear = 2000.0
  magnitudeLimit = $MagnitudeLimit
  count = @($stars).Count
  stars = @($stars)
}
$payload | ConvertTo-Json -Depth 4 -Compress | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Output "Generated $(@($stars).Count) visible stars at $OutputPath"

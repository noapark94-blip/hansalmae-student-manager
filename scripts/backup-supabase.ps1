param([string]$OutputDirectory = ".\backups")

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$fileName = "hansalmae-db-{0}.sql" -f (Get-Date -Format "yyyyMMdd-HHmmss")
$outputPath = Join-Path $OutputDirectory $fileName

Write-Host "Supabase 원격 데이터베이스 백업을 시작합니다..."
npx.cmd supabase db dump --linked --file $outputPath
if ($LASTEXITCODE -ne 0) { throw "Supabase 백업에 실패했습니다." }

Write-Host "백업 완료: $outputPath"

param([string]$OutputDirectory = ".\backups")

$ErrorActionPreference = "Stop"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDirectory = Join-Path $OutputDirectory "hansalmae-db-$stamp"
New-Item -ItemType Directory -Force -Path $backupDirectory | Out-Null

$schemaPath = Join-Path $backupDirectory "schema.sql"
$dataPath = Join-Path $backupDirectory "data.sql"
$rolesPath = Join-Path $backupDirectory "roles.sql"

Write-Host "1/3 데이터베이스 구조를 백업합니다..."
npx.cmd supabase db dump --linked --file $schemaPath
if ($LASTEXITCODE -ne 0) { throw "데이터베이스 구조 백업에 실패했습니다." }

Write-Host "2/3 실제 데이터를 백업합니다..."
npx.cmd supabase db dump --linked --data-only --use-copy --file $dataPath
if ($LASTEXITCODE -ne 0) { throw "데이터 백업에 실패했습니다." }

Write-Host "3/3 사용자 정의 역할을 백업합니다..."
npx.cmd supabase db dump --linked --role-only --file $rolesPath
if ($LASTEXITCODE -ne 0) { throw "역할 백업에 실패했습니다." }

Write-Host "백업 완료: $backupDirectory"
Write-Host "schema.sql, data.sql, roles.sql 파일이 생성되었습니다."

param([string]$OutputDirectory = ".\backups")

$ErrorActionPreference = "Stop"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDirectory = Join-Path $OutputDirectory "hansalmae-db-$stamp"
New-Item -ItemType Directory -Force -Path $backupDirectory | Out-Null

$schemaPath = Join-Path $backupDirectory "schema.sql"
$dataPath = Join-Path $backupDirectory "data.sql"
$rolesPath = Join-Path $backupDirectory "roles.sql"

Write-Host "1/3 Backing up database schema..."
npx.cmd supabase db dump --linked --file $schemaPath
if ($LASTEXITCODE -ne 0) { throw "Database schema backup failed." }

Write-Host "2/3 Backing up database data..."
npx.cmd supabase db dump --linked --data-only --use-copy --file $dataPath
if ($LASTEXITCODE -ne 0) { throw "Database data backup failed." }

Write-Host "3/3 Backing up custom roles..."
npx.cmd supabase db dump --linked --role-only --file $rolesPath
if ($LASTEXITCODE -ne 0) { throw "Database role backup failed." }

Write-Host "Backup completed: $backupDirectory"
Write-Host "Created schema.sql, data.sql, and roles.sql."

# Приватная публикация тренажёра: Cloudflare Pages + Access.
# Токен берётся из z:\VIBE\.secrets\cloudflare.env, в код не попадает.
#
#   powershell -ExecutionPolicy Bypass -File z:\VIBE\Writer\site\deploy_private.ps1
#
# Требования к токену: Account → Cloudflare Pages: Edit,
#                      Account → Access: Apps and Policies: Edit,
#                      Account → Account Settings: Read

$ErrorActionPreference = "Stop"

$PROJECT = "razbor-korobov"
$EMAIL   = "ek@eko-res.ru"        # кому разрешён вход
$SECRETS = "z:\VIBE\.secrets\cloudflare.env"
$DIR     = "z:\VIBE\Writer\site\private"

if (-not (Test-Path $SECRETS)) { throw "нет файла $SECRETS — положить туда CLOUDFLARE_API_TOKEN=..." }
if (-not (Test-Path "$DIR\index.html")) { throw "нет $DIR\index.html — сначала python build.py" }

Get-Content $SECRETS | ForEach-Object {
    if ($_ -match '^\s*([A-Z_]+)\s*=\s*(.+?)\s*$') { Set-Item -Path "env:$($matches[1])" -Value $matches[2] }
}
if (-not $env:CLOUDFLARE_API_TOKEN) { throw "в $SECRETS нет CLOUDFLARE_API_TOKEN" }

# ID аккаунта — сам, чтобы не просить руками
if (-not $env:CLOUDFLARE_ACCOUNT_ID) {
    $h = @{ Authorization = "Bearer $env:CLOUDFLARE_API_TOKEN" }
    $acc = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/accounts" -Headers $h
    if (-not $acc.success) { throw "токен не принят: $($acc.errors | ConvertTo-Json -Compress)" }
    $env:CLOUDFLARE_ACCOUNT_ID = $acc.result[0].id
    Write-Host "аккаунт: $($acc.result[0].name)"
}

Write-Host "`n--- деплой Pages ---"
npx --yes wrangler@latest pages deploy $DIR --project-name=$PROJECT --branch=main --commit-dirty=true

$host_name = "$PROJECT.pages.dev"
Write-Host "`n--- Access: закрываем $host_name ---"

$h = @{ Authorization = "Bearer $env:CLOUDFLARE_API_TOKEN"; "Content-Type" = "application/json" }
$api = "https://api.cloudflare.com/client/v4/accounts/$env:CLOUDFLARE_ACCOUNT_ID/access/apps"

$existing = (Invoke-RestMethod -Uri $api -Headers $h).result | Where-Object { $_.domain -eq $host_name }
if ($existing) {
    Write-Host "приложение Access уже есть: $($existing.id)"
} else {
    $body = @{
        name             = "Тренажёр — разбор терминов"
        domain           = $host_name
        type             = "self_hosted"
        session_duration = "720h"
        policies         = @(@{
            name     = "Только владелец"
            decision = "allow"
            include  = @(@{ email = @{ email = $EMAIL } })
        })
    } | ConvertTo-Json -Depth 8
    $r = Invoke-RestMethod -Uri $api -Method Post -Headers $h -Body $body
    if (-not $r.success) { throw "Access не создан: $($r.errors | ConvertTo-Json -Compress)" }
    Write-Host "Access создан, вход разрешён только $EMAIL"
}

Write-Host "`nГотово: https://$host_name  — вход по одноразовому коду на $EMAIL"

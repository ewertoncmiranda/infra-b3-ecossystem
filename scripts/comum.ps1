# Funcoes comuns das rotinas agendadas (diario, cargas do ETL, backup).
# Carregado com:  . (Join-Path $PSScriptRoot 'comum.ps1')
#
# Alerta: Telegram, se as variaveis de ambiente do usuario existirem
#   TELEGRAM_BOT_TOKEN  token do bot (criado no @BotFather)
#   TELEGRAM_CHAT_ID    id do chat que recebe (mande uma mensagem ao bot e
#                       veja em https://api.telegram.org/bot<token>/getUpdates)
# Sem elas, a falha fica no log e aparece como ERRO/ATRASADA na aba
# Avaliacao > Saude dos dados, que le etl_execucao.

$ErrorActionPreference = 'Continue'
$script:Infra = Split-Path -Parent $PSScriptRoot
# Fora de infra-b3-ecossytem\logs de proposito: essa pasta e montada no
# Logstash, que mantem os *.log abertos (no Windows isso bloqueia a escrita).
$script:PastaLocal = Join-Path $env:LOCALAPPDATA 'b3-ecossistema'
New-Item -ItemType Directory -Force -Path $script:PastaLocal | Out-Null

function Escrever-Log([string]$Arquivo, [string]$Texto) {
    $agora = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path (Join-Path $script:PastaLocal $Arquivo) -Value "[$agora] $Texto"
}

function Enviar-Alerta([string]$Texto) {
    $token = [Environment]::GetEnvironmentVariable('TELEGRAM_BOT_TOKEN', 'User')
    $chat = [Environment]::GetEnvironmentVariable('TELEGRAM_CHAT_ID', 'User')
    if (-not $token -or -not $chat) { return $false }
    try {
        Invoke-RestMethod -Method Post -Uri "https://api.telegram.org/bot$token/sendMessage" `
            -Body @{ chat_id = $chat; text = "B3 ecossistema: $Texto" } -TimeoutSec 20 | Out-Null
        return $true
    } catch {
        return $false
    }
}

# SQL no MySQL do compose, com a senha que o proprio container ja conhece.
function Executar-Sql([string]$Sql) {
    $Sql | docker exec -i mysql sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" -N 2>/dev/null'
}

# Rastro em etl_execucao: a saude dos dados mostra quando cada rotina rodou.
function Registrar-Execucao([string]$Fonte, [string]$Status, [int]$Linhas = 0, [string]$Erro = '') {
    $competencia = Get-Date -Format 'yyyy-MM-dd'
    $mensagem = if ($Erro) { "'" + ($Erro -replace "'", "''").Substring(0, [Math]::Min(1000, $Erro.Length)) + "'" } else { 'NULL' }
    Executar-Sql ("INSERT INTO etl_execucao (fonte, competencia, arquivo, status, linhas_carregadas, " +
        "mensagem_erro, finalizado_em) VALUES ('$Fonte', '$competencia', 'rotina', '$Status', $Linhas, $mensagem, NOW());") | Out-Null
}

# Roda um comando do compose e devolve @{ Codigo; Saida }.
function Rodar-Compose([string[]]$Argumentos) {
    Push-Location $script:Infra
    try {
        $saida = & docker compose -f docker-compose-local.yml @Argumentos 2>&1 | ForEach-Object { "$_" }
        return @{ Codigo = $LASTEXITCODE; Saida = $saida }
    } finally {
        Pop-Location
    }
}

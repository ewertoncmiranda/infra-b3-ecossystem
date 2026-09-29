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

# Status (Running/Exited/etc) de um container do compose pelo nome do servico.
function Status-Container([string]$Servico) {
    $r = Rodar-Compose @('ps', '-a', '--format', 'json', $Servico)
    if ($r.Codigo -ne 0 -or -not $r.Saida) { return $null }
    try {
        # docker compose ps --format json devolve uma linha por container.
        $linha = @($r.Saida) | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1
        if (-not $linha) { return $null }
        return $linha | ConvertFrom-Json
    } catch {
        return $null
    }
}

# Garante a stack local no ar antes de qualquer rotina do dia: espera o
# Docker Engine responder, sobe tudo via docker-compose-local.yml e confirma
# que mysql esta saudavel e que db-migrate/my-terraform-provisioner (que sao
# jobs de inicializacao, nao servicos de longa duracao) terminaram com
# sucesso. Pensado pro gatilho de logon: a maquina acabou de ligar, o Docker
# Desktop pode levar minutos para responder.
#
# Devolve $true se a stack esta pronta; $false (com ERRO em etl_execucao e
# alerta) se nao deu pra confirmar dentro do limite.
function Garantir-Stack {
    $log = 'garantir-stack.log'
    $limiteDocker = (Get-Date).AddMinutes(5)
    Escrever-Log $log 'aguardando o Docker Engine responder...'
    while ((Get-Date) -lt $limiteDocker) {
        docker info *> $null
        if ($LASTEXITCODE -eq 0) { break }
        Start-Sleep -Seconds 5
    }
    docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        $motivo = 'Docker Engine nao respondeu em 5 minutos'
        Escrever-Log $log "FALHOU: $motivo"
        Registrar-Execucao 'GARANTIR_STACK' 'ERRO' 0 $motivo
        if (-not (Enviar-Alerta "garantir stack falhou: $motivo")) { Escrever-Log $log 'alerta nao enviado (Telegram nao configurado)' }
        return $false
    }

    # --build: sem isso, um commit novo de gestor/gerar-insights/painel so
    # entra em vigor com um rebuild manual - a rotina rodaria codigo velho
    # depois de qualquer commit (achado pela Sessao 03, 2026-09-29: a rotina
    # das 07:00 rodou sem --recuperar/--conciliar porque a imagem do
    # gerar-insights ainda era a de antes desses comandos existirem).
    # Custa uns segundos a mais quando nao ha mudanca (cache do Docker).
    Escrever-Log $log 'Docker Engine respondeu; subindo a stack (docker compose up -d --build)...'
    $subida = Rodar-Compose @('up', '-d', '--build')
    if ($subida.Codigo -ne 0) {
        # docker compose up --build roda o build ANTES de tocar em qualquer
        # container: se o build falhar, o container antigo (imagem anterior)
        # continua no ar, intocado - so nao sabemos ainda se subiu por outro
        # motivo. Por isso o fallback aqui e so tentar `up -d` sem --build:
        # se isso funcionar, a stack esta de pe com a imagem anterior (algum
        # commit sem codigo quebrado) e a rotina segue, so avisada; se falhar
        # tambem, ai sim e erro de verdade (achado da Sessao 03, 2026-09-29:
        # working tree com codigo quebrado sem commit nao pode travar o dia
        # inteiro).
        $motivoBuild = "docker compose up -d --build saiu com codigo $($subida.Codigo)"
        Escrever-Log $log "AVISO: $motivoBuild - tentando subir com a imagem anterior (sem --build)"
        $subida.Saida | ForEach-Object { Escrever-Log $log "  $_" }

        $subidaSemBuild = Rodar-Compose @('up', '-d')
        if ($subidaSemBuild.Codigo -ne 0) {
            $motivo = "$motivoBuild; fallback sem --build tambem falhou (codigo $($subidaSemBuild.Codigo))"
            Escrever-Log $log "FALHOU: $motivo"
            $subidaSemBuild.Saida | ForEach-Object { Escrever-Log $log "  $_" }
            Registrar-Execucao 'GARANTIR_STACK' 'ERRO' 0 $motivo
            if (-not (Enviar-Alerta "garantir stack falhou: $motivo")) { Escrever-Log $log 'alerta nao enviado (Telegram nao configurado)' }
            return $false
        }
        Escrever-Log $log 'ok: stack subiu com a imagem anterior (build falhou - ver acima; provavel codigo sem commit quebrado)'
        if (-not (Enviar-Alerta "build falhou na rotina da manha, seguindo com a imagem anterior: $motivoBuild")) {
            Escrever-Log $log 'alerta nao enviado (Telegram nao configurado)'
        }
    }

    # mysql e servico de longa duracao: espera o healthcheck ficar "healthy".
    # db-migrate e my-terraform-provisioner sao jobs de inicializacao (rodam e
    # saem); espera os dois pararem e confere o codigo de saida de cada um.
    $limiteServicos = (Get-Date).AddMinutes(5)
    $mysqlOk = $false
    $migrateOk = $false
    $provisionadorOk = $false
    while ((Get-Date) -lt $limiteServicos -and -not ($mysqlOk -and $migrateOk -and $provisionadorOk)) {
        if (-not $mysqlOk) {
            $mysql = Status-Container 'mysql'
            if ($mysql -and $mysql.Health -eq 'healthy') { $mysqlOk = $true }
        }
        if (-not $migrateOk) {
            $migrate = Status-Container 'db-migrate'
            if ($migrate -and $migrate.State -eq 'exited' -and $migrate.ExitCode -eq 0) { $migrateOk = $true }
        }
        if (-not $provisionadorOk) {
            $provisionador = Status-Container 'my-terraform-provisioner'
            if ($provisionador -and $provisionador.State -eq 'exited' -and $provisionador.ExitCode -eq 0) { $provisionadorOk = $true }
        }
        if (-not ($mysqlOk -and $migrateOk -and $provisionadorOk)) { Start-Sleep -Seconds 5 }
    }

    if (-not ($mysqlOk -and $migrateOk -and $provisionadorOk)) {
        $pendentes = @()
        if (-not $mysqlOk) { $pendentes += 'mysql nao ficou saudavel' }
        if (-not $migrateOk) { $pendentes += 'db-migrate nao terminou com sucesso' }
        if (-not $provisionadorOk) { $pendentes += 'my-terraform-provisioner nao terminou com sucesso' }
        $motivo = $pendentes -join '; '
        Escrever-Log $log "FALHOU: $motivo"
        Registrar-Execucao 'GARANTIR_STACK' 'ERRO' 0 $motivo
        if (-not (Enviar-Alerta "garantir stack falhou: $motivo")) { Escrever-Log $log 'alerta nao enviado (Telegram nao configurado)' }
        return $false
    }

    Escrever-Log $log 'ok: stack no ar (mysql saudavel, db-migrate e provisionador com sucesso)'
    Registrar-Execucao 'GARANTIR_STACK' 'SUCESSO'
    return $true
}

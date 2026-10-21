# Rotina da manha (PLANO-ATUALIZACAO-DIARIA.md): recupera o pregao de D no
# COTAHIST/CVM, concilia com a brapi, gera insights e sinais, e roda o
# backtest as sextas. Pensada pra rodar so em horario comercial: a maquina
# fica desligada a noite, entao o disparo e ao ligar (+5 min) e as 07:00,
# nunca mais as 20h/21h30 do pregao anterior (D2: nada de insight preliminar
# com a brapi - so com o preco oficial do COTAHIST).
#
# Registrar: scripts\registrar-rotinas.ps1. Log: %USERPROFILE%\b3-ecossistema\cargas-etl.log
#
# Cada carga compara o ETag antes de baixar: arquivo sem novidade custa uma
# requisicao HEAD. Com a CVM fora do ar, o ETL segue com o cache e avisa.
# Cada passo e idempotente: rodar de novo (recuperacao apos maquina desligada
# ou passo anterior falhar) nao duplica nada.
#
# Cargas do ETL (Plano CARGA, CARGA-INFRA-3): o ETL e um servico interno do
# compose e a entrada unica e POST /cargas. A rotina pede uma carga ROTINA,
# acompanha GET /cargas/{id} ate terminar e soma nas falhas quando o status
# final e FALHA, SUCESSO_PARCIAL ou INTERROMPIDA. Etapas, metricas, alertas e
# erros ficam em carga_execucao/carga_etapa (tela Cargas de dados no painel).

# Backfill pela API (CONS-INFRA-3), sem o profile `etl` e sem CLI do ETL:
#   cargas-etl.ps1 -Backfill                                  COMPLETA (todas as etapas, ultimos 5 anos)
#   cargas-etl.ps1 -Backfill -Etapas CVM_CADASTRO,TESOURO     PARCIAL das etapas
#   cargas-etl.ps1 -Backfill -Etapas CVM_FRE -Anos 2022,2023 -Forcar
#   ... -DryRun    so imprime o corpo JSON do POST /cargas (sem rede, sem stack)
# Sem -Backfill, roda a rotina da manha (abaixo).
param(
    [switch]$Backfill,
    [string[]]$Etapas = @(),
    [string[]]$Anos = @(),
    [string[]]$Simbolos = @(),
    [switch]$Forcar,
    [switch]$DryRun
)

. (Join-Path $PSScriptRoot 'comum.ps1')
$log = 'cargas-etl.log'

if (-not $DryRun -and -not (Garantir-Stack)) {
    Escrever-Log $log 'FALHOU: stack nao ficou pronta; rotina abortada'
    exit 1
}

$etlUrl = if ($env:ETL_URL_HOST) { $env:ETL_URL_HOST } else { 'http://127.0.0.1:8097' }
$limiteCargaMin = if ($env:B3_CARGA_TIMEOUT_MIN) { [int]$env:B3_CARGA_TIMEOUT_MIN } else { 240 }
$intervaloSeg = 15
$statusEmAndamento = @('PENDENTE', 'EXECUTANDO')
$statusComFalha = @('FALHA', 'SUCESSO_PARCIAL', 'INTERROMPIDA')

# Chamada a API de cargas. Devolve @{ Status = <HTTP ou 0 sem conexao>; Corpo = <objeto ou $null> }.
function Chamar-Etl([string]$Metodo, [string]$Caminho, $Corpo = $null) {
    $cabecalhos = @{}
    if ($env:ETL_TOKEN) { $cabecalhos['X-ETL-Token'] = $env:ETL_TOKEN }
    $parametros = @{ Uri = "$etlUrl$Caminho"; Method = $Metodo; Headers = $cabecalhos; UseBasicParsing = $true; TimeoutSec = 30 }
    if ($null -ne $Corpo) {
        $parametros['Body'] = [Text.Encoding]::UTF8.GetBytes(($Corpo | ConvertTo-Json -Depth 5 -Compress))
        $parametros['ContentType'] = 'application/json; charset=utf-8'
    }
    try {
        $resposta = Invoke-WebRequest @parametros
        $texto = [Text.Encoding]::UTF8.GetString($resposta.RawContentStream.ToArray())
        return @{ Status = [int]$resposta.StatusCode; Corpo = $(if ($texto) { $texto | ConvertFrom-Json } else { $null }) }
    } catch [System.Net.WebException] {
        $r = $_.Exception.Response
        if (-not $r) { return @{ Status = 0; Corpo = $null } }
        $leitor = New-Object System.IO.StreamReader($r.GetResponseStream(), [Text.Encoding]::UTF8)
        $texto = $leitor.ReadToEnd()
        $corpoErro = $null
        try { if ($texto) { $corpoErro = $texto | ConvertFrom-Json } } catch { $corpoErro = $null }
        return @{ Status = [int]$r.StatusCode; Corpo = $corpoErro }
    }
}

# Espera a execucao sair de PENDENTE/EXECUTANDO, registrando cada etapa que muda de status.
function Aguardar-Carga([string]$Id) {
    $limite = (Get-Date).AddMinutes($limiteCargaMin)
    $vistos = @{}
    while ((Get-Date) -lt $limite) {
        $r = Chamar-Etl 'GET' "/cargas/$Id"
        if ($r.Status -eq 200 -and $r.Corpo) {
            foreach ($etapa in @($r.Corpo.etapas)) {
                if ($vistos[$etapa.etapa] -ne $etapa.status) {
                    $vistos[$etapa.etapa] = $etapa.status
                    if ($etapa.status -notin @('PENDENTE', 'PULADA')) {
                        Escrever-Log $log "  etapa $($etapa.etapa): $($etapa.status)"
                        if ($script:ecoConsole) { Write-Host "  etapa $($etapa.etapa): $($etapa.status)" }
                    }
                }
            }
            if ($r.Corpo.status -notin $statusEmAndamento) { return $r.Corpo }
        } elseif ($r.Status -eq 0) {
            Escrever-Log $log '  ETL sem resposta durante o acompanhamento; tentando de novo'
        }
        Start-Sleep -Seconds $intervaloSeg
    }
    return $null
}

# Pede uma carga, espera terminar e devolve o codigo da rotina (0 ok, 1 falha).
# Ja havendo carga rodando (409, ex.: disparada pelo painel), espera ela e pede de novo uma vez.
function Rodar-Carga([string]$Nome, [hashtable]$Pedido) {
    Escrever-Log $log "inicio: $Nome"
    if (-not $Pedido.ContainsKey('solicitada_por')) { $Pedido['solicitada_por'] = 'ROTINA_MANHA' }
    foreach ($tentativa in 1..2) {
        $r = Chamar-Etl 'POST' '/cargas' $Pedido
        if ($r.Status -eq 409 -and $tentativa -eq 1) {
            $outra = $r.Corpo.execucao_em_andamento
            Escrever-Log $log "  ja existe carga em andamento ($outra); aguardando terminar"
            if ($outra) { [void](Aguardar-Carga $outra) } else { Start-Sleep -Seconds 60 }
            continue
        }
        break
    }
    if ($r.Status -eq 0) {
        Escrever-Log $log "FALHOU: $Nome (ETL indisponivel em $etlUrl)"
        return 1
    }
    if ($r.Status -ne 202 -or -not $r.Corpo.id) {
        Escrever-Log $log "FALHOU: $Nome (POST /cargas respondeu HTTP $($r.Status))"
        return 1
    }
    $id = $r.Corpo.id
    Escrever-Log $log "  carga $id aceita; acompanhando"
    $final = Aguardar-Carga $id
    if (-not $final) {
        Escrever-Log $log "FALHOU: $Nome (carga $id nao terminou em $limiteCargaMin min)"
        return 1
    }
    $resumo = "status $($final.status) | ok $($final.etapas_ok) | alerta $($final.etapas_alerta) | falha $($final.etapas_falha)"
    foreach ($etapa in @($final.etapas)) {
        foreach ($a in @($etapa.alertas)) { if ($a) { Escrever-Log $log "  AVISO $($etapa.etapa): $a" } }
        foreach ($e in @($etapa.erros)) { if ($e) { Escrever-Log $log "  ERRO $($etapa.etapa): $e" } }
    }
    if ($final.status -in $statusComFalha) {
        Escrever-Log $log "FALHOU: $Nome ($resumo)"
        return 1
    }
    Escrever-Log $log "concluido: $Nome ($resumo)"
    return 0
}

# Catalogo de etapas aceitas pelo ETL (V44 + V45). Etapa fora dele nunca chega a POST /cargas.
$etapasAntigas = @('COTAHIST', 'LIQUIDEZ', 'PRONTIDAO', 'QUALIDADE_OPCOES', 'CONCILIACAO', 'DFP', 'TTM', 'IPE', 'DVA', 'EVENTOS', 'CHECAGENS')
$etapasNovas = @('TESOURO', 'IFDATA', 'CVM_CADASTRO', 'CVM_VLMO', 'CVM_FRE', 'CVM_CDA')
$catalogoEtapas = $etapasAntigas + $etapasNovas

# Corpo do POST /cargas do backfill: COMPLETA sem etapas, PARCIAL com etapas.
function Montar-PedidoBackfill([string[]]$Etapas, $Anos, [string[]]$Simbolos, [bool]$Forcar) {
    $pedido = [ordered]@{ tipo = $(if ($Etapas.Count -gt 0) { 'PARCIAL' } else { 'COMPLETA' }) }
    if ($Etapas.Count -gt 0) { $pedido['etapas'] = @($Etapas) }
    if ($Anos.Count -gt 0) { $pedido['anos'] = @($Anos) }
    if ($Simbolos.Count -gt 0) { $pedido['simbolos'] = @($Simbolos) }
    if ($Forcar) { $pedido['forcar'] = $true }
    $pedido['solicitada_por'] = 'API'
    return $pedido
}

# Valida etapas contra o catalogo local e, se GET /saude listar as etapas, contra o ETL.
# Devolve a lista de mensagens de erro (vazia = ok). Em -DryRun nao usa rede.
function Validar-EtapasBackfill([string[]]$Etapas, [bool]$Seco) {
    $erros = @()
    foreach ($e in $Etapas) {
        if ($e -notin $catalogoEtapas) { $erros += "etapa desconhecida: $e (catalogo: $($catalogoEtapas -join ', '))" }
    }
    if ($erros.Count -gt 0 -or $Seco) { return $erros }
    $s = Chamar-Etl 'GET' '/saude'
    if ($s.Status -eq 0) { return @("ETL indisponivel em $etlUrl") }
    $lista = $null
    if ($s.Corpo) { $lista = $s.Corpo.etapas }
    if ($lista) {
        $nomes = @($lista | ForEach-Object { if ($_.etapa) { $_.etapa } else { "$_" } })
        foreach ($e in $Etapas) {
            if ($e -notin $nomes) { $erros += "etapa $e nao existe neste ETL (imagem sem FONTES-ETL-8?); GET /saude lista: $($nomes -join ', ')" }
        }
    }
    return $erros
}

# Dispara o backfill pela API e acompanha ate o fim, imprimindo o status por etapa.
# Retorna 0 (ok, ou 409 sem erro) ou 1 (falha).
function Rodar-Backfill([string[]]$Etapas, [string[]]$Anos, [string[]]$Simbolos, [bool]$Forcar, [bool]$Seco) {
    # Com -File, "A,B" chega como um unico texto: separa por virgula.
    $Etapas = @($Etapas | ForEach-Object { "$_" -split ',' } | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ })
    $Simbolos = @($Simbolos | ForEach-Object { "$_" -split ',' } | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ })
    $Anos = @($Anos | ForEach-Object { "$_" -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($a in $Anos) { if ($a -notmatch '^(19|20)\d\d$') { Write-Host "ERRO: ano invalido: $a" -ForegroundColor Red; return 1 } }
    $anosInt = [int[]]@($Anos | ForEach-Object { [int]$_ })
    $erros = Validar-EtapasBackfill $Etapas $Seco
    if ($erros.Count -gt 0) {
        $erros | ForEach-Object { Write-Host "ERRO: $_" -ForegroundColor Red }
        return 1
    }
    $pedido = Montar-PedidoBackfill $Etapas $anosInt $Simbolos $Forcar
    if ($Seco) {
        Write-Host "DRY-RUN: POST $etlUrl/cargas"
        Write-Host ($pedido | ConvertTo-Json -Depth 5)
        return 0
    }
    $script:ecoConsole = $true
    Escrever-Log $log "inicio: backfill ($($pedido.tipo) $($Etapas -join ','))"
    $r = Chamar-Etl 'POST' '/cargas' $pedido
    if ($r.Status -eq 409) {
        $msg = "ja existe carga em andamento ($($r.Corpo.execucao_em_andamento)); nada disparado. Acompanhe: GET $etlUrl/cargas/$($r.Corpo.execucao_em_andamento)"
        Escrever-Log $log "  $msg"
        Write-Host $msg
        return 0
    }
    if ($r.Status -eq 0) { Write-Host "ERRO: ETL indisponivel em $etlUrl" -ForegroundColor Red; return 1 }
    if ($r.Status -ne 202 -or -not $r.Corpo.id) { Write-Host "ERRO: POST /cargas respondeu HTTP $($r.Status)" -ForegroundColor Red; return 1 }
    Write-Host "carga $($r.Corpo.id) aceita; acompanhando (GET $etlUrl/cargas/$($r.Corpo.id))"
    $final = Aguardar-Carga $r.Corpo.id
    if (-not $final) { Write-Host "ERRO: carga $($r.Corpo.id) nao terminou em $limiteCargaMin min (segue no ETL)" -ForegroundColor Red; return 1 }
    foreach ($etapa in @($final.etapas)) {
        Write-Host ("  {0,-18} {1}" -f $etapa.etapa, $etapa.status)
        foreach ($a in @($etapa.alertas)) { if ($a) { Write-Host "    AVISO: $a" } }
        foreach ($e in @($etapa.erros)) { if ($e) { Write-Host "    ERRO: $e" } }
    }
    $resumo = "status $($final.status) | ok $($final.etapas_ok) | alerta $($final.etapas_alerta) | falha $($final.etapas_falha)"
    Escrever-Log $log "fim: backfill ($resumo)"
    Write-Host $resumo
    if ($final.status -in $statusComFalha) { return 1 }
    return 0
}

if ($Backfill) {
    exit (Rodar-Backfill $Etapas $Anos $Simbolos $Forcar.IsPresent $DryRun.IsPresent)
}

$insights = @('run', '--rm', '--no-deps', 'gerar-insights', 'python', '-m')
# Opiniao por horizonte: com o compose do servico de IA (rede `ia`, IA_URL) quando o repositorio
# insider-ia esta ao lado; sem ele, o lote grava pela regra local (mesma reserva do servico).
$composeIa = Join-Path $script:Infra '..\insider-ia-b3-ecossytem\compose.ia.yml'
$insightsIa = if (Test-Path $composeIa) { @('-f', $composeIa) + $insights } else { $insights }

$passos = [ordered]@{
    # Camada Base: um insight por pregao para cada ativo, sobre o preco
    # oficial e o lucro da CVM - sem BRAPI (D2, monitoramento em camadas).
    # --recuperar preenche todo pregao do COTAHIST sem insight ainda (limite
    # de 30 pregoes), nao so o ultimo - e o que torna um dia de maquina
    # desligada recuperavel em vez de virar buraco definitivo.
    'insights diarios (Base)'  = $insights + @('app.insights_diarios', '--recuperar')
    # Lote de opiniao (Gemini -> Ollama -> regra, ate LOTE_MAX_GEMINI ativos priorizados): sem
    # argumentos recupera sozinho os pregoes com insight sem opiniao (ultimos 5). Alimenta o
    # diario operacional (entrada e saida por sinal).
    'opiniao por horizonte'    = $insightsIa + @('app.opiniao.gerar')
    # Diario de sinais (paper trading): registrar sem --data ja recupera
    # sozinho todo pregao sem sinal (contrato ajustado pela Frente C em
    # 2026-09-28); avaliar julga os horizontes que venceram desde entao.
    'diario de sinais: registrar' = $insights + @('app.validacao.diario', 'registrar')
    'diario de sinais: avaliar'   = $insights + @('app.validacao.diario', 'avaliar')
    # Estratégias do simulador (SIM-INS-1): MOMENTO_PURO calcula retorno 12-1 meses
    # e grava em simulador_resultado para todos os ativos monitorados.
    'estratégias do simulador'   = $insights + @('app.simulador')
}
# Backtest semanal: o placar muda devagar e roda em segundos.
if ((Get-Date).DayOfWeek -eq 'Friday') {
    $passos['backtest'] = $insights + @('app.validacao.backtest')
}

# Mensal (LAC-INFRA-4): eventos corporativos e fatores do plano LAC, na
# referencia do primeiro pregao do mes. Roda quando o COTAHIST ja tem um
# pregao do mes corrente e fator_valor ainda nao tem referencia nele - nao
# depende de ligar a maquina num dia certo; o atraso se recupera sozinho.
# Eventos antes: os fatores ajustam o preco por eles (eventos = carga PARCIAL
# do ETL, abaixo; fatores = passo de insights, depois dela).
$sqlMensal = "SELECT COALESCE((SELECT MIN(data_pregao) FROM cotacao_b3_diaria " +
    "WHERE data_pregao >= DATE_FORMAT(CURDATE(), '%Y-%m-01')) > " +
    "COALESCE((SELECT MAX(data_referencia) FROM fator_valor), '1900-01-01'), 0);"
$mensal = (Executar-Sql $sqlMensal | Select-Object -First 1) -eq '1'
if ($mensal) {
    $mesAnterior = (Get-Date).AddMonths(-1).ToString('yyyy-MM')
    # --desde o mes anterior: refaz o mes passado (idempotente) caso a
    # rodada dele tenha sido antes do COTAHIST fechar o mes.
    $passos['fatores (mensal)'] = $insights + @('app.fatores', 'calcular', '--desde', $mesAnterior)
}

$falhas = @()

# Cargas do ETL antes dos insights: a ROTINA cobre comunicados (IPE), balancos
# (DFP), TTM, preco oficial (COTAHIST, com liquidez, prontidao e qualidade das
# opcoes), conciliacao brapi x B3, proventos (DVA) e checagens. Conciliacao com
# divergencia grave sai como FALHA da etapa, somando nas falhas sem abortar.
if ((Rodar-Carga 'cargas do ETL (rotina)' @{ tipo = 'ROTINA' }) -ne 0) {
    $falhas += 'cargas do ETL (rotina)'
}
if ($mensal -and (Rodar-Carga 'eventos corporativos (mensal)' @{ tipo = 'PARCIAL'; etapas = @('EVENTOS') }) -ne 0) {
    $falhas += 'eventos corporativos (mensal)'
}

foreach ($nome in $passos.Keys) {
    Escrever-Log $log "inicio: $nome"
    $r = Rodar-Compose $passos[$nome]
    $r.Saida | Where-Object { $_ -match 'concluid|ERROR|CRITICAL|Traceback|indisponivel|corrigida|Insights diarios|Diario|Avaliacao|conciliac|divergen|Eventos|Fatores' } |
        ForEach-Object { Escrever-Log $log "  $_" }
    if ($r.Codigo -ne 0) {
        Escrever-Log $log "FALHOU: $nome (codigo $($r.Codigo))"
        $falhas += $nome
    }
}

# Fichas do insider-ia (TASK-IA-12): cada tipo na sua cadencia (semanal, trimestral,
# anual), contada em etl_execucao; sem nada vencido o script so registra no log dele.
Escrever-Log $log 'inicio: fichas do insider-ia'
& (Join-Path $PSScriptRoot 'fichas-ia.ps1')
if ($LASTEXITCODE -ne 0) {
    Escrever-Log $log "FALHOU: fichas do insider-ia (codigo $LASTEXITCODE; ver fichas-ia.log)"
    $falhas += 'fichas do insider-ia'
}

# Diario operacional simulado (OPR-INFRA-3, Plano OPR): abre/fecha posicoes
# para cada pregao novo. Depende de preco oficial, insights e elegibilidade;
# so roda quando as cargas criticas do dia estao ok (saude dos dados verde).
# Nao duplica: diario.py verifica o ultimo pregao gravado e processa apenas
# os novos. Sai com codigo 0 quando nao ha nada a processar.
if ($falhas.Count -eq 0) {
    Escrever-Log $log 'inicio: diario operacional'
    $r = Rodar-Compose ($insights + @('app.operacional.diario'))
    $r.Saida | Where-Object { $_ -match 'Diario|operacional|pregoes|abertas|fechadas|pendentes|canceladas|patrimonio|ERROR|CRITICAL|Traceback|Exception' } |
        ForEach-Object { Escrever-Log $log "  $_" }
    if ($r.Codigo -ne 0) {
        Escrever-Log $log "FALHOU: diario operacional (codigo $($r.Codigo))"
        $falhas += 'diario operacional'
    }
} else {
    Escrever-Log $log "AVISO: diario operacional ignorado (saude vermelha: $($falhas -join ', '))"
    Registrar-Execucao 'DIARIO_OPERACIONAL' 'IGNORADO' 0 "saude vermelha: $($falhas -join ', ')"
}

# Alertas do operacional (OPR-INFRA-4): adapter fora dos servicos de dominio. Consome a fila
# sqs-eventos-operacionais e manda um resumo por rodada pelo Telegram (Enviar-Alerta, token so nas
# variaveis de ambiente do usuario). Sem Telegram configurado, nao consome nada.
Escrever-Log $log 'inicio: alertas do operacional'
& (Join-Path $PSScriptRoot 'alertas-operacionais.ps1')

if ($falhas.Count -gt 0) {
    $texto = "rotina da manha: falhas em $($falhas -join ', '). Log: $(Join-Path $script:PastaLocal $log)"
    if (-not (Enviar-Alerta $texto)) { Escrever-Log $log 'alerta nao enviado (Telegram nao configurado)' }
    exit 1
}
Escrever-Log $log 'fim: tudo certo'

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

. (Join-Path $PSScriptRoot 'comum.ps1')
$log = 'cargas-etl.log'

if (-not (Garantir-Stack)) {
    Escrever-Log $log 'FALHOU: stack nao ficou pronta; rotina abortada'
    exit 1
}

$ano = (Get-Date).Year
$etl = @('--profile', 'etl', 'run', '--rm', '--no-deps', 'etl-fundamentos-cvm')
$insights = @('run', '--rm', '--no-deps', 'gerar-insights', 'python', '-m')

$passos = [ordered]@{
    'comunicados (IPE)'        = $etl + @('--comunicados')
    # Balancos da camada Base inteira (universo liquido + cadastrados).
    'fundamentos (DFP)'        = $etl + @('--ano', "$($ano - 1)", '--ano', "$ano", '--universo-backtest')
    'ultimos 12 meses (TTM)'   = $etl + @('--ttm', '--ano', "$ano", '--universo-backtest')
    'preco oficial (COTAHIST)' = $etl + @('--cotahist', '--ano', "$ano")
    # Conciliacao brapi x COTAHIST (D4/C3): le vw_conciliacao_preco (V15) e
    # registra CONCILIACAO_BRAPI_B3 em etl_execucao. Sai 3 quando ha
    # divergencia grave - nao aborta a rotina (o alerta fica no proprio
    # etl_execucao/saude dos dados), so soma nas falhas reportadas no fim.
    'conciliacao brapi x B3'   = $etl + @('--conciliar')
    # Camada Base: um insight por pregao para cada ativo, sobre o preco
    # oficial e o lucro da CVM - sem BRAPI (D2, monitoramento em camadas).
    # --recuperar preenche todo pregao do COTAHIST sem insight ainda (limite
    # de 30 pregoes), nao so o ultimo - e o que torna um dia de maquina
    # desligada recuperavel em vez de virar buraco definitivo.
    'insights diarios (Base)'  = $insights + @('app.insights_diarios', '--recuperar')
    # Diario de sinais (paper trading): registrar sem --data ja recupera
    # sozinho todo pregao sem sinal (contrato ajustado pela Frente C em
    # 2026-09-28); avaliar julga os horizontes que venceram desde entao.
    'diario de sinais: registrar' = $insights + @('app.validacao.diario', 'registrar')
    'diario de sinais: avaliar'   = $insights + @('app.validacao.diario', 'avaliar')
}
# Backtest semanal: o placar muda devagar e roda em segundos.
if ((Get-Date).DayOfWeek -eq 'Friday') {
    $passos['backtest'] = $insights + @('app.validacao.backtest')
}

# Mensal (LAC-INFRA-4): eventos corporativos e fatores do plano LAC, na
# referencia do primeiro pregao do mes. Roda quando o COTAHIST ja tem um
# pregao do mes corrente e fator_valor ainda nao tem referencia nele - nao
# depende de ligar a maquina num dia certo; o atraso se recupera sozinho.
# Eventos antes: os fatores ajustam o preco por eles. Requer as imagens
# com --eventos-corporativos (ETL) e app.fatores (insights) - T-INFRA-03.
$sqlMensal = "SELECT COALESCE((SELECT MIN(data_pregao) FROM cotacao_b3_diaria " +
    "WHERE data_pregao >= DATE_FORMAT(CURDATE(), '%Y-%m-01')) > " +
    "COALESCE((SELECT MAX(data_referencia) FROM fator_valor), '1900-01-01'), 0);"
if ((Executar-Sql $sqlMensal | Select-Object -First 1) -eq '1') {
    $mesAnterior = (Get-Date).AddMonths(-1).ToString('yyyy-MM')
    $passos['eventos corporativos'] = $etl + @('--eventos-corporativos')
    # --desde o mes anterior: refaz o mes passado (idempotente) caso a
    # rodada dele tenha sido antes do COTAHIST fechar o mes.
    $passos['fatores (mensal)'] = $insights + @('app.fatores', 'calcular', '--desde', $mesAnterior)
}

$falhas = @()
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

if ($falhas.Count -gt 0) {
    $texto = "rotina da manha: falhas em $($falhas -join ', '). Log: $(Join-Path $script:PastaLocal $log)"
    if (-not (Enviar-Alerta $texto)) { Escrever-Log $log 'alerta nao enviado (Telegram nao configurado)' }
    exit 1
}
Escrever-Log $log 'fim: tudo certo'

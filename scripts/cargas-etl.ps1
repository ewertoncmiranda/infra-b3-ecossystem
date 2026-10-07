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

$falhas = @()
foreach ($nome in $passos.Keys) {
    Escrever-Log $log "inicio: $nome"
    $r = Rodar-Compose $passos[$nome]
    $r.Saida | Where-Object { $_ -match 'concluid|ERROR|CRITICAL|Traceback|indisponivel|corrigida|Insights diarios|Diario|Avaliacao|conciliac|divergen' } |
        ForEach-Object { Escrever-Log $log "  $_" }
    if ($r.Codigo -ne 0) {
        Escrever-Log $log "FALHOU: $nome (codigo $($r.Codigo))"
        $falhas += $nome
    }
}

if ($falhas.Count -gt 0) {
    $texto = "rotina da manha: falhas em $($falhas -join ', '). Log: $(Join-Path $script:PastaLocal $log)"
    if (-not (Enviar-Alerta $texto)) { Escrever-Log $log 'alerta nao enviado (Telegram nao configurado)' }
    exit 1
}
Escrever-Log $log 'fim: tudo certo'

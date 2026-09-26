# Cargas do ETL (CVM e B3) e backtest semanal. Feito para o Agendador de
# Tarefas do Windows, dias uteis as 20h (depois do diario de sinais das 19h).
# Registrar: scripts\registrar-rotinas.ps1. Log: %LOCALAPPDATA%\b3-ecossistema\cargas-etl.log
#
# Cada carga compara o ETag antes de baixar: arquivo sem novidade custa uma
# requisicao HEAD. Com a CVM fora do ar, o ETL segue com o cache e avisa.

. (Join-Path $PSScriptRoot 'comum.ps1')
$log = 'cargas-etl.log'
$ano = (Get-Date).Year
$etl = @('--profile', 'etl', 'run', '--rm', '--no-deps', 'etl-fundamentos-cvm')

$passos = [ordered]@{
    'comunicados (IPE)'        = $etl + @('--comunicados')
    'fundamentos (DFP)'        = $etl + @('--ano', "$($ano - 1)", '--ano', "$ano")
    'ultimos 12 meses (TTM)'   = $etl + @('--ttm', '--ano', "$ano")
    'preco oficial (COTAHIST)' = $etl + @('--cotahist', '--ano', "$ano")
}
# Backtest semanal: o placar muda devagar e roda em segundos.
if ((Get-Date).DayOfWeek -eq 'Friday') {
    $passos['backtest'] = @('run', '--rm', '--no-deps', 'gerar-insights', 'python', '-m', 'app.validacao.backtest')
}

$falhas = @()
foreach ($nome in $passos.Keys) {
    Escrever-Log $log "inicio: $nome"
    $r = Rodar-Compose $passos[$nome]
    $r.Saida | Where-Object { $_ -match 'concluid|ERROR|CRITICAL|Traceback|indisponivel|corrigida' } |
        ForEach-Object { Escrever-Log $log "  $_" }
    if ($r.Codigo -ne 0) {
        Escrever-Log $log "FALHOU: $nome (codigo $($r.Codigo))"
        $falhas += $nome
    }
}

if ($falhas.Count -gt 0) {
    $texto = "cargas do ETL falharam: $($falhas -join ', '). Log: $env:LOCALAPPDATA\b3-ecossistema\$log"
    if (-not (Enviar-Alerta $texto)) { Escrever-Log $log 'alerta nao enviado (Telegram nao configurado)' }
    exit 1
}
Escrever-Log $log 'fim: tudo certo'

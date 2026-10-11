# Alertas do operacional simulado (OPR-INFRA-4, Plano OPR). Adapter: le a fila
# sqs-eventos-operacionais (eventos operacional.*.v1 publicados pelo diario do gerar-insights)
# e manda UMA mensagem por rodada pelo Telegram (Enviar-Alerta do comum.ps1). Nenhum servico de
# dominio conhece o token: ele fica so nas variaveis de ambiente do usuario do Windows
# (TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID).
#
# Etapa da rotina da manha (cargas-etl.ps1), sem agendamento proprio. Regras:
# - Telegram nao configurado: nao consome a fila (as mensagens expiram pela retencao da fila);
# - envio falhou: nao apaga as mensagens (voltam a fila depois do visibility timeout);
# - fila ainda nao provisionada (imagem antiga do provisionador): registra e sai sem erro.
# Paper trading: o texto sempre diz que e simulado.

. (Join-Path $PSScriptRoot 'comum.ps1')
$log = 'alertas-operacionais.log'
$fila = 'sqs-eventos-operacionais'
$maximoPorRodada = 100

function Sqs([string[]]$Argumentos) {
    $saida = & docker exec localstack awslocal sqs @Argumentos --output json 2>&1
    return @{ Codigo = $LASTEXITCODE; Saida = ($saida -join "`n") }
}

if (-not [Environment]::GetEnvironmentVariable('TELEGRAM_BOT_TOKEN', 'User') -or
    -not [Environment]::GetEnvironmentVariable('TELEGRAM_CHAT_ID', 'User')) {
    Escrever-Log $log 'Telegram nao configurado: fila nao consumida'
    exit 0
}

$r = Sqs @('get-queue-url', '--queue-name', $fila)
if ($r.Codigo -ne 0) {
    Escrever-Log $log "fila $fila indisponivel (provisionador sem a OPR-INS-7?): $($r.Saida)"
    exit 0
}
$url = ($r.Saida | ConvertFrom-Json).QueueUrl

# Le em lotes de 10 ate esvaziar (ou atingir o maximo da rodada).
$mensagens = @()
while ($mensagens.Count -lt $maximoPorRodada) {
    $r = Sqs @('receive-message', '--queue-url', $url, '--max-number-of-messages', '10',
               '--wait-time-seconds', '1', '--visibility-timeout', '120')
    if ($r.Codigo -ne 0 -or -not $r.Saida.Trim()) { break }
    $lote = ($r.Saida | ConvertFrom-Json).Messages
    if (-not $lote) { break }
    $mensagens += $lote
}
if ($mensagens.Count -eq 0) {
    Escrever-Log $log 'sem eventos novos'
    exit 0
}

function Pct($valor) { if ($null -eq $valor) { 'n/d' } else { '{0:+0.00;-0.00}%' -f ([double]$valor * 100) } }

$eventos = $mensagens | ForEach-Object { $_.Body | ConvertFrom-Json }
$diarios = $eventos | Where-Object { $_.evento -eq 'operacional.diario-avaliado.v1' } | Sort-Object dataPregao
$abertas = $eventos | Where-Object { $_.evento -eq 'operacional.posicao-aberta.v1' }
$fechadas = $eventos | Where-Object { $_.evento -eq 'operacional.posicao-fechada.v1' }
$riscos = $eventos | Where-Object { $_.evento -eq 'operacional.alerta-risco.v1' }

$linhas = @('[SIMULADO] operacional (paper trading, nao e recomendacao)')
$ultimo = $diarios | Select-Object -Last 1
if ($ultimo) {
    $d = $ultimo.dados
    $linhas += ("Pregao {0}: patrimonio R$ {1:N2} | acumulado {2} | CDI liq. {3} | excesso {4} | drawdown max {5} | status {6}" -f
        $ultimo.dataPregao, [double]$d.patrimonio, (Pct $d.retorno_liquido_acumulado), (Pct $d.cdi_liquido_ir_acumulado),
        (Pct $d.excesso_sobre_cdi_liquido), (Pct $d.drawdown_maximo), $d.status_sistema)
}
foreach ($dia in $diarios) {
    if ($dia.dados.status_anterior -and $dia.dados.status_anterior -ne $dia.dados.status_sistema) {
        $linhas += "MUDOU DE STATUS em $($dia.dataPregao): $($dia.dados.status_anterior) -> $($dia.dados.status_sistema)"
    }
}
if ($abertas) {
    $linhas += "Abertas ($(@($abertas).Count)): " + (($abertas | ForEach-Object {
        "{0} {1} a R$ {2:N2}" -f $_.dados.simbolo, $_.dados.quantidade, [double]$_.dados.preco_entrada }) -join '; ')
}
if ($fechadas) {
    $linhas += "Fechadas ($(@($fechadas).Count)): " + (($fechadas | ForEach-Object {
        "{0} {1} R$ {2:N2}" -f $_.dados.simbolo, $_.dados.motivo_saida, [double]$_.dados.resultado_pos_custos }) -join '; ')
}
foreach ($alerta in $riscos) {
    $linhas += "ALERTA DE RISCO $($alerta.dataPregao): " + ($alerta.dados | ConvertTo-Json -Compress -Depth 4)
}

$texto = $linhas -join "`n"
if (-not (Enviar-Alerta $texto)) {
    Escrever-Log $log "envio falhou: $($mensagens.Count) eventos voltam para a fila"
    exit 1
}
foreach ($m in $mensagens) {
    Sqs @('delete-message', '--queue-url', $url, '--receipt-handle', $m.ReceiptHandle) | Out-Null
}
Escrever-Log $log "enviado: $($mensagens.Count) eventos ($(@($diarios).Count) diarios, $(@($abertas).Count) abertas, $(@($fechadas).Count) fechadas, $(@($riscos).Count) riscos)"
exit 0

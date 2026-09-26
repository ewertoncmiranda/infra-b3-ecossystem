# Diario de sinais (paper trading): registra o sinal do pregao e avalia os
# horizontes que venceram. Feito para o Agendador de Tarefas do Windows, todo
# dia util depois do fechamento da B3 (sugestao: 19h, com folga para o gestor
# gravar o candle do dia).
#
# Ativar (uma vez, num PowerShell comum):
#   schtasks /Create /TN "B3 - Diario de sinais" /SC WEEKLY /D MON,TUE,WED,THU,FRI /ST 19:00 `
#     /TR "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\User\projetos\infra-b3-ecossytem\scripts\diario-de-sinais.ps1"
#
# Desativar:
#   schtasks /Delete /TN "B3 - Diario de sinais" /F
#
# Log: %LOCALAPPDATA%\b3-ecossistema\diario-de-sinais.log
#
# Feriado nao precisa de tratamento: sem candle no dia, o registrar nao grava
# nada. Dia perdido (maquina desligada) se recupera rodando com --data:
#   docker compose -f docker-compose-local.yml run --rm --no-deps gerar-insights `
#     python -m app.validacao.diario registrar --data 2026-09-28

# 'Continue', e nao 'Stop': o docker compose escreve o progresso ("Container
# ... Creating") no stderr, e no Windows PowerShell 5.1 cada linha de stderr
# de um executavel vira ErrorRecord - com 'Stop' o script abortaria na
# primeira. A falha real e detectada pelo codigo de saida ($LASTEXITCODE).
$ErrorActionPreference = 'Continue'
$infra = Split-Path -Parent $PSScriptRoot
# Fora de infra-b3-ecossytem\logs de proposito: essa pasta e montada no
# Logstash, que mantem os *.log abertos (no Windows isso bloqueia a escrita)
# e tentaria ler este texto puro como JSON.
$log = Join-Path $env:LOCALAPPDATA 'b3-ecossistema\diario-de-sinais.log'
New-Item -ItemType Directory -Force -Path (Split-Path $log) -ErrorAction Stop | Out-Null

Set-Location $infra
$falhou = $false
foreach ($comando in @('registrar', 'avaliar')) {
    $inicio = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $log -Value "[$inicio] diario $comando"
    $saida = docker compose -f docker-compose-local.yml run --rm --no-deps gerar-insights `
        python -m app.validacao.diario $comando 2>&1 | ForEach-Object { "$_" }
    $codigo = $LASTEXITCODE
    $saida | Where-Object { $_ -match 'Diario|Avaliacao|Error|Traceback|Exception' } |
        ForEach-Object { Add-Content -Path $log -Value $_ }
    if ($codigo -ne 0) {
        Add-Content -Path $log -Value "[$inicio] FALHOU diario $comando (codigo $codigo)"
        $falhou = $true
    }
}
# Codigo de saida != 0 aparece como falha no Agendador de Tarefas.
if ($falhou) { exit 1 }

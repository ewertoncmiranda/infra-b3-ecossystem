# Registra (ou atualiza) as rotinas no Agendador de Tarefas do Windows.
# Rodar uma vez, num PowerShell comum (sem administrador):
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\registrar-rotinas.ps1
#
#   B3 - Diario de sinais   dias uteis 19:00  registra e avalia os sinais
#   B3 - Cargas ETL         dias uteis 20:00  CVM (IPE, DFP, TTM), COTAHIST; backtest as sextas
#   B3 - Backup MySQL       todo dia   12:30  dump + restauracao testada (horario em que o PC costuma estar ligado)
#
# /F sobrescreve a tarefa existente. Para remover:  schtasks /Delete /TN "<nome>" /F
# Maquina desligada no horario: a tarefa nao roda; a aba Avaliacao > Saude dos
# dados mostra a fonte ATRASADA, e rodar o .ps1 a mao recupera.

$pasta = $PSScriptRoot
$rotinas = @(
    @{ Nome = 'B3 - Diario de sinais'; Script = 'diario-de-sinais.ps1'; Args = @('/SC', 'WEEKLY', '/D', 'MON,TUE,WED,THU,FRI', '/ST', '19:00') },
    @{ Nome = 'B3 - Cargas ETL'; Script = 'cargas-etl.ps1'; Args = @('/SC', 'WEEKLY', '/D', 'MON,TUE,WED,THU,FRI', '/ST', '20:00') },
    @{ Nome = 'B3 - Backup MySQL'; Script = 'backup-mysql.ps1'; Args = @('/SC', 'DAILY', '/ST', '12:30') }
)
foreach ($r in $rotinas) {
    $comando = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $pasta $r.Script)`""
    schtasks /Create /TN $r.Nome /TR $comando @($r.Args) /F | Out-Null
    if ($LASTEXITCODE -eq 0) { "ok: $($r.Nome)" } else { "FALHOU: $($r.Nome)" }
}
schtasks /Query /FO TABLE /TN 'B3 - Diario de sinais'
schtasks /Query /FO TABLE /TN 'B3 - Cargas ETL'
schtasks /Query /FO TABLE /TN 'B3 - Backup MySQL'

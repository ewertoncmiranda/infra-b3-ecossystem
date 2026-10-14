# Registra (ou atualiza) as rotinas no Agendador de Tarefas do Windows.
# Rodar uma vez, num PowerShell comum (sem administrador), FORA do app Claude
# (TASK-E20: o ambiente do app nega o gatilho de logon):
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\registrar-rotinas.ps1
#
#   B3 - Rotina da manha   dias uteis 07:00 + ao logon (+5 min)   IPE, DFP, TTM,
#                          COTAHIST, conciliacao brapi x B3, insights e diario de
#                          sinais (com recuperacao de pregoes perdidos), backtest
#                          as sextas
#   B3 - Backup MySQL      todo dia 12:30     dump + restauracao testada, seguido
#                          de uma segunda passada da rotina da manha
#
# As duas com "executar assim que possivel" (StartWhenAvailable): PC desligado
# no horario (07:00/12:30) roda ao ligar, em vez de perder o dia (ISS-E15:
# 2026-10-02, 10-06 e 10-07, resultado 0x800710E0). O gatilho de logon cobre
# tambem o PC que foi ligado sem ter passado pelas 07:00 do dia. Rodar duas
# vezes no mesmo dia e inofensivo: cada passo compara o ETag e e idempotente;
# uma execucao em andamento nao e duplicada (MultipleInstances IgnoreNew).
#
# Para remover:  Unregister-ScheduledTask -TaskName "<nome>" -Confirm:$false

$ErrorActionPreference = 'Stop'
$pasta = $PSScriptRoot
$usuario = "$env:USERDOMAIN\$env:USERNAME"

function Acao([string]$Script) {
    New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $pasta $Script)`""
}

function Configuracao {
    # Sem bateria como impeditivo: notebook na tomada ou nao, a rotina roda.
    New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Hours 2) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
}

function Registrar([string]$Nome, [string]$Script, $Gatilhos) {
    try {
        Register-ScheduledTask -TaskName $Nome -Action (Acao $Script) -Trigger $Gatilhos `
            -Settings (Configuracao) -User $usuario -Force | Out-Null
        "ok: $Nome"
        return $true
    } catch {
        "FALHOU: $Nome - $($_.Exception.Message)"
        return $false
    }
}

$diasUteis = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday, Tuesday, Wednesday, Thursday, Friday -At 07:00
$aoLogon = New-ScheduledTaskTrigger -AtLogOn -User $usuario
$aoLogon.Delay = 'PT5M'

# Primeiro com o gatilho de logon; se o ambiente negar (como o sandbox do app
# Claude), registra so o horario - o StartWhenAvailable ja recupera o dia.
if (-not (Registrar 'B3 - Rotina da manha' 'cargas-etl.ps1' @($diasUteis, $aoLogon))) {
    "tentando sem o gatilho de logon..."
    if (Registrar 'B3 - Rotina da manha' 'cargas-etl.ps1' @($diasUteis)) {
        "ATENCAO: sem gatilho de logon (ambiente negou); StartWhenAvailable cobre o PC desligado as 07:00"
    }
}

Registrar 'B3 - Backup MySQL' 'backup-mysql.ps1' @(New-ScheduledTaskTrigger -Daily -At 12:30) | Out-Null

# Aposentadas (D1): dependiam da maquina ligada a noite; viravam carga perdida
# nos dias em que ela desligava antes de 20:00/21:30. A "Rotina da manha" ja
# incorpora o diario de sinais (registrar + avaliar).
foreach ($nome in @('B3 - Cargas ETL', 'B3 - Diario de sinais', 'B3 - Rotina da manha (logon)')) {
    if (Get-ScheduledTask -TaskName $nome -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $nome -Confirm:$false
        "removida: $nome"
    }
}

# Conferencia: gatilhos e "executar assim que possivel" de cada tarefa.
foreach ($nome in @('B3 - Rotina da manha', 'B3 - Backup MySQL')) {
    $t = Get-ScheduledTask -TaskName $nome -ErrorAction SilentlyContinue
    if (-not $t) { "AUSENTE: $nome"; continue }
    $gatilhos = ($t.Triggers | ForEach-Object { $_.CimClass.CimClassName -replace 'MSFT_Task|Trigger', '' }) -join ', '
    "{0}: gatilhos [{1}] | StartWhenAvailable={2} | proxima={3}" -f $nome, $gatilhos,
        $t.Settings.StartWhenAvailable, (Get-ScheduledTaskInfo -TaskName $nome).NextRunTime
}

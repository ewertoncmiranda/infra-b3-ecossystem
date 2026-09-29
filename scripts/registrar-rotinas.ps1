# Registra (ou atualiza) as rotinas no Agendador de Tarefas do Windows.
# Rodar uma vez, num PowerShell comum (sem administrador):
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\registrar-rotinas.ps1
#
#   B3 - Rotina da manha   dias uteis 07:00   IPE, DFP, TTM, COTAHIST, conciliacao
#                          brapi x B3, insights e diario de sinais (com recuperacao
#                          de pregoes perdidos), backtest as sextas
#   B3 - Backup MySQL      todo dia 12:30     dump + restauracao testada, seguido
#                          de uma segunda passada da rotina da manha
#
# Falta o gatilho de logon+5min do plano (D1: cobre a maquina desligada as 07:00) -
# este script roda num ambiente sandboxed que nega qualquer /SC ONLOGON (testado
# sem flag nenhuma, com /RU, com /IT: sempre "Acesso negado"; WEEKLY/DAILY
# funcionam normalmente no mesmo ambiente). O script registra o que da e avisa;
# o comentario logo abaixo de Registrar-RotinaSemanal tem o comando pra registrar
# o gatilho de logon manualmente, uma vez, fora deste sandbox.
#
# Para remover:  schtasks /Delete /TN "<nome>" /F

$pasta = $PSScriptRoot

function Registrar-RotinaSemanal([string]$Nome, [string]$Script) {
    $comando = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $pasta $Script)`""
    # Sem dois-pontos no nome da tarefa: schtasks devolve "Parametro incorreto"
    # com ele (achado testando - nao e o horario, e literalmente o nome).
    schtasks /Create /TN $Nome /TR $comando /SC WEEKLY /D MON,TUE,WED,THU,FRI /ST 07:00 /F | Out-Null
    return $LASTEXITCODE -eq 0
}

if (Registrar-RotinaSemanal 'B3 - Rotina da manha' 'cargas-etl.ps1') { "ok: B3 - Rotina da manha (07:00)" } else { "FALHOU: B3 - Rotina da manha (07:00)" }

# O gatilho de logon+5min (D1: cobre a maquina desligada as 07:00) NAO foi
# registrado - esta sessao roda num ambiente sandboxed que nega qualquer
# /SC ONLOGON (testado sem flag nenhuma, com /RU, com /IT: sempre "Acesso
# negado"; WEEKLY/DAILY funcionam normalmente no mesmo ambiente). Registre
# manualmente, uma vez, num PowerShell comum (fora deste sandbox):
#   schtasks /Create /TN "B3 - Rotina da manha (logon)" /SC ONLOGON /DELAY 0005:00 /F `
#     /TR 'powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\User\projetos\infra-b3-ecossytem\scripts\cargas-etl.ps1"'
"ATENCAO: gatilho de logon+5min nao registrado (ambiente nega /SC ONLOGON) - ver comentario acima para registrar manualmente"

$comandoBackup = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $pasta 'backup-mysql.ps1')`""
schtasks /Create /TN 'B3 - Backup MySQL' /TR $comandoBackup /SC DAILY /ST 12:30 /F | Out-Null
if ($LASTEXITCODE -eq 0) { "ok: B3 - Backup MySQL" } else { "FALHOU: B3 - Backup MySQL" }

# Aposentadas (D1): dependiam da maquina ligada a noite; viravam carga perdida
# nos dias em que ela desligava antes de 20:00/21:30. A "Rotina da manha" ja
# incorpora o diario de sinais (registrar + avaliar).
foreach ($nome in @('B3 - Cargas ETL', 'B3 - Diario de sinais')) {
    $existe = Get-ScheduledTask -TaskName $nome -ErrorAction SilentlyContinue
    if ($existe) {
        schtasks /Delete /TN $nome /F | Out-Null
        if ($LASTEXITCODE -eq 0) { "removida: $nome" } else { "FALHOU ao remover: $nome" }
    }
}

schtasks /Query /FO TABLE /TN 'B3 - Rotina da manha'
schtasks /Query /FO TABLE /TN 'B3 - Backup MySQL'

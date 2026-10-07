# Backfill historico do plano LAC (LAC-INFRA-3): COTAHIST, DFP, TTM por
# trimestre e proventos da DVA desde o inicio dos dados abertos.
# Rodar uma vez (ou de novo, sem medo: cada carga e upsert idempotente):
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\backfill-historico.ps1
#   ... -De 2009 -Ate 2015          # so um trecho
#
# Log: %USERPROFILE%\b3-ecossistema\backfill-historico.log; cada carga
# registra a propria linha em etl_execucao (fonte, competencia = ano).
#
# Ordem (dependencias):
#   1. COTAHIST  2009..Ate   define o universo liquido de cada ano
#   2. DFP       2010..Ate   precisa do universo; FCA/FRE comecam em 2010
#   3. TTM       2012..Ate   ITR aberto comeca em 2011, e o TTM do ano Y usa
#                            o ITR de Y-1 (e a DFP de Y-1 e de Y)
#   4. Proventos 2010..Ate   DVA da DFP e do ITR do mesmo ano
#   5. Eventos               desdobramento/grupamento/bonificacao (todos os
#                            anos; le o que 1 e 2 gravaram, sem download)
#   6. Fatores   2010-01..   gerar-insights, um calculo por mes (ajusta o
#                            preco pelos eventos de 5)
#
# Requer a imagem do ETL com LAC-ETL-3 (etl-fundamentos-cvm >= 1174020:
# TTM de todos os trimestres e --ttm --universo-backtest). Com a imagem
# antiga o TTM so grava o ultimo trimestre de cada ano.
#
# Download: ~90 MB por ano de COTAHIST e ~30 MB por ano de ITR, uma vez so -
# ficam no volume cvm_cache. Tempo tipico: ~2 min por ano por etapa.

param(
    [int]$De = 2009,
    [int]$Ate = ((Get-Date).Year)
)

. (Join-Path $PSScriptRoot 'comum.ps1')
$log = 'backfill-historico.log'

if (-not (Garantir-Stack)) {
    Escrever-Log $log 'FALHOU: stack nao ficou pronta; backfill abortado'
    exit 1
}

$etl = @('--profile', 'etl', 'run', '--rm', '--no-deps', 'etl-fundamentos-cvm')
$insights = @('run', '--rm', '--no-deps', 'gerar-insights', 'python', '-m')

function Anos([int]$Inicio) {
    $primeiro = [Math]::Max($De, $Inicio)
    if ($primeiro -gt $Ate) { return @() }
    $primeiro..$Ate | ForEach-Object { '--ano'; "$_" }
}

# --forcar: o ETag do ano pode ja estar registrado por uma carga anterior
# com outro universo ou com codigo antigo; o backfill reprocessa de proposito.
$etapas = [ordered]@{
    'COTAHIST'  = @('--cotahist') + (Anos 2009) + @('--forcar')
    'DFP'       = (Anos 2010) + @('--universo-backtest', '--forcar')
    'TTM'       = @('--ttm') + (Anos 2012) + @('--universo-backtest', '--forcar')
    'proventos' = @('--proventos') + (Anos 2010) + @('--universo-backtest')
    'eventos'   = @('--eventos-corporativos', '--ano', "$De", '--ano', "$Ate")
}

$falhas = @()
foreach ($nome in $etapas.Keys) {
    $argumentos = $etapas[$nome]
    if (-not ($argumentos -contains '--ano')) {
        Escrever-Log $log "pulado: $nome (nenhum ano entre $De e $Ate)"
        continue
    }
    Escrever-Log $log "inicio: $nome ($($argumentos -join ' '))"
    $r = Rodar-Compose ($etl + $argumentos)
    $r.Saida | Where-Object { $_ -match 'concluida|ERROR|CRITICAL|Traceback|Baixando' } |
        ForEach-Object { Escrever-Log $log "  $_" }
    if ($r.Codigo -ne 0) {
        Escrever-Log $log "FALHOU: $nome (codigo $($r.Codigo))"
        $falhas += $nome
    }
}

# Fatores por ultimo, no gerar-insights: dependem de tudo acima.
$desdeFatores = "$([Math]::Max($De, 2010))-01"
Escrever-Log $log "inicio: fatores desde $desdeFatores"
$r = Rodar-Compose ($insights + @('app.fatores', 'calcular', '--desde', $desdeFatores))
$r.Saida | Where-Object { $_ -match 'Fatores|ERROR|CRITICAL|Traceback' } | ForEach-Object { Escrever-Log $log "  $_" }
if ($r.Codigo -ne 0) {
    Escrever-Log $log "FALHOU: fatores (codigo $($r.Codigo))"
    $falhas += 'fatores'
}

if ($falhas.Count -gt 0) {
    Escrever-Log $log "fim com falhas: $($falhas -join ', ')"
    exit 1
}
Escrever-Log $log "fim: backfill $De-$Ate sem falhas"

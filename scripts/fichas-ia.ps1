# Fichas do insider-ia (TASK-IA-12, DEC-IA-01/05): regera as fichas de conhecimento
# do RAG na cadencia de cada tipo, como ultimo passo da rotina da manha.
#
#   evidencia   semanal      fatores e placar mudam com o fator mensal e o backtest
#   fundamentos semanal      glossario/formulas/estudos do painel (exportados pelo Node do host)
#   ativos+setores trimestral cadencia do ITR (entregas ate 45 dias apos o trimestre)
#   todas       anual        a partir de abril: DFP do ano fechado ja entregue (prazo 31/03)
#
# A cadencia sai de etl_execucao (ultima execucao com SUCESSO de cada fonte), entao
# maquina desligada no dia nao perde a rodada: ela acontece no proximo disparo.
# O gerador roda num container python descartavel na rede do MySQL (--network
# container:mysql) com o usuario so leitura leitor_ia, e grava em
# ..\insider-ia-b3-ecossytem\conhecimento so as fichas cujo hash mudou. As fichas
# ficam no git (DEC-IA-01): o commit e revisado por gente, e o servico so as ve na
# proxima imagem. Registra FICHAS_IA_* em etl_execucao (linhas = fichas regravadas).
#
# Uso avulso: scripts\fichas-ia.ps1 [-Forcar evidencia,fundamentos,ativos,todas]

param([string[]]$Forcar = @())

. (Join-Path $PSScriptRoot 'comum.ps1')
$log = 'fichas-ia.log'
$repo = Join-Path (Split-Path -Parent $script:Infra) 'insider-ia-b3-ecossytem'
$painel = Join-Path (Split-Path -Parent $script:Infra) 'painel-ativos-frontend'
$imagem = 'python:3.11-slim'

if (-not (Test-Path (Join-Path $repo 'app\fichas'))) {
    Escrever-Log $log "pulado: checkout do insider-ia nao encontrado em $repo"
    exit 0
}

# Dias desde a ultima execucao com SUCESSO da fonte ou da anual, que cobre todas (9999 se nunca rodou).
function Dias-Desde([string]$Fonte) {
    $dias = Executar-Sql ("SELECT COALESCE(DATEDIFF(CURDATE(), MAX(finalizado_em)), 9999) FROM etl_execucao " +
        "WHERE fonte IN ('$Fonte', 'FICHAS_IA_TODAS') AND status = 'SUCESSO';") | Select-Object -First 1
    if ("$dias" -match '^\d+$') { return [int]$dias }
    return 9999
}

$hoje = Get-Date
$ultimaAnual = Executar-Sql ("SELECT COALESCE(YEAR(MAX(finalizado_em)), 0) FROM etl_execucao " +
    "WHERE fonte = 'FICHAS_IA_TODAS' AND status = 'SUCESSO';") | Select-Object -First 1

# Ordem: a anual cobre todos os tipos; nao repete no mesmo dia o que ela ja fez.
$tarefas = [ordered]@{}
if ($Forcar -contains 'todas' -or ($hoje.Month -ge 4 -and "$ultimaAnual" -match '^\d+$' -and [int]$ultimaAnual -lt $hoje.Year)) {
    $tarefas['FICHAS_IA_TODAS'] = @('app.fichas', '--tipo', 'todas')
} else {
    if ($Forcar -contains 'ativos' -or (Dias-Desde 'FICHAS_IA_ATIVOS') -ge 91) {
        $tarefas['FICHAS_IA_ATIVOS'] = @('app.fichas', '--tipo', 'ativos')
        $tarefas['FICHAS_IA_SETORES'] = @('app.fichas', '--tipo', 'setores')
    }
    if ($Forcar -contains 'evidencia' -or (Dias-Desde 'FICHAS_IA_EVIDENCIA') -ge 7) {
        $tarefas['FICHAS_IA_EVIDENCIA'] = @('app.fichas', '--tipo', 'evidencia')
    }
}
if ($Forcar -contains 'fundamentos' -or (Dias-Desde 'FICHAS_IA_FUNDAMENTOS') -ge 7) {
    $tarefas['FICHAS_IA_FUNDAMENTOS'] = @('app.fichas.fundamentos', '--json', '/dados/painel.json')
}
if ($tarefas.Count -eq 0) {
    Escrever-Log $log 'nada a fazer: todas as fichas dentro da cadencia'
    exit 0
}

$senha = Garantir-UsuarioLeitura
if (-not $senha) {
    Escrever-Log $log 'FALHOU: MySQL nao respondeu ao criar/conferir o usuario leitor_ia'
    foreach ($fonte in $tarefas.Keys) { Registrar-Execucao $fonte 'ERRO' 0 'usuario leitor_ia indisponivel' }
    exit 1
}

# Fundamentos: o conteudo vem dos modulos JS do painel, exportados pelo Node do host.
$dados = $script:PastaLocal
if ($tarefas.Contains('FICHAS_IA_FUNDAMENTOS')) {
    $json = Join-Path $dados 'painel.json'
    $saida = & node (Join-Path $repo 'scripts\exportar_painel.mjs') $painel 2>&1
    if ($LASTEXITCODE -ne 0) {
        Escrever-Log $log "FALHOU: exportar o painel (node, codigo $LASTEXITCODE): $($saida | Select-Object -Last 1)"
        Registrar-Execucao 'FICHAS_IA_FUNDAMENTOS' 'ERRO' 0 'exportar_painel.mjs falhou (node ou checkout do painel)'
        $tarefas.Remove('FICHAS_IA_FUNDAMENTOS')
    } else {
        [IO.File]::WriteAllText($json, ($saida -join "`n"), (New-Object Text.UTF8Encoding($false)))
    }
}

# A senha vai pelo ambiente deste processo (`-e DB_PASS` sem valor), nunca na linha de comando.
$env:DB_PASS = $senha
$falhas = @()
foreach ($fonte in @($tarefas.Keys)) {
    $modulo = $tarefas[$fonte]
    Escrever-Log $log "inicio: $fonte ($($modulo -join ' '))"
    # pymysql e a unica dependencia do gerador (app/fichas/requirements.txt).
    $comando = "pip install -q --disable-pip-version-check -r app/fichas/requirements.txt && python -m $($modulo -join ' ')"
    $saida = & docker run --rm --network container:mysql `
        -v "${repo}:/repo" -v "${dados}:/dados:ro" -w /repo `
        -e DB_HOST=127.0.0.1 -e DB_PORT=3306 -e DB_USER=leitor_ia -e DB_PASS -e PYTHONDONTWRITEBYTECODE=1 `
        $imagem sh -c $comando 2>&1 | ForEach-Object { "$_" }
    $codigo = $LASTEXITCODE
    $saida | Where-Object { $_ -match 'fichas|ERROR|Traceback|concluid' } | ForEach-Object { Escrever-Log $log "  $_" }
    $gravadas = 0
    $ultima = $saida | Select-String -Pattern 'gravadas[=: ]+(\d+)' -AllMatches | Select-Object -Last 1
    if ($ultima) { $gravadas = [int]$ultima.Matches[-1].Groups[1].Value }
    if ($codigo -eq 0) {
        Registrar-Execucao $fonte 'SUCESSO' $gravadas
        Escrever-Log $log "ok: $fonte ($gravadas fichas regravadas)"
    } else {
        $erro = ($saida | Select-Object -Last 3) -join ' | '
        Registrar-Execucao $fonte 'ERRO' 0 $erro
        Escrever-Log $log "FALHOU: $fonte (codigo $codigo)"
        $falhas += $fonte
    }
}

Remove-Item Env:DB_PASS -ErrorAction SilentlyContinue

if ($falhas.Count -gt 0) {
    if (-not (Enviar-Alerta "fichas do insider-ia falharam: $($falhas -join ', '). Log: $(Join-Path $script:PastaLocal $log)")) {
        Escrever-Log $log 'alerta nao enviado (Telegram nao configurado)'
    }
    exit 1
}
Escrever-Log $log 'fim: fichas em dia (commit das mudancas em conhecimento/ fica para revisao)'

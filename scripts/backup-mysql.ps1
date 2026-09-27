# Backup diario do MySQL com restauracao TESTADA. Backup que nunca foi
# restaurado e so esperanca: todo backup e carregado num banco descartavel e
# conferido tabela a tabela antes de contar como sucesso.
#
# Registrar: scripts\registrar-rotinas.ps1
# Arquivos:  %LOCALAPPDATA%\b3-ecossistema\backups\minha_base_AAAA-MM-DD_HHmm.sql.gz (guarda 14)
# Log:       %LOCALAPPDATA%\b3-ecossistema\backup-mysql.log
#
# Restaurar de verdade (APAGA o estado atual do banco):
#   Get-Content -Encoding Byte -ReadCount 0 <arquivo> | docker exec -i mysql sh -c `
#     'gunzip | mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"'

. (Join-Path $PSScriptRoot 'comum.ps1')
$log = 'backup-mysql.log'
$pasta = Join-Path $script:PastaLocal 'backups'
New-Item -ItemType Directory -Force -Path $pasta | Out-Null
$arquivo = Join-Path $pasta ("minha_base_{0}.sql.gz" -f (Get-Date -Format 'yyyy-MM-dd_HHmm'))
$MANTER = 14

function Falhar([string]$motivo) {
    Escrever-Log $log "FALHOU: $motivo"
    Registrar-Execucao 'BACKUP_MYSQL' 'ERRO' 0 $motivo
    if (-not (Enviar-Alerta "backup do MySQL falhou: $motivo")) { Escrever-Log $log 'alerta nao enviado (Telegram nao configurado)' }
    exit 1
}

Escrever-Log $log 'inicio'
# 1. dump consistente (InnoDB) dentro do container, comprimido
docker exec mysql sh -c 'mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction --routines --triggers --no-tablespaces "$MYSQL_DATABASE" 2>/dev/null | gzip > /tmp/backup.sql.gz' | Out-Null
if ($LASTEXITCODE -ne 0) { Falhar 'mysqldump' }
docker cp mysql:/tmp/backup.sql.gz $arquivo | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $arquivo) -or (Get-Item $arquivo).Length -lt 1024) { Falhar 'copia do dump' }

# 2. restauracao num banco descartavel e conferencia de contagens
Executar-Sql 'DROP DATABASE IF EXISTS restauracao_teste; CREATE DATABASE restauracao_teste;' | Out-Null
docker exec mysql sh -c 'gunzip < /tmp/backup.sql.gz | mysql -uroot -p"$MYSQL_ROOT_PASSWORD" restauracao_teste 2>/dev/null'
if ($LASTEXITCODE -ne 0) { Falhar 'restauracao no banco de teste' }

# Tabelas que nao podem se perder; contagem exata (nao a estimativa do information_schema).
$tabelas = @('ativo_monitorado', 'insight_acao', 'sinal_diario', 'sinal_resultado', 'indicador_fundamentalista',
    'cotacao_b3_diaria', 'comunicado_cvm', 'indice_macro', 'ativo_identidade')
$divergentes = @()
foreach ($t in $tabelas) {
    $origem = [int](Executar-Sql "SELECT COUNT(*) FROM $t;")
    $copia = [int](Executar-Sql "SELECT COUNT(*) FROM restauracao_teste.$t;")
    # Rotina rodando durante o dump pode ter gravado linhas depois dele: a
    # copia pode ter MENOS, nunca mais, e nunca estar vazia se a origem nao esta.
    if ($copia -gt $origem -or ($origem -gt 0 -and $copia -eq 0)) {
        $divergentes += "$t (origem=$origem copia=$copia)"
    }
}
$totalTabelas = [int](Executar-Sql "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'restauracao_teste';")
Executar-Sql 'DROP DATABASE IF EXISTS restauracao_teste;' | Out-Null
docker exec mysql rm -f /tmp/backup.sql.gz
if ($divergentes.Count -gt 0) { Falhar ("restauracao divergente: " + ($divergentes -join '; ')) }

# 3. rotacao
Get-ChildItem $pasta -Filter 'minha_base_*.sql.gz' | Sort-Object Name -Descending | Select-Object -Skip $MANTER |
    Remove-Item -Force

$tamanho = [Math]::Round((Get-Item $arquivo).Length / 1MB, 1)
Registrar-Execucao 'BACKUP_MYSQL' 'SUCESSO' ([int]$totalTabelas)
Escrever-Log $log "ok: $arquivo ($tamanho MB, $totalTabelas tabelas restauradas e conferidas)"

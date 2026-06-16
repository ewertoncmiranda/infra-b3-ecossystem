#!/bin/bash
set -euo pipefail

# =============================================================================
# Ponto de Entrada - Provisionamento de Infraestrutura Terraform
# Objetivo: Inicializar, validar e aplicar configuração Terraform
# Ambiente: Integração LocalStack para desenvolvimento e testes
# =============================================================================

# Configuração de registro de eventos
LOG_PREFIX="[TERRAFORM-PROVISIONER]"
SUCCESS_MARK="[SUCESSO]"
ERROR_MARK="[ERRO]"
INFO_MARK="[INFO]"

# Códigos de cor para saída (pode ser desativado via TF_LOG_COLOR=false)
if [[ "${TF_LOG_COLOR:-true}" == "true" ]]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # Sem cor
else
    GREEN=''
    RED=''
    YELLOW=''
    NC=''
fi

# =============================================================================
# Função: log_info
# Objetivo: Imprimir mensagens informativas
# =============================================================================
log_info() {
    local message="$1"
    echo -e "${YELLOW}${LOG_PREFIX} ${INFO_MARK}${NC} ${message}"
}

# =============================================================================
# Função: log_success
# Objetivo: Imprimir mensagens de sucesso
# =============================================================================
log_success() {
    local message="$1"
    echo -e "${GREEN}${LOG_PREFIX} ${SUCCESS_MARK}${NC} ${message}"
}

# =============================================================================
# Função: log_error
# Objetivo: Imprimir mensagens de erro e encerrar execução
# =============================================================================
log_error() {
    local message="$1"
    echo -e "${RED}${LOG_PREFIX} ${ERROR_MARK}${NC} ${message}" >&2
    exit 1
}

# =============================================================================
# Fluxo Principal de Provisionamento
# =============================================================================

log_info "Iniciando fluxo de provisionamento Terraform"
log_info "Diretório de trabalho: $(pwd)"
log_info "Versão Terraform: $(terraform version -json | jq -r '.terraform_version')"

# Validar variáveis de ambiente obrigatórias
if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
    log_error "Variável de ambiente AWS_ACCESS_KEY_ID não está definida"
fi

if [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    log_error "Variável de ambiente AWS_SECRET_ACCESS_KEY não está definida"
fi

if [[ -z "${TF_VAR_aws_endpoint:-}" ]]; then
    log_error "Variável de ambiente TF_VAR_aws_endpoint não está definida"
fi

log_success "Variáveis de ambiente obrigatórias validadas"

# Inicializar backend Terraform e baixar provedores necessários
log_info "Inicializando configuração Terraform"
if ! terraform init; then
    log_error "Falha na inicialização Terraform"
fi
log_success "Inicialização Terraform concluída"

# Validar sintaxe da configuração Terraform e consistência
log_info "Validando configuração Terraform"
if ! terraform validate; then
    log_error "Falha na validação da configuração Terraform"
fi
log_success "Validação de configuração Terraform aprovada"

# Gerar e revisar plano de execução
log_info "Planejando mudanças de infraestrutura"
if ! terraform plan -out=tfplan -no-color; then
    log_error "Falha na geração do plano Terraform"
fi
log_success "Plano Terraform gerado com sucesso"

# Aplicar mudanças de infraestrutura
log_info "Aplicando configuração de infraestrutura"
if ! terraform apply -no-color -auto-approve tfplan; then
    log_error "Falha na operação de aplicação Terraform"
fi
log_success "Provisionamento de infraestrutura concluído com sucesso"

# Exibir saídas de recursos provisionados para integração com serviços dependentes
log_info "Gerando saídas de infraestrutura"
echo ""
log_info "Saídas de Infraestrutura:"
echo "---"
terraform output -json | jq '.' || log_info "Nenhuma saída definida na configuração"
echo "---"
echo ""

log_success "Fluxo de provisionamento Terraform concluído"

# Limpeza de arquivo de plano temporário
rm -f tfplan

exit 0


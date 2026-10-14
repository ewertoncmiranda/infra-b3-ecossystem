FROM hashicorp/terraform:1.9.8

LABEL maintainer="Equipe DevOps"
LABEL description="Provisionador de Infraestrutura como Código para Ecossistema de Monitoramento B3"
LABEL version="1.0.0"

# Instala CLI AWS e ferramentas complementares para capacidades de automação estendidas
RUN apk add --no-cache \
    aws-cli \
    bash \
    curl \
    jq

# Cria usuário não-raiz com direitos mínimos como melhor prática de segurança
RUN addgroup -g 1000 terraform && \
    adduser -D -u 1000 -G terraform terraform

# Copia arquivos de configuração Terraform para a imagem
COPY --chown=terraform:terraform . /infra

WORKDIR /infra

# Copia e define permissões executáveis para o script de ponto de entrada
COPY --chown=terraform:terraform entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && \
    chmod -R 755 /infra

# Estado do Terraform fica num volume montado aqui (compose). Criado com o dono
# certo para que um volume novo herde a permissao do usuario terraform.
RUN mkdir -p /estado && chown terraform:terraform /estado

USER terraform

# Inicializa Terraform para baixar e armazenar em cache os provedores
RUN terraform init -backend=false || true

ENTRYPOINT ["/entrypoint.sh"]


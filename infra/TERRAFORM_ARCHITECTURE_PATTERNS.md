# Padrões de Arquitetura - Terraform Infrastructure as Code

## 📋 Índice
1. [Padrões Aplicados](#padrões-aplicados)
2. [Princípios SOLID](#princípios-solid)
3. [Contexto de Arquitetura](#contexto-de-arquitetura)
4. [Estrutura de Diretórios](#estrutura-de-diretórios)
5. [Análise de Outputs](#análise-de-outputs)
6. [Guia de Uso](#guia-de-uso)

---

## Padrões Aplicados

### 1. **Modular Pattern**
**Descrição**: Segregação de recursos por tipo de serviço (SQS, S3, etc.)

**Benefícios**:
- ✅ Reutilização de código
- ✅ Facilita manutenção
- ✅ Escalabilidade
- ✅ Testabilidade independente

**Implementação**:
- Cada serviço AWS possui seu próprio diretório com `main.tf`, `variables.tf`, `outputs.tf`
- Módulos são invocados desde o `main.tf` raiz

**Exemplo**:
```
sqs/
├── main.tf (recursos SQS)
├── variables.tf (inputs do módulo)
└── outputs.tf (outputs do módulo)
```

---

### 2. **DRY (Don't Repeat Yourself)**
**Descrição**: Elimina duplicação através de variáveis locais e mapa de recursos

**Implementação**:
- `locals.tf`: Centraliza configurações comuns
- `for_each`: Provisiona múltiplos recursos com uma única definição
- Tags compartilhadas em `local.common_tags`

**Exemplo**:
```terraform
# Antes (repetitivo)
resource "aws_sqs_queue" "tratar_ativos" { ... }
resource "aws_sqs_queue" "iniciar_treinamento" { ... }

# Depois (DRY)
resource "aws_sqs_queue" "queues" {
  for_each = var.sqs_queues
  name = each.value.name
  ...
}
```

---

### 3. **Separation of Concerns (SoC)**
**Descrição**: Separação clara de responsabilidades entre arquivos

**Estrutura**:
| Arquivo | Responsabilidade |
|---------|-----------------|
| `versions.tf` | Configuração do Terraform e provider |
| `variables.tf` | Variáveis de entrada (interface pública) |
| `locals.tf` | Valores locais e padrões (uso interno) |
| `main.tf` | Orquestração de módulos |
| `outputs.tf` | Valores exportados |
| `***/main.tf` | Recursos específicos do módulo |

**Benefício**: Facilita navegação e compreensão do código

---

### 4. **Infrastructure as Code (IaC) Best Practices**

#### a) **Declarativo vs Imperativo**
- ✅ **Declarativo**: Especificar o estado desejado (Terraform)
- ❌ Imperativo: Listar passos para chegar ao estado

#### b) **Imutabilidade**
- Preferir criação de novos recursos vs modificação
- `force_destroy = true` em LocalStack apenas

#### c) **Versionamento**
- `terraform.tfstate` em `.gitignore`
- Configuração de variáveis em `*.tfvars` versionado

#### d) **Outputs Estruturados**
- Retornar mapas ao invés de valores únicos
- Facilita acesso e expansão futura

---

### 5. **Convention over Configuration**
**Descrição**: Padrões de nomenclatura consistentes

**Convenções**:
```hcl
# Nomenclatura
- Variáveis: snake_case
- Resources: aws_service_name
- Locals: descriptive_snake_case
- Outputs: plural_resource_names

# Tags obrigatórias
tags = {
  Environment = var.environment
  Project     = var.project_name
  ManagedBy   = "Terraform"
  CreatedAt   = timestamp()
}
```

---

### 6. **Single Responsibility Principle (SRP)**
**Descrição**: Cada arquivo tem uma única responsabilidade

**Exemplo**:
- `sqs/main.tf` → **Apenas** define recursos SQS
- `s3/main.tf` → **Apenas** define recursos S3
- `locals.tf` → **Apenas** valores locais compartilhados

---

## Princípios SOLID

### **S - Single Responsibility Principle**
Cada módulo é responsável por um tipo de recurso:
```
✅ sqs/ - Apenas SQS
✅ s3/  - Apenas S3
✅ locals.tf - Apenas variáveis locais
```

### **O - Open/Closed Principle**
Aberto para extensão (novos serviços), fechado para modificação:
```terraform
# Adicionar novo serviço:
module "dynamodb" {
  source = "./dynamodb"
  ...
}
# Sem alterar código existente ✅
```

### **L - Liskov Substitution Principle**
Módulos podem ser substituídos sem quebrar o contrato:
```terraform
# Interface consistente
# Todos módulos recebem: common_tags, environment
module "sqs" {
  common_tags = local.common_tags
  environment = var.environment
}
# Podem ser trocados sem quebra ✅
```

### **I - Interface Segregation Principle**
Variáveis específicas do módulo isoladas:
```
sqs/variables.tf → Apenas variáveis SQS
s3/variables.tf → Apenas variáveis S3
variables.tf (raiz) → Apenas variáveis globais
```

### **D - Dependency Inversion Principle**
Módulos dependem de abstrações (variáveis), não de implementações:
```terraform
# Módulo recebe valores, não conhece origem
variable "common_tags"
variable "sqs_queues"
# Desacoplado ✅
```

---

## Análise de Outputs

### **Por que Outputs?**

Outputs são a **interface pública** do Terraform. Permitem:
1. **Consumo por aplicações** (via `terraform output`)
2. **Integração com ferramentas** (Ansible, Docker Compose, etc)
3. **Exportação segura de valores** (sem expor state)
4. **Auditoria e compliance** (rastreabilidade)
5. **Scripts de automação** (CI/CD)

### **Outputs Implementados**

| Output | Uso | Necessário (LocalStack) | Necessário (AWS Real) |
|--------|-----|----------------------|----------------------|
| `sqs_queue_urls` | URLs para consumidores | ✅ Essencial | ✅ Essencial |
| `sqs_queue_arns` | Políticas IAM e cross-stack | ⚠️ Opcional | ✅ Essencial |
| `s3_bucket_names` | Upload/download de arquivos | ✅ Essencial | ✅ Essencial |
| `s3_bucket_arns` | Políticas de bucket e IAM | ⚠️ Opcional | ✅ Essencial |
| `s3_bucket_ids` | Referências internas | ❌ Redundante | ❌ Redundante |
| `infrastructure_summary` | Verificação/auditoria | ⚠️ Opcional | ⚠️ Opcional |

### **Exemplo de Consumo**

```bash
# Obter URL da fila SQS
QUEUE_URL=$(terraform output -raw 'sqs_queue_urls.tratar_ativos')
export SQS_QUEUE_URL=$QUEUE_URL

# Obter nome do bucket S3
BUCKET_NAME=$(terraform output -raw 's3_bucket_names.salvar_insights')
export S3_BUCKET=$BUCKET_NAME

# Verificar resumo da infraestrutura
terraform output infrastructure_summary
```

---

## Contexto de Arquitetura

### **Arquitetura em Camadas**

```
┌─────────────────────────────────────────┐
│  Camada de Orquestração (main.tf)       │
│  - Invoca módulos                       │
│  - Define dependências                  │
└─────────────────────────────────────────┘
                    ↑
┌─────────────────────────────────────────┐
│  Camada de Módulos (sqs/, s3/, etc)     │
│  - Recursos específicos                 │
│  - Lógica de provisionamento            │
└─────────────────────────────────────────┘
                    ↑
┌─────────────────────────────────────────┐
│  Camada de Configuração                 │
│  - variables.tf (entrada)               │
│  - locals.tf (compartilhado)            │
│  - outputs.tf (saída)                   │
└─────────────────────────────────────────┘
                    ↑
┌─────────────────────────────────────────┐
│  Camada de Provider                     │
│  - versions.tf (configuração AWS)       │
└─────────────────────────────────────────┘
```

### **Fluxo de Provisioning**

```
terraform plan
    ↓
variables.tf + locals.tf + main.tf
    ↓
Módulos (sqs, s3) resolvem for_each
    ↓
Provider AWS (LocalStack)
    ↓
Recursos criados
    ↓
outputs.tf retorna valores
```

---

## Estrutura de Diretórios

```
infra/
├── versions.tf                    # Provider e dependências
├── variables.tf                   # Variáveis globais
├── locals.tf                      # Variáveis locais compartilhadas
├── main.tf                        # Orquestrador principal
├── outputs.tf                     # Outputs consolidados
│
├── sqs/
│   ├── main.tf                   # Recursos SQS
│   ├── variables.tf              # Variáveis do módulo SQS
│   └── outputs.tf                # Outputs do módulo SQS
│
├── s3/
│   ├── main.tf                   # Recursos S3
│   ├── variables.tf              # Variáveis do módulo S3
│   └── outputs.tf                # Outputs do módulo S3
│
├── terraform.tfvars              # Valores padrão (versionado)
├── terraform.local.tfvars        # Sobrescritas locais (.gitignore)
├── .gitignore                     # Exclusões Git
└── ARCHITECTURE_PATTERNS.md       # Esta documentação
```

---

## Guia de Uso

### **Inicializar**
```bash
cd infra/
terraform init
```

### **Planejar (verificar mudanças)**
```bash
terraform plan
terraform plan -var-file="terraform.tfvars"
```

### **Aplicar (provisionar)**
```bash
terraform apply
terraform apply -var-file="terraform.tfvars"
```

### **Criar/Destruir seletivamente**
```bash
# Apenas SQS
terraform apply -var="create_s3=false"

# Apenas S3
terraform apply -var="create_sqs=false"

# Destruir tudo
terraform destroy
```

### **Outputs após provisioning**
```bash
terraform output sqs_queue_urls
terraform output s3_bucket_names
terraform output infrastructure_summary

# Obter valor específico
terraform output -raw 'sqs_queue_urls.tratar_ativos'
terraform output -raw 's3_bucket_names.salvar_insights'
```

### **Validação**
```bash
terraform validate
terraform fmt
terraform plan -json | jq
```

---

## Benefícios da Refatoração

| Aspecto | Antes | Depois |
|--------|-------|--------|
| **Linhas de código (main)** | 101 | ~40 (+ módulos) |
| **Duplicação** | Alta | Nenhuma (DRY) |
| **Reutilização** | Baixa | Alta (módulos) |
| **Manutenção** | Difícil | Fácil |
| **Testabilidade** | Acoplada | Independente |
| **Escalabilidade** | Limitada | Ilimitada |
| **Readability** | Monolítico | Claro |
| **Time onboarding** | Difícil | Fácil |

---

## Compatibilidade LocalStack

✅ **Mantém compatibilidade total**:
- Mesmos endpoints: `http://localhost:4566`
- Mesmas skip flags: `skip_credentials_validation`, etc
- Mesmos recursos: SQS, S3 (LocalStack suportados)
- Mesmos nomes: `tratar-ativos`, `sqs-iniciar-treinamento`, `bucket-salvar-insights`
- Mesmas tags: `Environment = "local"`, `Project = "devops-b3-monitoring"`

**Melhorias de segurança**:
- Credenciais separadas em `variables.tf` (melhor prática)
- `sensitive = true` em senhas (proteção de secrets)
- Namespacing por ambiente (local, dev, staging, prod)

---

## Próximas Melhorias (Opcional)

1. **Terraform Workspace** para ambientes
   ```bash
   terraform workspace new dev
   terraform workspace list
   ```

2. **Remote State** (S3 + DynamoDB para lock)
   ```hcl
   terraform {
     backend "s3" {
       bucket = "terraform-state"
       key    = "b3-monitoring/terraform.tfstate"
     }
   }
   ```

3. **Policy as Code** (Sentinel/OPA)
   - Validar políticas de segurança
   - Garantir compliance

4. **Testes** (Terratest)
   ```go
   // Testes em Go
   terraform.InitAndApply(t, tfOptions)
   terraform.Destroy(t, tfOptions)
   ```

5. **Validação** (tflint, pre-commit hooks)
   ```bash
   tflint --init
   tflint
   ```

6. **Módulos públicos** (Terraform Registry)
   - Compartilhar módulos entre times
   - https://registry.terraform.io/

---

## Referências

- [Terraform Best Practices](https://www.terraform.io/cloud/guides/recommended-practices)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [SOLID Principles](https://en.wikipedia.org/wiki/SOLID)
- [Infrastructure as Code](https://en.wikipedia.org/wiki/Infrastructure_as_code)
- [LocalStack Documentation](https://docs.localstack.cloud/)

---

## Suporte e Perguntas

Para dúvidas sobre a arquitetura ou padrões utilizados:
1. Verifique a seção relevante neste documento
2. Consulte os comentários nos arquivos `.tf`
3. Execute `terraform validate` para validar sintaxe
4. Use `terraform plan` para simular mudanças antes de aplicar

**Mantido por**: DevOps Team - B3 Monitoring Project
**Última atualização**: 2026-06-16


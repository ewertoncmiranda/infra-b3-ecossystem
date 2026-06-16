# Estratégia de Modularização de Imagem Docker

## Sumário Executivo

Este documento descreve a abordagem de modularização para containerizar os componentes de Infraestrutura como Código dentro do projeto Ecossistema de Monitoramento B3. A estratégia permite versionamento independente, implantação e gerenciamento de pipeline CI/CD para cada componente de infraestrutura, mantendo compatibilidade com framework de orquestração docker-compose existente.

## Objetivos de Negócio

1. **Isolamento de Componentes**: Separar provisionamento de infraestrutura de serviços aplicacionais no registro Docker Hub
2. **Escalabilidade**: Permitir reutilização de imagens de infraestrutura em múltiplos projetos
3. **Eficiência DevOps**: Implementar CI/CD automatizado para mudanças de infraestrutura
4. **Garantia de Qualidade**: Aplicar verificação de segurança e validação em tempo de construção
5. **Distribuição de Times**: Permitir times de infraestrutura e aplicação independentes

## Arquitetura Técnica

### Estado Atual

```
docker-compose.yml (orquestração monolítica)
  ├── localstack (serviço: simulação AWS)
  ├── terraform-provisioner (serviço: codificação infraestrutura)
  ├── mysql (serviço: persistência dados)
  ├── gestor-ativos-brutos (serviço: aplicação Java)
  └── gerar-insights (serviço: aplicação Python)
```

**Problema**: Terraform usa imagem genérica `hashicorp/terraform:latest`, sem controle de versionamento

### Estado Alvo

```
Registro Docker Hub (ewertonmiranda)
  ├── gestor-ativos-brutos:version        (serviço Java)
  ├── gerar-insights:version              (serviço Python)
  └── infra-b3-ecossystem:version         (serviço Infraestrutura)

docker-compose.yml (Orquestração)
  └── Referencia imagens Docker Hub (versionadas)
```

**Benefício**: Cada componente mantém timeline de implantação independente e pipeline CI/CD próprio

## Component Breakdown

### 1. Infrastructure Service: `ewertonmiranda/infra-b3-ecossystem`

**Responsibility**: Infrastructure provisioning via Terraform

**Contents**:
- Terraform CLI with configuration
- AWS CLI for utility operations
- Custom entrypoint script for provisioning workflow

**Versioning**: Semantic versioning (1.0.0, 1.0.1, 1.1.0)

**Triggers for New Release**:
- Changes to Terraform configuration (infra/*.tf)
- Updates to Dockerfile or entrypoint.sh
- Dependency updates (provider versions)

### 2. Application Services

**Existing**:
- `ewertonmiranda/gestor-ativos-brutos:latest`
- `ewertonmiranda/gerar-insights:latest`

**Independence**: Each service maintains separate repository and CI/CD pipeline

**Compatibility**: All services communicate via LocalStack (SQS) and MySQL

## File Structure

```
infra-b3-ecossytem/
├── infra/
│   ├── Dockerfile                    (Container definition)
│   ├── entrypoint.sh                 (Provisioning workflow)
│   ├── .dockerignore                 (Build optimization)
│   ├── terraform.tfvars              (Default variables)
│   ├── versions.tf                   (Provider specification)
│   ├── variables.tf                  (Input variables)
│   ├── locals.tf                     (Local values)
│   ├── main.tf                       (Module orchestration)
│   ├── outputs.tf                    (Output values)
│   ├── sqs/                          (SQS module)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── s3/                           (S3 module)
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
├── docker-compose.yml                (Service orchestration)
├── PUSH_INSTRUCTIONS.md              (Build/push procedures)
├── ARCHITECTURE_PATTERNS.md          (Infrastructure design)
├── MODULARIZATION_GUIDE.md           (This file)
└── .github/
    └── workflows/
        └── docker-build-infra.yml    (CI/CD automation)
```

## Docker Image Specifications

### Dockerfile Design Principles

1. **Minimal Base Image**: Use `hashicorp/terraform:latest` (Alpine-based, ~300MB)
2. **Security**: Non-root user (`terraform:1000`) runs container
3. **Optimization**: Multi-stage builds where applicable
4. **Reproducibility**: Pinned versions for all dependencies

### Image Composition

```
Base: hashicorp/terraform:latest
  ├── AWS CLI v2 (automation capabilities)
  ├── Bash shell (scripting support)
  ├── jq tool (JSON processing)
  ├── curl (HTTP operations)
  └── Non-root user (security hardening)

Application: Terraform Configuration
  ├── infra/
  ├── entrypoint.sh
  └── terraform.tfvars
```

### Image Properties

| Property | Value |
|----------|-------|
| **Registry** | docker.io |
| **Repository** | ewertonmiranda/infra-b3-ecossystem |
| **Architectures** | linux/amd64, linux/arm64 |
| **Size** | ~350 MB |
| **Built from** | hashicorp/terraform:latest |

## CI/CD Pipeline

### Workflow: `.github/workflows/docker-build-infra.yml`

**Trigger Events**:
- Push to `main` or `develop` branches (infra/ changes)
- Pull requests targeting release branches
- Manual dispatch via GitHub Actions

**Pipeline Stages**:

1. **Checkout**: Clone repository at current commit
2. **Setup**: Configure Docker Buildx for multi-platform builds
3. **Authentication**: Login to Docker Hub with credentials
4. **Validation**: Execute Terraform syntax and format checks
5. **Build**: Construct image using BuildKit (cached layers)
6. **Scan**: Trivy vulnerability assessment
7. **Publish**: Push to Docker Hub registry

### Tag Strategy

**Automatic Tag Generation**:

| Event | Tag Pattern | Example |
|-------|-------------|---------|
| Branch push | `{branch}` | `develop`, `main` |
| Semantic tag | `{version}` | `1.0.0`, `1.1.0` |
| Latest | `latest` | (main branch only) |
| SHA based | `{branch}-{sha}` | `main-a1b2c3d` |

### Secrets Configuration

**GitHub Repository Secrets** (required):

```
DOCKER_USERNAME = ewertonmiranda
DOCKER_PASSWORD = [Docker Hub PAT]
```

**Access Level**: Read/Write on Docker Hub account

## Integration with docker-compose

### Before Modularization

```yaml
terraform-provisioner:
  image: hashicorp/terraform:latest
  volumes:
    - ./infra:/infra
  working_dir: /infra
  entrypoint: /bin/sh -c "terraform init && terraform apply -auto-approve"
```

**Issues**:
- No versioning control
- Generic image (no infrastructure specifics)
- Entrypoint logic mixed in compose file

### After Modularization

```yaml
terraform-provisioner:
  image: ewertonmiranda/infra-b3-ecossystem:latest
  environment:
    - AWS_ACCESS_KEY_ID=test
    - AWS_SECRET_ACCESS_KEY=test
```

**Benefits**:
- Versioned image (full control)
- Specialized infrastructure image
- Logic encapsulated in container
- Simpler compose configuration

## Operational Procedures

### Local Development Workflow

```bash
# 1. Clone repository
git clone https://github.com/ewertonmiranda/infra-b3-ecossytem.git
cd infra-b3-ecossytem

# 2. Build infrastructure image locally
cd infra/
docker build -t ewertonmiranda/infra-b3-ecossystem:dev .

# 3. Test with docker-compose
cd ..
docker-compose up

# 4. Validate provisioning
docker-compose logs terraform-provisioner
```

### Production Deployment

```bash
# 1. Tag image with version
docker tag ewertonmiranda/infra-b3-ecossystem:dev \
  ewertonmiranda/infra-b3-ecossystem:1.0.0

# 2. Push to Docker Hub
docker push ewertonmiranda/infra-b3-ecossystem:1.0.0
docker push ewertonmiranda/infra-b3-ecossystem:latest

# 3. Update compose file reference (optional)
# - Uses 'latest' tag by default
# - Specific version: image: ewertonmiranda/infra-b3-ecossystem:1.0.0

# 4. Deploy
docker-compose pull
docker-compose up
```

## Security Considerations

### Image Security

1. **Base Image Scanning**: Trivy scans all pushed images
2. **Non-root Execution**: Container runs as `terraform` user
3. **Read-only Root**: Filesystem mounted read-only where applicable
4. **Minimal Attack Surface**: Only essential tools included

### Credential Management

1. **Environment Variables**: AWS credentials passed at runtime
2. **No Hardcoded Secrets**: Zero credentials in Dockerfile
3. **State File Protection**: External storage required (S3 backend)
4. **Secret Rotation**: Use docker secrets or external secret managers

### Terraform State

**Recommendation**: Configure remote backend for production

```hcl
terraform {
  backend "s3" {
    bucket         = "terraform-state-b3"
    key            = "infra/terraform.tfstate"
    region         = "sa-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

## Maintenance and Updates

### Dependency Updates

| Component | Frequency | Process |
|-----------|-----------|---------|
| Terraform | Monthly | Update hashicorp/terraform base image |
| AWS CLI | Quarterly | Update apk packages in Dockerfile |
| Alpine | Quarterly | Update base image digest |
| Custom code | On-demand | Terraform configuration changes |

### Versioning Policy

**Semantic Versioning**: MAJOR.MINOR.PATCH

- **MAJOR**: Breaking Terraform changes (resource deletion/modification)
- **MINOR**: Additive features (new modules, resources)
- **PATCH**: Bug fixes, documentation, non-breaking changes

**Example Timeline**:
```
v1.0.0  - Initial infrastructure release
v1.0.1  - Bug fix in S3 configuration
v1.1.0  - Add DynamoDB module
v2.0.0  - Restructure to multi-account architecture
```

## Troubleshooting

### Build Failures

**Scenario**: Docker build fails on Linux permissions

```bash
# Add current user to docker group
sudo usermod -aG docker $USER
newgrp docker
```

**Scenario**: Terraform validation fails in CI/CD

```bash
# Local validation before push
cd infra/
docker run --rm -v $(pwd):/working -w /working \
  hashicorp/terraform:latest \
  terraform validate
```

### Container Execution Issues

**Scenario**: Container exits immediately after start

```bash
# Check entrypoint logs
docker-compose logs terraform-provisioner

# Manual execution for debugging
docker run -it --rm \
  -e AWS_ACCESS_KEY_ID=test \
  -e AWS_SECRET_ACCESS_KEY=test \
  -e TF_VAR_aws_endpoint=http://host.docker.internal:4566 \
  ewertonmiranda/infra-b3-ecossystem:latest /bin/bash
```

## Scalability and Future Enhancements

### Phase 1 (Current)
- Single infrastructure image for LocalStack
- Basic Terraform modules (SQS, S3)
- Local docker-compose orchestration

### Phase 2 (Planned)
- Remote state backend (S3 + DynamoDB)
- Multi-environment support (dev/staging/prod)
- Additional AWS services (DynamoDB, Lambda, RDS)

### Phase 3 (Future)
- Kubernetes deployment
- Terraform Cloud/Enterprise integration
- Infrastructure policy enforcement (Sentinel)
- Automated testing framework (Terratest)

## Compliance and Best Practices

### Regulatory Considerations

1. **Audit Trail**: All infrastructure changes tracked via Git
2. **Access Control**: Docker Hub access controlled via credentials
3. **Image Scanning**: Security vulnerabilities detected at build time
4. **Documentation**: All procedures documented in dedicated guides

### Industry Standards

- **Infrastructure as Code**: IaC best practices via Terraform
- **Container Security**: Non-root user, minimal base image
- **CI/CD Automation**: GitHub Actions workflow standards
- **Semantic Versioning**: Industry-standard version numbering

## References

- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Terraform Documentation](https://www.terraform.io/docs)
- [HashiCorp Terraform Image](https://hub.docker.com/r/hashicorp/terraform)
- [GitHub Actions](https://docs.github.com/en/actions)
- [Docker Hub](https://hub.docker.com/)
- [ARCHITECTURE_PATTERNS.md](./infra/ARCHITECTURE_PATTERNS.md)
- [PUSH_INSTRUCTIONS.md](./PUSH_INSTRUCTIONS.md)

## Contact and Support

**DevOps Team**: Responsible for infrastructure container maintenance

**Repository**: https://github.com/ewertonmiranda/infra-b3-ecossytem

**Issues**: Report via GitHub Issues with `[INFRA]` tag

---

**Document Version**: 1.0.0
**Last Updated**: 2026-06-16
**Maintained by**: DevOps Team - B3 Monitoring Project


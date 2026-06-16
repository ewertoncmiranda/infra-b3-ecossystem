# B3 Monitoring Ecosystem - Infrastructure Repository

**Version**: 1.0.0  
**Status**: Active Development  
**Last Updated**: 2026-06-16

## Overview

This repository contains the Infrastructure as Code (IaC) provisioning for the B3 Monitoring Ecosystem project. It includes Terraform configurations for AWS resources running on LocalStack for local development and a modularized Docker image for containerized infrastructure deployment.

## Project Structure

```
infra-b3-ecossytem/
├── infra/                              # Terraform infrastructure code
│   ├── Dockerfile                      # Container definition for infrastructure
│   ├── entrypoint.sh                   # Provisioning workflow orchestration
│   ├── terraform.tfvars                # Default configuration values
│   ├── versions.tf                     # Provider specifications
│   ├── variables.tf                    # Input variables
│   ├── locals.tf                       # Local values and defaults
│   ├── main.tf                         # Module orchestration
│   ├── outputs.tf                      # Output values
│   ├── sqs/                            # SQS Queue module
│   └── s3/                             # S3 Bucket module
│
├── docker-compose.yml                  # Service orchestration
├── docker-compose-local.yml            # Local development variant
├── mysql-init/                         # Database initialization scripts
├── logs/                               # Application logs directory
│
├── ARCHITECTURE_PATTERNS.md            # Infrastructure design patterns
├── MODULARIZATION_GUIDE.md             # Docker containerization strategy
├── PUSH_INSTRUCTIONS.md                # Build and publish procedures
└── README.md                           # This file
```

## Quick Start

### Prerequisites

- Docker Desktop or Docker Engine with Compose support
- Git repository access
- (Optional) Terraform CLI for local validation

### Local Development

```bash
# Clone repository
git clone https://github.com/ewertonmiranda/infra-b3-ecossytem.git
cd infra-b3-ecossytem

# Launch complete ecosystem
docker-compose up -d

# Verify services status
docker-compose ps

# View provisioning logs
docker-compose logs terraform-provisioner

# Stop all services
docker-compose down
```

### Docker Compose Services

| Service | Image | Port | Purpose |
|---------|-------|------|---------|
| `localstack` | localstack/localstack:3.3 | 4566 | AWS service mocking |
| `terraform-provisioner` | ewertonmiranda/infra-b3-ecossystem:latest | - | Infrastructure provisioning |
| `mysql` | mysql:8.0 | 3305 | Data persistence |
| `gestor-ativos-brutos` | ewertonmiranda/gestor-ativos-brutos:latest | 8091 | Java backend service |
| `gerar-insights` | ewertonmiranda/gerar-insights:latest | 8080 | Python analytics service |

## Infrastructure Components

### SQS (Simple Queue Service)

**Module**: `infra/sqs/`  
**Resources**: Message queues for asynchronous processing

```
Configured Queues:
- tratar-ativos: Raw asset processing queue
- iniciar-treinamento: Model training initiation queue
```

### S3 (Simple Storage Service)

**Module**: `infra/s3/`  
**Resources**: Object storage for insights and artifacts

```
Configured Buckets:
- bucket-salvar-insights: Generated insights and analysis results
```

### Configuration Management

**Variables**: `infra/variables.tf`
**Local Defaults**: `infra/locals.tf`
**Override Values**: `infra/terraform.tfvars`

## Docker Image

### Infrastructure Container: `ewertonmiranda/infra-b3-ecossystem`

**Purpose**: Containerized Terraform provisioner  
**Registry**: Docker Hub  
**Architecture**: Multi-platform (AMD64, ARM64)

**Included Tools**:
- Terraform CLI
- AWS CLI v2
- Bash scripting support
- JSON processing (jq)

### Building Locally

```bash
cd infra/
docker build -t ewertonmiranda/infra-b3-ecossystem:dev .
```

### Pushing to Registry

Reference: [PUSH_INSTRUCTIONS.md](./PUSH_INSTRUCTIONS.md)

```bash
docker push ewertonmiranda/infra-b3-ecossystem:1.0.0
docker push ewertonmiranda/infra-b3-ecossystem:latest
```

## Documentation

### Architecture and Design

- **[ARCHITECTURE_PATTERNS.md](./infra/ARCHITECTURE_PATTERNS.md)**: Infrastructure design patterns, principles, and best practices
- **[MODULARIZATION_GUIDE.md](./MODULARIZATION_GUIDE.md)**: Docker containerization strategy and rationale
- **[PUSH_INSTRUCTIONS.md](./PUSH_INSTRUCTIONS.md)**: Build and publish procedures to Docker Hub

### Key Topics

| Document | Purpose |
|----------|---------|
| ARCHITECTURE_PATTERNS.md | IaC patterns, SOLID principles, module design |
| MODULARIZATION_GUIDE.md | Container strategy, CI/CD pipeline, scalability |
| PUSH_INSTRUCTIONS.md | Build procedures, troubleshooting, versioning |

## Terraform Operations

### Validation

```bash
cd infra/

# Syntax check
terraform validate

# Format check
terraform fmt -check -recursive
```

### Planning

```bash
terraform plan -var-file="terraform.tfvars"
```

### Provisioning

```bash
terraform apply -var-file="terraform.tfvars"
```

### Output Values

```bash
# All outputs
terraform output -json

# Specific output
terraform output sqs_queue_urls
terraform output s3_bucket_names
```

## Environment Variables

### Required (Runtime)

```bash
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test
AWS_DEFAULT_REGION=sa-east-1
TF_VAR_aws_endpoint=http://localstack:4566
```

### Optional

```bash
TF_LOG=INFO              # Terraform logging level
TF_LOG_COLOR=true        # Colored output (disable: false)
```

## CI/CD Pipeline

**Workflow**: `.github/workflows/docker-build-infra.yml`

**Triggers**:
- Push to `main` or `develop` branches (infra/ changes)
- Pull requests targeting release branches
- Manual dispatch via GitHub Actions

**Pipeline Steps**:
1. Checkout repository
2. Setup Docker Buildx
3. Validate Terraform configuration
4. Build Docker image
5. Scan for security vulnerabilities (Trivy)
6. Push to Docker Hub registry

**Required Secrets**:
- `DOCKER_USERNAME`: Docker Hub username
- `DOCKER_PASSWORD`: Docker Hub personal access token

## Security Considerations

### Image Security

- Non-root user execution (`terraform` user, UID 1000)
- Minimal base image (Alpine-based)
- Automated vulnerability scanning (Trivy)
- No hardcoded credentials

### Access Control

- GitHub Actions secrets management
- Docker Hub authentication required
- Cloud provider credentials via environment variables

### State Management

- LocalStack development: Local state files
- Production deployment: Remote backend recommended (S3 + DynamoDB)

### Credential Rotation

- LocalStack uses test credentials (`access_key: test`, `secret_key: test`)
- Production: Implement credential rotation policies
- Never commit credentials to repository

## Troubleshooting

### Common Issues

**Issue**: Terraform container fails to start

```bash
# Check container logs
docker-compose logs terraform-provisioner

# Verify LocalStack is healthy
docker-compose logs localstack

# Manual health check
docker run --rm ewertonmiranda/infra-b3-ecossystem:latest terraform version
```

**Issue**: SQS/S3 resources not created

```bash
# Verify LocalStack connectivity
docker exec localstack awslocal sqs list-queues
docker exec localstack awslocal s3 ls

# Check Terraform state
cd infra/
terraform show
```

**Issue**: Permission denied when building Docker image

```bash
# Add user to docker group (Linux)
sudo usermod -aG docker $USER
newgrp docker
```

## Maintenance

### Regular Tasks

- Monitor Terraform releases for updates
- Review AWS provider compatibility
- Update base images quarterly
- Audit security scanning results

### Update Procedures

```bash
# Update Terraform provider
cd infra/
terraform init -upgrade

# Update base Docker image
# Edit Dockerfile, update FROM line

# Rebuild and test locally
docker build -t ewertonmiranda/infra-b3-ecossystem:dev .
docker-compose up
```

## Versioning

**Strategy**: Semantic Versioning (MAJOR.MINOR.PATCH)

- **MAJOR**: Breaking infrastructure changes
- **MINOR**: Additive features (new modules/resources)
- **PATCH**: Bug fixes and non-breaking updates

**Image Tags**: `ewertonmiranda/infra-b3-ecossystem:1.0.0`

## References

- [Terraform Documentation](https://www.terraform.io/docs)
- [AWS LocalStack](https://docs.localstack.cloud/)
- [Docker Documentation](https://docs.docker.com/)
- [GitHub Actions](https://docs.github.com/en/actions)
- [HashiCorp Terraform Best Practices](https://www.terraform.io/cloud/guides/recommended-practices)

## Support and Contact

**Team**: DevOps - B3 Monitoring Project  
**Repository**: https://github.com/ewertonmiranda/infra-b3-ecossytem  
**Issues**: GitHub Issues with `[INFRA]` tag  
**Documentation**: See `ARCHITECTURE_PATTERNS.md`, `MODULARIZATION_GUIDE.md`, `PUSH_INSTRUCTIONS.md`

## License

[Specify license here]

---

**Document Version**: 1.0.0  
**Last Updated**: 2026-06-16  
**Maintained by**: DevOps Team

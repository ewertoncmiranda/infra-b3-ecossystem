# CARGA-INFRA-2 — IMPLEMENTADO (2026-10-18)

Entregue em `docker-compose.yml`:
- ETL sai do profile `etl`: `restart: unless-stopped`, `entrypoint: ["python", "-m", "app.servidor"]`, porta só em `127.0.0.1:8097` → 8080, health check em `GET /saude`, env `ETL_HTTP_PORT`, `ETL_TOKEN`, `ETL_VERSAO`.
- Gestor recebe `ETL_URL=http://etl-fundamentos-cvm:8080` e `ETL_TOKEN`.

Evidência: `docker compose -f docker-compose.yml config` válido.

Atenção:
- **Não mesclar/implantar antes da imagem do ETL com a CARGA-ETL-4** (`app.servidor`). O entrypoint é explícito de propósito: o ENTRYPOINT atual da imagem (`python main.py`) roda a carga completa de 5 anos e, com `restart`, rodaria em loop. Com a imagem antiga o container só falha ao subir, sem carregar nada.
- O `docker-compose-local.yml` (local, fora do git, com chaves) precisa da mesma mudança à mão quando o ETL tiver o servidor.

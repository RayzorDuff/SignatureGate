1) Initialize the signaturegate-postgres database with db/schema.sql

From the server where your docker compose runs (in the SignatureGate repo folder where your .env lives):

Confirm containers are up:

```bash
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

2) Load the schema into Postgres (recommended: execute inside the container):

```bash
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/schema.sql
```

3) Verify tables exist:

```bash
sudo docker exec -it signaturegate-postgres psql -U signaturegate -d signaturegate -c "\dt"
```

4) Seed at least one agreement template (As long as base schema doesn't already include one)

```bash
sudo docker exec -it signaturegate-postgres psql -U signaturegate -d signaturegate -c " \
INSERT INTO agreement_templates (name, version, required_for, doc_url, active) \
VALUES ('Member Acknowledgment & Liability Release', '2025-12-01', ARRAY['membership','sacrament_release'], \
'OPENSIGN_TEMPLATE_OR_PDF_URL', true) ON CONFLICT DO NOTHING;"
```

5) Create the NocoDB base connected to signaturegate-postgres

In NocoDB UI:

Create Base → name it SignatureGate.

Open that base → Connect External Data 
NocoDB

Choose PostgreSQL and enter connection info:

If NocoDB is running in the same docker compose network, use:

```bash
Host: signaturegate-postgres
Port: 5432
DB: ${SIG_DB_NAME}
User: ${SIG_DB_USER}
Password: ${SIG_DB_PASSWORD}
```


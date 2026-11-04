# Veriqta engineering platform

The application, data, delivery, telemetry, recovery, governance and incident-control planes have separate responsibilities.

| Plane | Primary implementation | Failure boundary |
|---|---|---|
| Requests and jobs | `application/`, `kubernetes/` | Process, dependency, node and AZ |
| Durable business data | PostgreSQL orders, outbox and ledger | Transaction integrity and restore correctness |
| Infrastructure | Independent Terraform roots | State, account, Region, IAM and KMS |
| Delivery | Trusted build, verifier, protected GitOps promotion | Source/workflow authority and artifact identity |
| Investigation | OpenTelemetry, Prometheus, Loki, Tempo, Grafana | Collection loss, sampling and retention |
| Recovery | Encrypted backups, restore verification and write fencing | Data loss, key availability and split-brain |
| Governance | OPA and separately approved exceptions | Unknown plans, review boundaries and drift |
| Incident command | Authenticated intake, durable claims, allowlisted SSM | Duplicate/conflicting actions and ambiguous outcomes |

The local ledger has one transactional authority. Regional replicas or restored databases must not independently promote themselves using copied authority rows. Routing, identity and storage changes require a controlled handover and independent verification.

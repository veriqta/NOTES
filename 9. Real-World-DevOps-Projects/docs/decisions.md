# Engineering decisions

1. **Separate state ownership.** Backend, application dependencies, cluster, backup policies and operational identities have independent roots. Recovery exports must be reachable when ordinary CI is unavailable.
2. **Dependency-independent liveness.** Database failures remove readiness while preserving process liveness, preventing dependency-driven restart loops.
3. **Single transactional write authority.** The ledger checks fencing and writes under one database transaction. Loss of authority sacrifices write availability instead of inventing global ownership from DNS.
4. **Immutable promotion.** Build once, scan/sign/verify the digest, and promote the same artifact. Verification and admission have independent failure modes to test.
5. **Recommendation before action.** FinOps and recovery decision functions do not possess mutation credentials. Actuators need separate authorization and idempotency controls.
6. **Retained data requires retained keys.** Deleting a workload does not authorize deleting its snapshot encryption key. Key retirement is a separately reviewed lifecycle operation.
7. **Local evidence is scoped.** SQLite coordination, simulated payments, and a shared lab database user make the exercises reproducible; they are not evidence of a highly available production control plane.

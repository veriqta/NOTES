# Veriqta platform threat model

| Boundary | Attack/failure | Control | Verification |
|---|---|---|---|
| Contributor to release | PR tries to obtain cloud credentials | Credential-free PR job; OIDC exact subject; protected main/environment | Attempt role assumption from an untrusted PR |
| Registry to workload | Unsigned or changed artifact | Digest pin, exact signing identity, admission enforcement | Wrong signer and changed-digest denial tests |
| Portal to provisioner | Privilege fields or arbitrary template execution | Server-side request schema, protected templates, action allowlist, scoped GitOps identity | Unknown IAM field and oversized request rejection |
| Primary to recovery writer | Stale observations cause two writers | Same-transaction authority/epoch checks; external fencing before independent-DB promotion | Stale-epoch, lease-expiry and concurrent replay tests |
| Alert to privileged action | Forged approval or duplicate execution | Authenticated intake, protected operator path, durable claim, SSM deterministic client token | Unauthenticated API rejection and concurrent claim test |
| Backup to recovery | Unusable encryption key or wrong network | Authenticated encrypted archive, separate key custody, destination dependency checks | Wrong-key failure plus real restore/application test |
| Plan to apply | Hidden replacement or fabricated exception | Plan policy, exact artifact review, independent expiring exceptions | Dangerous plan denied; self-approval/expiry tests |

Residual risks include compromise of a trusted maintainer/signing workflow, an improperly protected approval repository, unavailable authoritative storage, telemetry loss, and incorrect operator-supplied evidence. Do not turn lab identity hints or caller-supplied booleans into production authorization.

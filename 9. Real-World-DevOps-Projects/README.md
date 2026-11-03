# 10 Real-World DevOps Projects You Can Build and Add to GitHub

**VERIQTA**

Build a portfolio around engineering decisions that can be tested: when to stop restarting a service, which artifact may enter a cluster, whether a backup can restore the business, and who may accept writes after a failure.

These ten projects share a working checkout application and reusable infrastructure. Each project adds a distinct operational capability, a controlled failure exercise, and acceptance criteria. Use the local application for repeatable practice, then use the AWS and Kubernetes configurations to investigate the cloud-specific behavior. Record measurements from your own runs; an architectural intention is not a measured result.

## Projects

| Project | System | Suggested repository name |
|---|---|---|
| 01 | A resilient platform that knows when to stop remediation | `self-healing-production-platform` |
| 02 | A delivery pipeline with independent verification | `zero-trust-delivery-factory` |
| 03 | A platform that verifies recovery from encrypted backups | `disaster-recovery-verification-platform` |
| 04 | An incident investigation platform with correlated telemetry | `production-incident-observability-lab` |
| 05 | A self-service developer platform with constrained templates | `self-service-platform-backstage` |
| 06 | A cost and capacity engine that protects reliability | `finops-capacity-decision-engine` |
| 07 | A progressive release decision system | `production-progressive-delivery-engine` |
| 08 | Regional recovery with authoritative write ownership | `split-brain-safe-regional-failover` |
| 09 | Infrastructure governance with controlled exceptions | `terraform-policy-guardrail-engine` |
| 10 | Incident command and controlled recovery orchestration | `production-incident-command-platform` |

The extended portfolio names `enterprise-internal-developer-platform`, `reliability-aware-finops-engine`, `production-release-decision-system`, `disaster-recovery-write-ownership`, `infrastructure-governance-engine`, and `incident-response-orchestration-engine` also fit the corresponding systems. Choose names that describe what you actually implement and prove.

## Prepare the workstation

Use Linux, macOS, or Windows with WSL. Install Python 3.11 or later, Git, Docker Engine/Desktop with Compose v2, Terraform 1.13.5, AWS CLI v2, `kubectl`, Helm, and OPA 1.0.1. The Terraform configurations pin AWS provider 6.19.0. Kubernetes manifests use current stable API groups; the digest-admission policy requires Kubernetes 1.30 or later. Select a currently supported EKS control-plane version and matching add-ons for a live cluster rather than copying an obsolete version from a test fixture.

Use the [official Terraform installation guide](https://developer.hashicorp.com/terraform/install), [Docker installation instructions](https://docs.docker.com/get-started/get-docker/), and [Kubernetes tool instructions](https://kubernetes.io/docs/tasks/tools/). Start Docker and confirm `docker info` works before running Compose exercises.

Open a terminal in `9. Real-World-DevOps-Projects`:

```bash
export BOOK="$(pwd)"
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.lock.txt
python -m pip install --no-deps -e .
mkdir -p .private artifacts
chmod 700 .private artifacts
umask 077
python scripts/init_lab.py
```

`requirements.txt` lists direct dependencies; the lock file pins the resolved Python environment. The editable installation makes `application` and `engineering` importable by the helper scripts. Keep secrets, encrypted backups, raw telemetry, database exports, state, and binary plans in the ignored private directories. A backup key stored next to its only encrypted backup does not provide an independent recovery path.

### Run checks before provisioning

```bash
python scripts/validate.py
opa test policies -v
kubectl kustomize kubernetes > artifacts/base-manifests.yaml
```

The validator parses Python and YAML, runs Python tests, formats/validates Terraform, and executes mocked AWS plans. PostgreSQL integration tests require `TEST_DATABASE_URL`; without it they explicitly skip. Mocked plans do not prove actual AWS permissions, quotas, network reachability, image boot, cluster behavior, or successful restoration.

### Start the local application

The local stack contains two isolated PostgreSQL databases, four API services, and a worker. PostgreSQL ports and dashboards bind to the workstation loopback address. No image is pushed to a registry.

```bash
python scripts/lab.py up -d primary recovery
python scripts/lab.py build gateway
python scripts/lab.py run --rm --no-deps gateway python -c 'from application.db import initialize; initialize()'
python scripts/lab.py up -d gateway checkout payment inventory worker
python scripts/compose_smoke.py
```

The migration command initializes the primary schema once. Replicas do not run DDL at application startup. A new recovery database is populated by restoring a backup, not by silently pointing the primary application at it.

```bash
curl --fail http://127.0.0.1:18080/healthz
curl --fail http://127.0.0.1:18080/readyz
curl --fail -X POST http://127.0.0.1:18080/checkout \
  -H 'Idempotency-Key: veriqta-first-order'
python scripts/traffic.py --count 100 --workers 4
```

Expected result: the gateway calls checkout, checkout calls payment and inventory, and a successful order creates one durable outbox record. The payment and inventory endpoints are explicitly simulations: they do not charge money or decrement real stock. The worker records an idempotent receipt. In AWS it can use SQS transport; locally it uses the PostgreSQL outbox directly. Reusing an order key does not create another order.

```mermaid
flowchart LR
  Client --> Gateway
  Gateway --> Checkout
  Checkout --> Payment[Payment simulator]
  Checkout --> Inventory[Inventory simulator]
  Checkout --> DB[(PostgreSQL orders and outbox)]
  DB --> Worker
  Worker --> Receipts[(Idempotent receipts)]
  Services[Service instrumentation] --> Collector[OpenTelemetry Collector]
  Collector --> Tempo
  Collector --> Loki
  Metrics[Application metrics] --> Prometheus
  Prometheus --> Grafana
  Tempo --> Grafana
  Loki --> Grafana
```

The local database identity is deliberately shared for setup simplicity. Production services need separate least-privilege database roles, migration identities, credential rotation, bounded connection pools, and authorization at the API boundary. Keep the unauthenticated application endpoints inside the lab; they are not a public customer API.

## AWS and Kubernetes foundation

### Accounts, costs, and state ownership

Use an isolated AWS account with an approved SSO role. Never use the root user for the exercises. EKS control planes, nodes, three NAT gateways, interface endpoints across three AZs, RDS Multi-AZ, ALBs, public IPv4 addresses, backups, logs, KMS, ECR, and SQS can all produce charges. Estimate the selected Region's costs and set a budget before applying. Budget alerts do not cap expenditure.

```bash
export AWS_PROFILE=veriqta-lab
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION="$AWS_REGION"
aws sso login --profile "$AWS_PROFILE"
export ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
aws sts get-caller-identity
function tf() {
  local root="$1"
  shift
  terraform -chdir="$BOOK/infrastructure/$root" "$@"
}
```

Each root owns its own state: `backend`, `foundation`, `cluster`, `backup`, `delivery-identity`, and `incidents`. For a second regional foundation, use a separate working directory and state key. Never point two regional configurations at one state or make two states own the same resource.

The backend root supplies versioned private state, KMS encryption, native S3 locking, environment roles, and a retained archive bucket. Bootstrap it with an explicit existing operator role ARN:

```bash
cat > infrastructure/backend/terraform.tfvars <<EOF
account_id = "$ACCOUNT_ID"
region = "$AWS_REGION"
name = "veriqta9-state"
trusted_principal_arns = ["arn:aws:iam::$ACCOUNT_ID:role/REPLACE_WITH_OPERATOR_ROLE"]
EOF

tf backend init
tf backend plan -out="$BOOK/.private/backend.tfplan"
tf backend show "$BOOK/.private/backend.tfplan"
tf backend apply "$BOOK/.private/backend.tfplan"
export STATE_BUCKET="$(tf backend output -raw bucket)"
export STATE_KEY_ARN="$(tf backend output -raw kms_key_arn)"
```

Keep the bootstrap state protected. The bucket must exist before another root can initialize its S3 backend. For each consumer, create `backend.tf` containing `terraform { backend "s3" {} }` as a multiline block and a private backend configuration:

```hcl
bucket               = "REPLACE_WITH_STATE_BUCKET"
key                  = "environments/dev/veriqta9-foundation/terraform.tfstate"
region               = "us-east-1"
kms_key_id           = "REPLACE_WITH_STATE_KEY_ARN"
encrypt              = true
use_lockfile         = true
workspace_key_prefix = "environments/dev/workspaces"
```

Initialize with `terraform init -backend-config=PATH_TO_PRIVATE_BACKEND_FILE`. Use `-migrate-state` only when intentionally migrating an existing local state. Change the key for every root and regional environment. Native S3 locks need delete permission for the `.tflock` object; live state objects do not need routine deletion. See [Terraform S3 backend permissions](https://developer.hashicorp.com/terraform/language/backend/s3).

### Provision the application dependencies

Select a supported PostgreSQL engine version and verify that your intended instance class and Multi-AZ mode are available:

```bash
aws rds describe-db-engine-versions --engine postgres --default-only \
  --query 'DBEngineVersions[0].EngineVersion'
aws rds describe-orderable-db-instance-options --engine postgres \
  --db-instance-class db.t4g.small \
  --query 'OrderableDBInstanceOptions[].[EngineVersion,MultiAZCapable]'
```

Create `infrastructure/foundation/terraform.tfvars`:

```hcl
account_id              = "REPLACE_WITH_ACCOUNT_ID"
region                  = "us-east-1"
name                    = "veriqta9-primary"
cidr                    = "10.90.0.0/16"
database_engine_version = "REPLACE_WITH_SUPPORTED_ENGINE_VERSION"
```

```bash
tf foundation init
tf foundation plan -out="$BOOK/.private/foundation.tfplan"
tf foundation show "$BOOK/.private/foundation.tfplan"
tf foundation apply "$BOOK/.private/foundation.tfplan"
tf foundation output -json contract > .private/foundation.json
```

The contract contains resource identifiers, not the database password. RDS generates and manages the password in Secrets Manager. The data key has destruction protection because retained database snapshots and objects can still depend on it. RDS uses one primary and one standby across two AZs; three application AZs do not imply three writable database nodes.

### Provision an isolated EKS cluster

Choose your SSO role ARN and a narrow workstation/office CIDR for the control-plane public endpoint. The private endpoint remains enabled for in-VPC access. Create cluster inputs from the foundation contract:

```bash
export OPERATOR_ROLE_ARN='REPLACE_WITH_APPROVED_OPERATOR_ROLE_ARN'
export OPERATOR_CIDR='REPLACE_WITH_APPROVED_IP/32'
export EKS_VERSION='REPLACE_WITH_CURRENTLY_SUPPORTED_VERSION'
python - <<'PY'
import json,os,pathlib
b=pathlib.Path(os.environ['BOOK'])
v={'account_id':os.environ['ACCOUNT_ID'],'region':os.environ['AWS_REGION'],'name':'veriqta9',
   'kubernetes_version':os.environ['EKS_VERSION'],'administrator_role_arn':os.environ['OPERATOR_ROLE_ARN'],
   'administrator_cidrs':[os.environ['OPERATOR_CIDR']],
   'foundation':json.loads((b/'.private/foundation.json').read_text())}
(b/'infrastructure/cluster/terraform.tfvars.json').write_text(json.dumps(v,indent=2))
PY

tf cluster init
tf cluster plan -out="$BOOK/.private/cluster.tfplan"
tf cluster apply "$BOOK/.private/cluster.tfplan"
export CLUSTER_NAME="$(tf cluster output -raw cluster_name)"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --alias veriqta9-lab
kubectl --context veriqta9-lab get nodes -L topology.kubernetes.io/zone
```

The node group starts with three On-Demand nodes and allows growth to nine. Its managed group spans three private subnets; verify actual node placement. A maximum of nine is not a node autoscaler. Install and configure Cluster Autoscaler or Karpenter deliberately if node demand must grow automatically. HPA scales pods, not EC2 nodes. Instance availability, subnet space, and quotas can still prevent growth.

The node role carries EKS worker, ECR read, and CNI permissions for the lab. Before production, move CNI permissions to a dedicated add-on identity, test network-policy enforcement, and harden node/pod access boundaries. EKS's own cluster security group can permit traffic in addition to the shared workload group; do not describe this cluster as an arbitrary-egress-denying network solely because one attached group has narrow rules.

### Configure the application without exposing its secret

Build and publish an application image only through the deliberately installed release workflow in Project 02. No registry publication is needed for the local lab. Use a reviewed image digest for a cloud deployment.

```bash
python - <<'PY'
import json,os,pathlib
b=pathlib.Path(os.environ['BOOK']);v=json.loads((b/'.private/foundation.json').read_text())
config={'apiVersion':'v1','kind':'ConfigMap','metadata':{'name':'veriqta-config','namespace':'veriqta'},
        'data':{'DB_HOST':v['db_host'],'DB_SECRET_ARN':v['secret_arn'],'QUEUE_URL':v['queue_url']}}
(b/'.private/app-config.json').write_text(json.dumps(config))
PY
kubectl --context veriqta9-lab apply -f kubernetes/namespace.yaml -f kubernetes/serviceaccount.yaml
kubectl --context veriqta9-lab apply -f .private/app-config.json
```

Use a working copy for image substitutions; do not leave a placeholder image on a cloud cluster:

```bash
mkdir -p artifacts/cloud-manifests
cp kubernetes/* artifacts/cloud-manifests/
export APP_IMAGE='ACCOUNT.dkr.ecr.REGION.amazonaws.com/REPOSITORY@sha256:REPLACE_WITH_REVIEWED_DIGEST'
```

Use the supplied renderer to set the reviewed image:

```bash
python scripts/render_images.py --directory artifacts/cloud-manifests --image "$APP_IMAGE"
```

Run schema initialization once as a Kubernetes Job using the same image, service account, and DB configuration. The renderer emits that Job as `.private/migration-job.json` when given `--migration`; apply it before starting the workloads:

```bash
python scripts/render_images.py --directory artifacts/cloud-manifests --image "$APP_IMAGE" --migration
kubectl --context veriqta9-lab apply -f .private/migration-job.json
kubectl --context veriqta9-lab -n veriqta wait --for=condition=complete job/veriqta-schema --timeout=180s
kubectl --context veriqta9-lab apply -k artifacts/cloud-manifests
kubectl --context veriqta9-lab -n veriqta rollout status deployment/checkout --timeout=180s
kubectl --context veriqta9-lab -n veriqta port-forward service/gateway 18080:8080
```

In a second terminal, run the same curl and traffic commands against port 18080. The application uses the default AWS SDK credential chain and the `veriqta-app` Pod Identity association. Do not inject access keys into Kubernetes Secrets. See [EKS Pod Identity SDK behavior](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-minimum-sdk.html).

For public ingress, install an approved AWS Load Balancer Controller or supported ingress controller, configure its dedicated IAM identity, and use a validated TLS certificate and real DNS name. A public ALB is an additional live extension: `port-forward` above is the complete private verification path. Do not expose the unauthenticated teaching API to the internet. The progressive-release lab uses an explicitly configured NGINX route in Project 07.

## 01. Build a platform that survives infrastructure failure

### Business problem and design

A SaaS API must continue useful service when a pod crashes, a node disappears, or an AZ loses capacity. It also needs a recovery policy that recognizes when restarting application pods cannot repair a failed database.

The platform combines the shared EKS/RDS/SQS foundation, readiness probes, pod topology spread, PDBs, HPA, controlled deployment, telemetry, and a bounded remediation decision engine. `engineering/recovery.py` returns a proposed action; it cannot execute a restart by itself. Keep the actuator separately authorized and require it to persist attempt/cooldown state across restarts. An in-memory retry counter reset by each process restart is not a safety limit.

### Follow along

1. Run the local stack and establish a baseline with `scripts/traffic.py`. Declare an exercise target before injecting a failure: for example, under 1% request failures and p95 under 500 ms at the chosen load. Those numbers are lab criteria, not a production guarantee.
2. Evaluate the dependency-failure scenario:

```bash
python scripts/decision.py recovery projects/01-resilience/scenario.json
```

Expected action: `ESCALATE_DEPENDENCY`, not an application restart.

3. Test a pod crash in the explicit lab cluster:

```bash
kubectl --context veriqta9-lab -n veriqta get pods -l app=checkout -o wide
kubectl --context veriqta9-lab -n veriqta delete pod REPLACE_WITH_ONE_LAB_POD --wait=false
kubectl --context veriqta9-lab -n veriqta rollout status deployment/checkout
```

Select **one** named pod from the output; do not delete the entire replica set. Direct pod deletion bypasses a PDB. The PDB constrains voluntary evictions such as a drain; it cannot prevent a node power loss or an AZ outage. See [Kubernetes disruption budgets](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/).

4. Rehearse a node drain using one disposable worker, while continuously probing the application:

```bash
kubectl --context veriqta9-lab drain REPLACE_WITH_ONE_LAB_NODE \
  --ignore-daemonsets --delete-emptydir-data --timeout=180s
kubectl --context veriqta9-lab uncordon REPLACE_WITH_ONE_LAB_NODE
```

Review the effect on `emptyDir` data before using that flag. Do not force through a blocking PDB merely to make the command finish. Record whether replacement pods had somewhere to schedule.

5. Simulate a local database loss and restoration:

```bash
python scripts/fault.py db-loss
curl -i http://127.0.0.1:18080/healthz
curl -i http://127.0.0.1:18080/readyz
python scripts/fault.py restore-db
```

The liveness endpoint should still report a running process; readiness should fail while the database is inaccessible. This avoids a restart storm driven by a dependency failure.

### AZ and capacity exercise

A node drain is not an AZ outage. For a real AZ impairment experiment, use an approved AWS Fault Injection Simulator experiment in the disposable account, explicit target tags, a finite duration, and stop conditions based on application health. Preview the experiment's targets before starting it. Include node placement, the database's primary/standby AZs, and the load generator's location in the experiment record.

Three evenly loaded AZs lose one third of their capacity when one is lost. Each survivor needs roughly 1.5 times its previous capacity before replacements arrive. Topology spreading helps placement; it does not provide that spare capacity. The provided `ScheduleAnyway` constraints favor continued scheduling under constrained capacity. If you choose `DoNotSchedule`, test the availability tradeoff and verify enough domains remain. See [topology-spread behavior](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/).

### Controlled recovery and evidence

Only consider `RESTART_ONE` when the dependency is healthy, minimum ready capacity remains, fewer than three attempts have occurred, and the two-minute cooldown elapsed. `RESTORE_CAPACITY` means investigate supply/quotas/scheduling; it is not permission to restart the remaining healthy pods. Require a lock per service so two controllers cannot remediate it simultaneously.

Deployments can be managed with the supplied Argo CD Application and AppProject after installing Argo CD using its official release manifests. Replace the exact repository allowlist, import the namespace/config first, and synchronize manually during fault exercises. Automated self-heal must not race with an investigator's intentional changes. Argo CD reconciles configuration; it is not a database-repair mechanism.

Acceptance: service returns to the declared exercise SLO under the faults actually tested, with no unbounded remediation loop. Publish node/pod placement, pending-pod evidence, request/error/latency measurements, the incident timeline, and the reason a proposed action was stopped. Cleanup includes uncordoning nodes, restoring dependencies, stopping experiments, and verifying normal capacity before deleting resources.

## 02. Build delivery that does not trust its own builds

### Business problem and trust boundaries

A successful CI job must not imply unrestricted production access. Separate untrusted contribution checks, trusted builds, verification, and promotion. The supplied teaching workflows live under `workflows/`, so uploading this handbook does not activate a deployment or registry publication workflow.

The untrusted PR workflow has `contents: read`, no OIDC permission, no cloud role, and no production environment. The release workflow runs only on `main`, builds once, produces SBOM/provenance metadata, scans the resulting digest, signs it, verifies the exact identity, and opens a protected GitOps PR for that digest. It never rebuilds the promoted artifact.

### Configure identities

Apply `infrastructure/delivery-identity` with your exact `owner/repository`, existing GitHub OIDC provider ARN, ECR repository ARN, and the common account/Region/name inputs. It creates separate build, verify, and promotion roles. The build role can upload to one repository; the verifier can read it but cannot upload. The promotion role trusts the protected `production-promotion` environment and has no workload permissions by default. Add only the approved GitOps or deployment permissions required by your operating model; do not attach administrator access to make promotion convenient.

Configure these repository variables in the separate lab repository: `BUILD_ROLE_ARN`, `VERIFY_ROLE_ARN`, `AWS_REGION`, `ECR_REPOSITORY`, `GITOPS_APP_ID`, `GITOPS_OWNER`, and `GITOPS_REPOSITORY_NAME`. Store the narrowly scoped GitHub App private key as `GITOPS_PRIVATE_KEY`. Install that App only on the protected GitOps repository with contents/pull-request write permission; it does not need organization or cloud administrator rights. The promotion job changes only `kubernetes/checkout-deployment.yaml` and opens a PR; it never merges that PR. Configure Argo CD to deploy the reviewed GitOps commit according to your approved synchronization policy. Create the protected environment with required reviewers and `main` branch restrictions. Protect workflows, policy code, and release configuration with CODEOWNERS and branch rules. Restrict the GitHub App that writes GitOps PRs to its specific repository; it should not administer clusters.

Copy `workflows/pr-validation.yml` and `workflows/release.yml` only after reviewing these controls. Replace major action tags with reviewed immutable commit references in an operated pipeline. Do not execute contributor-controlled code with production credentials or use `pull_request_target` to bypass that separation.

### Verify an artifact independently

```bash
export IMAGE='REPLACE_WITH_REGISTRY/REPOSITORY@sha256:REVIEWED_DIGEST'
export SIGNING_IDENTITY='https://github.com/ORGANIZATION/REPOSITORY/.github/workflows/release.yml@refs/heads/main'
cosign verify --certificate-identity "$SIGNING_IDENTITY" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com "$IMAGE"
```

Match the full workflow identity and issuer. An expression that accepts any issuer or any subject does not establish your release authority. Signing proves who signed bytes; it does not prove that those bytes are safe. Require a passing scan and inspect SBOM/provenance claims, source commit, builder/workflow identity, and subject digest. BuildKit's SBOM/provenance settings attach metadata to the pushed artifact; policy still has to verify the claims it relies on. See [Cosign verification](https://docs.sigstore.dev/cosign/verifying/verify/).

### Enforce at cluster admission

Install Sigstore policy-controller from its [official instructions](https://docs.sigstore.dev/policy-controller/overview/), record the reviewed chart/controller version, and configure its private-registry authentication if using ECR. Verification needs permission to retrieve signatures and attestations as well as image metadata. EKS node image-pull permission does not automatically grant the policy-controller's identity registry access.

Replace the registry and exact signing identity in `cluster-image-policy.yaml`. Apply it and the digest-only ValidatingAdmissionPolicy. Label only the intended lab namespace with `policy.sigstore.dev/include=true` after both controls are ready. Keep the controller healthy and its failure policy enforcing; an unavailable verifier must not silently admit unverified images.

Test four cases in the isolated namespace: an image specified only by tag, an unsigned digest, a digest signed by another workflow, and the approved signed digest. The first three must fail, and the approved image must start. Also test init containers. Keep workloads and their service accounts unable to alter admission policies or the controller. Successful `cosign verify` on a workstation is not a substitute for the actual server-side admission test.

### Supply-chain exercise

Submit an untrusted test PR that attempts to request a deployment role and verify the attempt is denied. Do not put real credentials in the test branch. Change the proposed image digest after verification and prove that the old approval/signature does not authorize the new digest. Try skipping the environment approval and confirm the promotion job cannot proceed. Record commit → build → scan → digest → signature/provenance → approval → GitOps change → running image ID.

Acceptance: unauthorized code cannot obtain privileged deployment credentials or promote an unverified artifact. Publish the threat model, role boundaries, denied test evidence, and the audit chain. Remove only temporary test artifacts under the approved registry retention policy; keep evidence and released artifacts as required. No pipeline here is evidence of immunity from a compromised trusted maintainer or signing workflow; protect and review that trust root.

## 03. Prove that backups can recover the business

### Business problem

A healthcare platform reports successful backups, but no engineer has restored the application in a clean environment. Backup completion, object integrity, recoverable credentials, application behavior, and measured RTO/RPO are separate facts. Use synthetic data for this project; do not place patient or customer information in a portfolio.

### Local encrypted recovery exercise

Create an order marker, then pause incoming business writes while capturing the exercise backup. The local payment simulator has no external effects. Keep both databases running, and stop gateway/checkout while taking the backup if other test clients could still write.

```bash
curl --fail -X POST http://127.0.0.1:18080/checkout \
  -H 'Idempotency-Key: veriqta-recovery-marker'
mkdir -p .private/objects
printf 'veriqta recovery object\n' > .private/objects/example.txt
python scripts/lab.py stop gateway checkout
python scripts/backup.py backup .private/backup.fernet
python scripts/backup.py restore .private/backup.fernet --objects .private/recovered-objects
```

The backup contains a PostgreSQL custom-format dump and object bytes inside an authenticated Fernet-encrypted envelope. The script always restores into the isolated `recovery` service. A wrong encryption key or modified envelope must fail before restore. Keep independent copies of the key according to the recovery policy. This small archive format reads objects into memory; large systems need streaming backups and versioned object manifests.

Verify known-good business records while the source remains unchanged:

```bash
set -a
source .private/lab.env
set +a
export PRIMARY_DATABASE_URL="postgresql://veriqta:$PGPASSWORD@127.0.0.1:15432/veriqta"
export RECOVERY_DATABASE_URL="postgresql://veriqta:$PGPASSWORD@127.0.0.1:15433/veriqta"
python scripts/verify_recovery.py --marker veriqta-recovery-marker
cmp .private/objects/example.txt .private/recovered-objects/example.txt
python scripts/lab.py start gateway checkout
```

A successful `pg_restore` is not the acceptance test. Start a recovered checkout instance against the recovery DSN, point its payment/inventory URLs at the lab simulators, and verify a new write:

```bash
export DATABASE_URL="$RECOVERY_DATABASE_URL"
export SERVICE_NAME=checkout
export PAYMENT_URL=http://127.0.0.1:18082/pay
export INVENTORY_URL=http://127.0.0.1:18083/reserve
python -m uvicorn application.api:app --host 127.0.0.1 --port 18084
```

In another terminal, post an order with a new key to port 18084 and query the recovery database to confirm it exists. Do not accidentally compare that intentionally changed recovery database with an unchanged primary and describe the resulting difference as corruption.

After the smoke test, run the encrypted-backup, restore, data comparison, object check, and recovered-application new-write exercise automatically:

```bash
python scripts/compose_recovery.py
```

It deliberately stops gateway, checkout, and worker during the frozen-source backup and leaves them stopped afterward. Restart them deliberately when the drill ends. Its elapsed time is a local exercise measurement, not a claim about regional production RTO.

### Inject operational failures

Use `scripts/fault.py db-loss` to stop the primary and keep restoration independent of it. Repeat with an intentionally wrong backup key and confirm decryption fails. In a separate disposable restore, corrupt one business record and show that the verification detects the difference. After actual source corruption, compare restored records against a known-good pre-corruption expectation, not against the already corrupted live source.

Record the last confirmed business write, the last recovered write, the incident start, restore start/end, dependency repairs, and successful recovered application test. `restore_seconds` from the helper measures only its restore operation. Full RTO includes detection, access, provisioning, restore, verification, and traffic recovery. RPO is the measured committed-data loss window; backup start time alone does not establish it. State any writes deliberately made after the backup.

### Cloud recovery and dependency checks

Provision a second foundation with a different name, nonoverlapping CIDR, Region, and backend key. Use a separate copy of the same foundation root so you cannot accidentally turn the primary root into a recovery root. The recovery foundation may be created without a new database when an AWS Backup restore owns that resource; in that case, use the separate network module and adopt the restored DB only after a matching reviewed configuration exists. Do not create a duplicate DB merely to fill an expected Terraform output.

The `backup` root configures a daily backup with 14-day primary retention and a 30-day copied recovery point. Supply the original database ARN, source vault name, destination vault ARN, and the exact source/destination KMS key ARNs. Inspect vault/key policies and AWS Backup settings in both Regions before applying. The backup role's broad KMS operation set is restricted to those explicit keys; further constrain grants and services as appropriate for the approved environment.

```bash
# After configuring the backup root and reviewing its plan:
tf backup init
tf backup plan -out="$BOOK/.private/backup-plan.tfplan"
tf backup apply "$BOOK/.private/backup-plan.tfplan"
aws backup list-copy-jobs
aws backup list-recovery-points-by-backup-vault --region YOUR_RECOVERY_REGION \
  --backup-vault-name YOUR_RECOVERY_VAULT
```

Select a completed **destination-region** RDS recovery point. Inspect `EncryptionKeyArn`, status, and freshness. Obtain restore metadata:

```bash
aws backup get-recovery-point-restore-metadata --region YOUR_RECOVERY_REGION \
  --backup-vault-name YOUR_RECOVERY_VAULT \
  --recovery-point-arn YOUR_COMPLETED_RECOVERY_POINT \
  > .private/restore-response.json
```

Extract the `RestoreMetadata` map into a new private JSON file. Replace the DB identifier, DB subnet group, security-group IDs, public-access setting, instance class, and any region-specific option/parameter references. Review supported fields for your engine; metadata values are strings, and list-valued settings must use the API's expected encoding. Start the restore only with an approved restore role that can use the reported key and create the destination RDS resource:

```bash
aws backup start-restore-job --region YOUR_RECOVERY_REGION \
  --recovery-point-arn YOUR_COMPLETED_RECOVERY_POINT \
  --iam-role-arn YOUR_APPROVED_RESTORE_ROLE \
  --resource-type RDS --metadata file://.private/reviewed-restore-metadata.json
aws backup describe-restore-job --region YOUR_RECOVERY_REGION --restore-job-id YOUR_JOB_ID
```

Wait for the job and database to become available, verify the actual resulting ARN, establish an active destination credential, and run the marker/new-write checks. A primary-region secret ARN is not a destination credential strategy. Check RDS managed-secret status and rotate/enable the destination secret deliberately if needed. Keep identity, KMS, DNS, routes, security groups, AMI/image availability, and application configuration in the dependency checklist. See [AWS Backup RDS restore metadata](https://docs.aws.amazon.com/aws-backup/latest/devguide/restoring-rds.html) and [backup encryption behavior](https://docs.aws.amazon.com/aws-backup/latest/devguide/encryption.html).

Acceptance: a clean environment restores known-good data and application functionality within declared objectives, and unusable backups/dependencies are detected. Publish both a successful and a failed exercise report. Cleanup must preserve encryption keys and retained recovery points until their documented retirement conditions are met.

## 04. Build an incident investigation platform

### Business problem and instrumentation

Checkout failures can occur while node CPU and memory look ordinary. Follow the failing request through service boundaries and dependency waits. The application emits RED metrics—rate, errors, duration—plus in-flight request counts, JSON logs with trace IDs, and OpenTelemetry spans. Request IDs and user inputs are not metric labels, preventing uncontrolled cardinality.

Start the observability profile:

```bash
python scripts/lab.py --profile observability up -d
python scripts/traffic.py --count 100 --workers 4
```

Open Grafana at `http://127.0.0.1:13000`, use username `admin`, and retrieve its local password privately from `.private/lab.env`. Prometheus is on port 19090, Tempo on 13200, and Loki on 13100. The provisioned dashboard shows checkout request rate, error fraction, p95 latency, and in-flight work. Datasources link JSON log trace IDs to Tempo.

No dashboard is publicly authenticated or hardened by this loopback setup. Restrict remote access through a real authentication layer before moving it to a shared host. Grafana's local admin password is generated, not a public default.

### Tail sampling and retention

The Collector retains error traces, traces slower than 500 ms, and a 10% baseline sample. The application records all candidate spans so the Collector can make a tail decision. Metrics are collected independently from sampling; sampled traces must not be treated as an unbiased request counter.

A single tail-sampling collector receives all spans for each trace in this lab. Scaling it behind a random load balancer can split traces and produce incorrect decisions. Use trace-ID routing and test collector capacity before scaling a stateful sampling tier. The 10-second decision window must accommodate actual span arrival delays. The Collector's memory limits and queue behavior can still drop telemetry under overload. See [OpenTelemetry tail-sampling requirements](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/processor/tailsamplingprocessor/README.md).

The local Prometheus, Tempo, and Loki examples retain roughly 24 hours of data. Apply separate capacity, retention, deletion, and privacy policies for a real installation. Do not log payment details, credentials, authorization headers, or customer payloads to make traces more convenient.

### Inject hidden dependency failure

In one terminal, hold the inventory row lock for 20 seconds:

```bash
python scripts/fault.py db-lock
```

In another terminal, immediately run a bounded load:

```bash
python scripts/traffic.py --count 100 --workers 4
```

Investigate without first reading the injected-fault command. Start from the failed checkout trace, follow the inventory span, find lock waits, and correlate the trace ID with logs. Query PostgreSQL's `pg_stat_activity`, `wait_event_type`, and `pg_blocking_pids(pid)` through the lab database. The lock timeout bounds dependency wait; the API should report failures rather than keep every thread blocked indefinitely.

To simulate downstream latency, set a temporary environment override and recreate only payment:

```bash
export PAYMENT_DELAY_SECONDS=1
python scripts/lab.py up -d --force-recreate payment
python scripts/traffic.py --count 100 --workers 4
unset PAYMENT_DELAY_SECONDS
python scripts/lab.py up -d --force-recreate payment
```

There is deliberately no automatic retry in `application.api.call`. To investigate retry amplification, compare the same workload with an explicitly bounded experimental retry policy in a separate branch. Count attempts as well as user requests, keep an overall deadline, add jitter, and restrict retries to idempotent operations. Do not add an unbounded loop. Simulate pool pressure by reducing `POOL_SIZE` in a copied lab configuration and running a small concurrent load; compare pool exhaustion, in-flight requests, latency, and DB connection counts.

The supplied SLO alert combines a five-minute and one-minute error fraction against a 99.9% availability objective. Its 1.44% threshold represents a 14.4x error-budget burn rate. Missing telemetry has a separate alert; missing data does not mean healthy service. Alert windows require enough traffic and elapsed time to be meaningful.

For EKS, install an approved Prometheus Operator stack and apply `kubernetes/podmonitor.yaml` after its CRDs exist. It scrapes pods individually, avoiding an inaccurate single service-level scrape across replicas. Deploy the Collector/Tempo/Loki configuration through reviewed charts or equivalent manifests, using consistent endpoints and per-service identity; the local Compose configuration is not itself a Kubernetes deployment.

Acceptance: an investigator identifies the injected failure domain using correlated telemetry, not prior fault knowledge. Publish normal/failure traces, metric queries, a timeline tied to deployment history, and a root-cause report with corrective actions. Stop the lock/latency experiment, restore connection settings, and verify request behavior before cleanup.

## 05. Build self-service with useful boundaries

### Business problem and platform contract

A developer should not wait days for a standard service or receive unrestricted AWS permissions merely to deploy it. Separate the portal interface from the provisioner's authority. Backstage supplies a catalog and approved templates; the protected platform workflow owns infrastructure and GitOps credentials.

The local renderer accepts only a service name, an approved owner, environment, bounded CPU/memory requests, and a preview expiry. Unknown privileged fields fail validation. It writes an ownership record, namespace, quota, and README atomically. Repeating identical inputs returns the same service; reusing the name with different inputs requires a reviewed update.

```bash
python scripts/self_service.py projects/05-self-service/request.json
cat artifacts/generated/veriqta-orders/catalog-info.yaml
cat artifacts/generated/veriqta-orders/quota.yaml
```

The renderer proposes manifests; it never applies resources or creates a public repository. Use its output as input to the protected GitOps workflow. That workflow may automatically accept preapproved contracts, but it must repeat validation server-side and have only the permissions needed by the approved template. A portal's dropdown is not an authorization control.

### Add the Backstage portal

Create an application following [Backstage's installation guide](https://backstage.io/docs/getting-started/), record the exact generator version you select, and retain its generated package/Yarn lockfiles. Use the supported Node.js version and package manager for that release. In the generated backend, enable catalog, scaffolder, GitHub publishing integration, PostgreSQL, authenticated GitHub/organization sign-in, and the permission backend. Do not enable a guest sign-in resolver on a shared installation.

Copy the supplied `backstage-template.yaml` and its `skeleton/` together into the backend's `veriqta-template/` directory. Set the catalog location relative to the generated backend's runtime working directory. Use `backstage-config.yaml` as the configuration fragment, setting the private database URL and the narrowly scoped GitHub App/token through environment secrets. Replace the organization allowlist; the template fixes the repository owner instead of accepting arbitrary destinations.

Add the GitHub scaffolder backend module to the generated backend through its package manager and backend registration:

```typescript
backend.add(import('@backstage/plugin-catalog-backend'));
backend.add(import('@backstage/plugin-scaffolder-backend'));
backend.add(import('@backstage/plugin-scaffolder-backend-module-github'));
backend.add(import('@backstage/plugin-permission-backend'));
```

Avoid duplicate registrations already present in the generated application. Copy `permission-policy.ts` and `permission-module.ts` into a backend module, register that module with `backend.add`, and remove the generated allow-all policy module. Install the imported permission/scaffolder packages at versions compatible with the generated Backstage release. Run the generated application's typecheck and tests after integration; the supplied fragment is not a prebuilt standalone Backstage distribution.

The permission policy admits approved organization groups, restricts scaffolder actions, scopes task access to the task owner, and denies other permissions by default. Also restrict catalog template ingestion to a protected repository. Otherwise a trusted user might submit a malicious template that invokes an allowed publishing action with unintended inputs. Use the permission framework and action-property conditions where required by your organization. See [scaffolder authorization](https://backstage.io/docs/features/software-templates/authorizing-scaffolder-template-details/).

### Provision, deploy, and measure

Connect the template's generated repository to the protected shared build/release workflow from Project 02. Keep Terraform roots and cloud roles under platform ownership. Use the foundation outputs and namespace-scoped GitOps configuration to deploy the service; do not copy an AWS administrator token into the generated repository. Provide a service URL only after readiness and access checks pass.

Run onboarding as a developer, with no direct AWS or cluster administrator access. Attempt an excessive memory request, an unknown owner, a production environment, and an `iam_policy` field. The local renderer rejects these. Repeat equivalent requests through the portal/backend and show server-side denial, not merely a disabled form field. Re-submit the same valid request, interrupt provisioning mid-task, and verify retries do not create conflicting ownership or duplicate resources.

Preview requests require a timezone-aware expiry within 48 hours. The supplied garbage-collection helper lists expired rendered previews and prints a proposed deletion command:

```bash
python scripts/preview_gc.py artifacts/generated
```

Keep expiry metadata and owner checks authoritative before wiring deletion to an automated controller. Never delete a production namespace because a caller supplied an expired label. Record onboarding duration, successful/failed requests, adoption by team, and support tickets. A fast template that creates unusable services is not successful self-service.

Acceptance: an authenticated developer onboards, deploys, and accesses an approved service through the portal and protected automation without direct infrastructure administration. Publish the catalog/template, policy rejections, retry/partial-failure behavior, preview lifecycle, and measured time/support impact. For the local renderer alone, claim only the generation/idempotency result; complete the portal and controlled delivery exercise before claiming end-to-end automation.

## 06. Build FinOps decisions that protect reliability

### Business problem and inputs

A cheaper configuration can violate peak capacity, recovery objectives, or database safety. The engine recommends changes; it does not delete or resize resources. Gather billing data, account/owner/application/environment tags, CPU and memory observations, network/storage growth, deployment history, SLOs, RTO/RPO requirements, and a rollback plan.

Run the supplied synthetic cases:

```bash
python scripts/decision.py finops projects/06-finops/recommendations.json
```

Expected results: one reviewable recommendation, one rejected standby-capacity removal, and one rejected critical-database action. The USD amounts are illustrative estimates, not current AWS prices or promised savings. Missing/stale telemetry, a short observation window, missing ownership, inadequate remaining peak capacity, or unproven SLO/recovery limits prevent a recommendation.

### Ingest live billing data safely

Use an authorized billing identity, not an application role. The end date is exclusive. Store the export privately:

```bash
python scripts/cost_ingest.py 2026-10-01 2026-11-01 --output .private/billing.json
```

Replace the dates with complete comparable periods. The helper fetches every Cost Explorer page and preserves estimated flags and cost units. Activate relevant user-defined cost-allocation tags in billing and account for reporting lag. Unallocated costs remain an investigation item, not free infrastructure. Cost Explorer API calls may be billed; check the current service pricing before scheduling frequent polling.

For large Cost and Usage Reports, use a private S3/Athena pipeline with the same attribution rules and access controls. Retain account scope, currency, discounts, credits, tax treatment, and units. Do not sum GB, request counts, and hours into a common “usage” number or add costs in different currencies.

### Investigate a spike

Create a synthetic spike in the analysis input rather than generating unnecessary paid traffic. Group the live export by service, usage type, linked account, owner, and resource where available. Distinguish NAT hours from NAT processing bytes, cross-AZ traffic, public IPv4, object growth, database storage, idle EBS, and logging loops. Correlate the onset with route changes, workloads, and deployments.

Pull CloudWatch utilization over a meaningful period. Memory generally requires an agent; a missing memory metric is not zero memory use. Compare sustained demand, peaks, growth, burst-credit behavior, connection limits, and the capacity left after an AZ loss. Idle headroom may be intentional standby capacity or necessary scale-up warmup margin.

Propose one reversible action with a specific owner. Estimate the change using current regional rates, then run a controlled performance/recovery rehearsal. Reject a recommendation if it would remove a required standby, reduce the retention needed for RPO, impair encryption/logging, or leave insufficient surviving capacity. The supplied guard treats critical databases as requiring an independent migration review.

A recommendation report should contain current cost assumptions, estimated savings, measured performance evidence, reliability constraints, an owner, approval conditions, and a rollback trigger. Notifications should route through the organization's ownership directory; the helper prints decisions and never sends messages automatically. Before scheduling notifications, authorize recipients and deduplicate repeated findings.

Acceptance: identify actionable savings while preserving declared performance, availability, and recovery constraints. Compare an equivalent later billing window after an approved change; billing lag means a short test does not prove a monthly saving. Publish anonymized input, safe/unsafe recommendations, a dashboard/report, and evidence that the rejection rules work. Remove only temporary analysis exports or resources; do not perform automatic production cleanup based on tags alone.

## 07. Stop a release that passes tests but harms customers

### Business problem and deployment choices

CI success says the tested checks passed. It does not prove real-traffic performance or schema compatibility. Use immutable artifacts, a baseline, progressive routing, enough fresh measurements, and explicit promote/pause/abort controls.

```bash
python scripts/decision.py release projects/07-progressive-delivery/good.json
python scripts/decision.py release projects/07-progressive-delivery/bad.json
```

Expected decisions: `PROMOTE` and `ABORT_TO_STABLE`. Unknown/stale or low-volume evidence pauses. A backward-incompatible schema requires a forward-fix decision instead of pretending an image rollback restores removed data.

### Configure the release lab

The release manifests use a separate `veriqta-release` namespace so the original Deployment and the Rollout do not compete for the same pod selectors. Install a reviewed Argo Rollouts release, its `kubectl argo rollouts` plugin, NGINX Ingress Controller, Metrics Server, and a Prometheus stack. Record compatible versions. The canary manifest uses NGINX's supported controller integration, not replica counts as a supposed exact traffic percentage. See [Argo Rollouts NGINX routing](https://argoproj.github.io/argo-rollouts/features/traffic-management/nginx/).

```bash
kubectl --context veriqta9-lab apply -f projects/07-progressive-delivery/namespace.yaml
kubectl --context veriqta9-lab -n veriqta get serviceaccount veriqta-app -o json \
  > .private/release-serviceaccount-source.json
python scripts/release_namespace.py
kubectl --context veriqta9-lab apply -f .private/release-serviceaccount.json -f .private/release-config.json
export APPLICATION_ROLE="$(tf cluster output -raw application_role_arn)"
aws eks create-pod-identity-association --cluster-name "$CLUSTER_NAME" \
  --namespace veriqta-release --service-account veriqta-app --role-arn "$APPLICATION_ROLE"
```

The helper copies only the service-account name and the known foundation configuration into the release namespace; it does not copy tokens or arbitrary Kubernetes metadata. The release namespace needs its own Pod Identity association. Check for an existing association before creating a duplicate.

Render the exact reviewed image into a working copy of the release directory, then apply only the chosen strategy:

```bash
mkdir -p artifacts/release
cp projects/07-progressive-delivery/*.yaml artifacts/release/
python scripts/render_images.py --directory artifacts/release --image "$APP_IMAGE"
kubectl --context veriqta9-lab apply \
  -f artifacts/release/service-stable.yaml -f artifacts/release/service-canary.yaml \
  -f artifacts/release/analysis.yaml -f artifacts/release/ingress.yaml \
  -f artifacts/release/rollout.yaml -f artifacts/release/hpa.yaml
kubectl argo rollouts get rollout checkout -n veriqta-release --watch --context veriqta9-lab
```

Apply the PodMonitor after the Prometheus Operator CRDs exist. Ensure its namespace selector includes both lab namespaces and its release label matches your Prometheus installation. The analysis address assumes `prometheus-operated` in namespace `monitoring`; change it deliberately if your installation differs.

Forward the NGINX controller's HTTP service to a local port and send traffic with host `checkout.veriqta.test`. The ingress must route to `checkout-stable`; Argo Rollouts creates/manages the canary route. A direct port-forward to a random checkout pod bypasses the traffic split and cannot validate routing weights.

### Progressive decisions and failure injection

The canary moves to 10%, waits, evaluates three windows, moves to 50%, and pauses for an explicit final decision. Requests are labeled with the controller's pod-template hash through the downward API; the analysis queries only the new revision. It requires at least 100 canary requests and checks errors and p95. Empty or inconclusive results must pause, not promote. The threshold is an exercise policy, not statistical proof that every workload is safe.

Introduce a slow payment dependency or an error-returning candidate in a separate release build, sign/verify it, and update the Rollout image by digest. Run enough bounded traffic for the windows. Observe the new AnalysisRun, its metric values, and routing changes. Verify traffic returns to the stable revision after a failed analysis.

```bash
kubectl argo rollouts pause checkout -n veriqta-release --context veriqta9-lab
kubectl argo rollouts abort checkout -n veriqta-release --context veriqta9-lab
kubectl argo rollouts get rollout checkout -n veriqta-release --context veriqta9-lab
```

Use `promote` only after the intended metrics and approval conditions pass. An abort may not repair a shared downstream dependency that affects both revisions. Verify stable-service behavior independently before declaring recovery.

For blue-green delivery, use `blue-green.yaml` **instead of** `rollout.yaml`. It uses active/preview services and disables automatic promotion. Drive synthetic traffic through the preview path, run the same decision engine, then explicitly promote or abort. Blue-green changes the active target; it does not split traffic by percentage.

### Database compatibility

`migration-expand.sql` adds an optional field while preserving old readers. `migration-unsafe.sql` is a deliberately unsafe review fixture that drops the amount column; do not execute it against the shared lab DB. Rehearse incompatible changes only in a disposable restored database. Use expand → deploy compatible readers/writers → backfill/verify → contract in a separate approved change. Application rollback does not undelete a column or undo external business effects.

Acceptance: detect and stop a bad candidate before full promotion, verify restored service behavior, and make a reasoned image rollback versus forward-fix decision. Publish immutable artifact IDs, routing observations, analysis values, rollout history, schema review, and the recovery timeline. Cleanup the release namespace's routing/controller resources before deleting its namespace or Pod Identity association.

## 08. Prevent conflicting writes during ambiguous regional failure

### Business problem and authority

A network partition can look like a regional outage. An unreachable primary may still accept writes from clients that can reach it. DNS and monitoring observations are not authoritative write fencing.

The supplied ledger checks owner, epoch, and lease validity under a PostgreSQL row lock, then commits the business write in the **same transaction and same authoritative database**. Idempotency keys are globally unique within that ledger; reusing a key with a different amount is rejected. Promotion increments the epoch under that same lock, so an old epoch cannot commit after promotion.

This implementation chooses consistency: if the authoritative database is unreachable, writes fail closed. It does not claim that a lease read from one system can fence writes to an independently writable database elsewhere. A recovery architecture with independent databases needs an enforcement mechanism at each write sink and a proven old-writer fencing procedure before promotion.

### Run the ownership experiment

Use the local application and initialized database:

```bash
curl --fail -X POST http://127.0.0.1:18081/ledger \
  -H 'Idempotency-Key: veriqta-ledger-001' -H 'Content-Type: application/json' \
  -d '{"amount_cents":1000}'
```

Repeat the same request: `created` becomes false and the row count remains one. Repeat with a different amount: the API rejects it. Start a second checkout process with the same authoritative database but a different owner:

```bash
set -a; source .private/lab.env; set +a
export DATABASE_URL="postgresql://veriqta:$PGPASSWORD@127.0.0.1:15432/veriqta"
export SERVICE_NAME=checkout
export WRITE_OWNER=recovery
export WRITE_EPOCH=2
python -m uvicorn application.api:app --host 127.0.0.1 --port 18085
```

Before promotion, this process is fenced. From an approved operator terminal, promote the authority using an expected owner/epoch comparison:

```bash
python scripts/promote_writer.py --from-owner primary --from-epoch 1 --to-owner recovery
```

After promotion, the new process can commit with epoch 2 and the original epoch-1 process receives `writer fenced`. Run the PostgreSQL integration tests against the disposable database to prove concurrent duplicates produce one row and expired leases are rejected:

```bash
export TEST_DATABASE_URL="$DATABASE_URL"
python -m unittest discover -s tests -p test_postgres.py -v
```

Those tests reset the lab tables. Never point `TEST_DATABASE_URL` at a database containing data you need.

### Partition and regional recovery exercise

Block one writer's access to the authoritative DB using an isolated lab network rule or a deliberately unreachable test DSN. It must not fall back to a local writable copy. Introduce stale health observations and show that the standby still cannot bypass epoch/owner checks. Pause replication or use a stale restored copy in an independent environment to demonstrate why an old ownership row copied with data is not current authority.

For AWS, deploy primary and recovery foundations in distinct Regions and states. The provided recovery model uses cross-region backup copies and controlled restoration. A warm standby/read replica can reduce restoration time but changes cost, credentials, replication-lag behavior, and promotion procedures. RDS managed-master-password integration restricts creating read replicas from the source; select a supported credential model before changing that architecture.

Before promoting an **independent restored DB**, fence all old writers through an enforceable mechanism, verify the data-loss window, establish the new authority, and require the designated recovery approval. If you cannot prove that old writers are fenced, remain read-only. Do not use a client-side lease cache or a last-writer-wins replicated item as proof. DynamoDB's MREC and MRSC modes have different consistency/transaction constraints; an eventually consistent global-table conditional write is not a global mutex. See [DynamoDB global-table consistency modes](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/GlobalTables.html).

Route 53/ALB traffic changes occur only after data and writer acceptance checks. Clients can cache old DNS and retain connections, so measure actual reconnection behavior. Reconcile transaction IDs and amounts after the partition, establish one authoritative ledger, and perform failback as a controlled data migration. Near-zero RPO is a target to measure, not a consequence of having two Regions.

Acceptance: only the intended writer commits during the tested partition/promotion, duplicate keys do not duplicate effects, and restored data is reconciled. Publish the authority mechanism, its availability tradeoff, rejected stale writes, concurrent tests, measured replication/data-loss window, and the promotion/failback runbook.

## 09. Block dangerous infrastructure changes

### Business problem and policy scope

A Terraform plan can be syntactically valid while exposing a database or replacing stateful infrastructure. Review actions and unknown values, not just whether `terraform validate` passes.

The Rego policy checks deletes/replacements, unproven RDS encryption, public databases, missing ownership on selected taggable resource types, public ingress, unresolved ingress fields, and IAM policy changes requiring dedicated review. IAM changes are intentionally routed to manual policy-specific review rather than approved by a superficial wildcard search.

```bash
opa test policies -v
python scripts/governance.py projects/09-governance/compliant-plan.json
python scripts/governance.py projects/09-governance/dangerous-plan.json
```

The compliant example exits successfully. The dangerous example prints resource-specific reasons and exits 2. The policy is a scoped teaching guard, not a complete security/compliance scanner. Extend resource coverage and tests to match your service estate. In particular, add inline security-group rules, IPv6, IAM conditions/trust relationships, service resource policies, and approved architectural patterns before relying on broader automated approval. See [OPA and Terraform plan limitations](https://www.openpolicyagent.org/docs/terraform).

### Review a real saved plan

```bash
tf foundation plan -out="$BOOK/.private/reviewed.tfplan"
tf foundation show -json "$BOOK/.private/reviewed.tfplan" > .private/reviewed-plan.json
python scripts/governance.py .private/reviewed-plan.json
```

Keep plan JSON private. A policy on one plan must not authorize a different replan. Protect the saved artifact's commit, root, account, backend key, Terraform/provider versions, approval age, and reviewer. Serialize state-changing operations and reject stale plans. Locks do not reserve infrastructure during an approval window, and out-of-band AWS changes can occur without advancing Terraform's state serial.

### Controlled exceptions

Use a separately protected approval repository with `approvers.json` and `approved.json`. Each approved entry contains requester, independent approver, ticket, exact resource, rule, issued/expiry timestamps, and the canonical plan digest. The validator enforces a maximum 72-hour lifetime and rejects expired, self-approved, or plan-mismatched entries.

```json
{
  "requester": "veriqta-requester",
  "approver": "veriqta-approved-reviewer",
  "ticket": "INC-EXAMPLE",
  "resource": "aws_db_instance.database",
  "rule": "destructive",
  "issued_at": "REPLACE_WITH_UTC_TIMESTAMP",
  "expires_at": "REPLACE_WITH_UTC_TIMESTAMP_WITHIN_72_HOURS",
  "plan_digest": "REPLACE_WITH_CANONICAL_REVIEWED_PLAN_DIGEST"
}
```

The digest binds approval to plan content; it is an application control, not a public checksum handoff file. The protected review job computes it from canonical JSON with sorted keys and compact separators. Approval timestamps and approver membership come from the trusted approval process, not fields submitted by an infrastructure PR.

```bash
python scripts/governance.py .private/reviewed-plan.json \
  --approval-repository PATH_TO_SEPARATELY_PROTECTED_CHECKOUT \
  --approval-commit EXACT_APPROVED_COMMIT
```

The script reads committed Git objects and verifies the expected approval commit, rather than trusting a dirty checkout. This protects only when the approval repository, its commit input, job code, and credential boundary are themselves protected. Do not let a contributor choose their own approval repository or expected commit. A legitimate recovery replacement may need multiple separately scoped exceptions; a broad “allow everything during incident” switch defeats the control.

### Drift without undoing an emergency fix

Create a normal plan with refresh enabled and compare `resource_drift[].change.after` (observed reality) with `resource_changes[].change.after` (proposed result). If a responder narrowed a CIDR while old code still declares `0.0.0.0/0`, reconciliation would widen access. Preserve the approved restriction in code before applying. The `drift_direction` helper and its test exercise that direction correctly.

Use CloudTrail/change records and controller ownership to classify changes. A refresh-only plan is useful evidence but does not show the same corrective actions as a normal plan. Do not automatically import, ignore, or revert every detected difference. Require a new reviewed plan after repairing configuration or state.

Acceptance: risky changes fail with understandable reasons, valid reviewed exceptions permit the exact necessary action, and expired approvals fail. Publish dangerous/compliant plans with sensitive data removed, policy tests, exception lifecycle, and drift reconciliation evidence. Delete only disposable test resources; retain audit evidence according to policy.

## 10. Coordinate people and automation during an incident

### Business problem and architecture

Checkout fails because the database is saturated. Application alerts, database alarms, and queue symptoms arrive together. Without coordination, engineers can duplicate investigation or launch conflicting recovery actions.

The local intake API authenticates a trusted alert sender, deduplicates event IDs, correlates service/dependency/environment within a 15-minute window, attaches service ownership and severity, and records a timeline in SQLite. It uses a transaction to grant one remediation claim per incident. This is a single-host lab store; a replicated production intake needs a shared transactional authority and tested high-availability behavior.

```mermaid
flowchart LR
  Alerts[Authenticated alerts] --> Intake[Deduplicate and correlate]
  Intake --> Ownership[Service owner and incident commander]
  Ownership --> Approval[Protected operator approval]
  Approval --> Claim[One durable remediation claim]
  Claim --> SSM[Allowlisted SSM automation]
  SSM --> Verify[Independent checkout and SLO checks]
  Verify --> Review[Timeline and postmortem]
```

### Run the intake exercise

```bash
export INCIDENT_API_TOKEN="$(python -c 'import secrets; print(secrets.token_urlsafe(32))')"
python -m uvicorn scripts.incident_api:app --host 127.0.0.1 --port 18086
```

In another terminal with the same token set, submit both fixture alerts:

```bash
python scripts/send_alerts.py --url http://127.0.0.1:18086
```

Both alerts should map to one incident. Repeating the same event ID should not create another alert. The CLI/API token authenticates intake; an incoming alert cannot approve a remediation by setting an `approver` field.

Declare an incident commander and distinct application/database/infrastructure owners. Severity should reflect customer impact and SLO burn evidence, not the number of alert sources. The teaching classifier uses a high burn rate plus impact to select SEV1 and records derived ownership; replace the small directory with your approved service/on-call source before operating it.

### Control recovery actions

```bash
export AUTHENTICATED_OPERATOR=veriqta-lab-operator
python scripts/incident_operator.py claim YOUR_INCIDENT_ID --runbook diagnose-database
python scripts/incident_operator.py report YOUR_INCIDENT_ID
```

The environment variable is a local lab identity hint, not an authentication system. Run the operator path only behind an authenticated, protected operator environment. Production approval must come from verified identity/group membership and auditable authorization. The intake API deliberately exposes no privileged approval endpoint.

Eight concurrent local claim attempts are tested; exactly one succeeds. Do not reset the claim merely because an external call times out. An action might have executed even if its response was lost. Inspect the external execution state, use deterministic idempotency tokens, and require a new decision before selecting a conflicting runbook.

### Use an allowlisted SSM document

The `incidents` Terraform root creates `veriqta-diagnose-database` and an SSM execution role that can describe RDS instances. It cannot scale or delete a database or run arbitrary shell commands. Supply the common account/Region/name inputs, then review/apply the root.

The operator needs `ssm:StartAutomationExecution` on the approved document/version and `iam:PassRole` only for that execution role, with `iam:PassedToService=ssm.amazonaws.com`. Do not grant permission to run every SSM document. Use an approved SSO operator session:

```bash
python scripts/ssm_operator.py YOUR_INCIDENT_ID \
  --database veriqta9-primary-db \
  --execution-role YOUR_DIAGNOSTIC_EXECUTION_ROLE_ARN
aws ssm get-automation-execution --automation-execution-id YOUR_EXECUTION_ID
```

The script uses the incident UUID as SSM's client token and persists the execution ID. Retries must use identical runbook/role/database parameters. Diagnostic automation is not recovery; after diagnosing saturation, perform a separately approved capacity or application correction, with bounds, rollback criteria, and its own least-privilege runbook. Never assume an automatic restart fixes a database bottleneck.

### Full incident simulation

Start normal local traffic and telemetry, inject the bounded database lock or a controlled pool-pressure fault, send overlapping alerts, assign owners, record the decision, and execute the diagnostic path. Restore the actual dependency/capacity problem. Verify a new checkout transaction, the error fraction, and latency using independent signals—not merely the status of the runbook that made the change.

```json
{"checkout": true, "latency": true, "error_rate": true}
```

Save actual independently measured checks in a private file, then resolve the incident:

```bash
python scripts/incident_operator.py resolve YOUR_INCIDENT_ID --checks .private/recovery-checks.json
python scripts/incident_operator.py report YOUR_INCIDENT_ID > .private/incident-report.json
```

The helper refuses resolution when any required signal is absent or false. It cannot prove that a supplied boolean is an honest measurement; production verification must obtain trusted observations directly. Keep that trust boundary explicit.

Acceptance: correlated intake, clear ownership, no duplicate/conflicting remediation, verified service recovery, and a complete postmortem. Include root cause, contributing conditions, UTC timeline, customer impact, what worked, what failed, and corrective actions with owners and verification conditions. Clear the fault and confirm normal service before stopping the lab.

## What every GitHub project must contain

A portfolio repository should let another engineer reproduce the system and evaluate its behavior. Adapt directories to the project rather than adding empty folders solely to resemble a template.

```text
project-name/
├── README.md
├── architecture/
├── application/
├── infrastructure/
├── automation/
├── policies/
├── tests/
├── observability/
├── incidents/
├── evidence/
├── docs/
│   ├── decisions/
│   ├── runbooks/
│   └── threat-model.md
└── .github/
    └── workflows/
```

This handbook uses shared `application/`, `engineering/`, `scripts/`, `infrastructure/`, `kubernetes/`, `observability/`, and `policies/` directories to keep one authoritative implementation of common behavior. Each numbered project has an entry point. When extracting a standalone portfolio repository, carry its imported modules, dependency locks, configurations, and tests with it; do not leave imports pointing at a private working directory.

A strong README includes the business problem, architecture diagram, prerequisites, exact setup/deployment process, expected output and verification, controlled failure tests, recovery process, cost considerations, cleanup, and explicit operating assumptions. Include a threat model and design decisions. Publish actual measured evidence, including failures; a screenshot of a dashboard alone is not proof of recovery or safety.

The supplied `docs/threat-model.md`, `docs/decisions.md`, `docs/incident-review-template.md`, and `evidence/README.md` provide a starting structure. Keep real credentials, customer data, sensitive logs, raw state/plans, internal identities, and unredacted cloud account details out of public repositories. A synthetic fixture should remain labeled as a fixture rather than becoming a claimed production success.

## Cleanup and retirement

### Local lab

Stop traffic generators, unlock experimental database transactions, clear temporary environment overrides, and stop extra Uvicorn processes. Inspect state before removing volumes:

```bash
python scripts/lab.py ps
python scripts/lab.py --profile observability down --remove-orphans
# Only when the local databases and retained telemetry are no longer needed:
python scripts/lab.py --profile observability down -v --remove-orphans
```

The final command deletes the lab's database and telemetry volumes. Keep any required encrypted backups and their separate keys before running it. Do not delete a primary volume as a substitute for diagnosing a recoverable connection problem.

### Cloud consumers before foundations

1. Stop fault experiments and load generation, restore normal readiness, and capture the final independent checks.
2. Remove canary/blue-green ingress, ALBs, rollout resources, and other controller-managed cloud objects while their controllers and IAM permissions are still running. A deleted cluster cannot finish an ALB controller's cleanup.
3. Remove disposable preview namespaces only after checking their owner, expiry, and data-retention requirements. Revoke temporary template/publishing credentials through the approved process.
4. Remove application workloads and Pod Identity associations, then retire the cluster root with a reviewed destroy plan. Verify controller-created load balancers, target groups, ENIs, and log groups separately; Terraform owns only the resources in its state.
5. Disable backup schedules before retiring vaults. Retain required copied recovery points and snapshots. Delete only versions/objects whose approved retention has ended; nonempty versioned buckets and backup vaults will resist deletion.
6. For a disposable foundation DB, set `deletion_protection=false` and choose a unique `final_snapshot_suffix`, then plan/apply that preparation while the original full configuration is present. Verify the proposed snapshot name does not collide with an existing snapshot. Do not set `skip_final_snapshot=true` to bypass a retirement error.
7. Preserve the data key for every retained snapshot, object, secret, or restored DB that still needs it. `prevent_destroy` intentionally stops a blind whole-foundation destroy.

To retire disposable foundation consumers while retaining their key, use a reviewed configuration change after their dependent cluster/backups/data can be retired. Export protected state evidence first. Replace only that foundation root's `main.tf` with `infrastructure/retain-data-key.tf.example`, keep the existing backend/provider and the same account/Region/name inputs, and remove obsolete tfvars for variables no longer declared. Create a **normal plan**, inspect every deletion, and apply only after confirming that `aws_kms_key.data` is unchanged and not being deleted or replaced. The small remaining root continues managing the retained key. Keep the full original configuration if its bucket/vault resources still require management.

Do not restore the original full configuration and apply it unless you intend to recreate its deleted resources. Key retirement is a later approved action after proving no retained resource depends on it. A pending-deletion key can prevent decryption even before its final deletion date.

Retire diagnostic/delivery roles only after cleanup operations that need them are complete. Keep backend access and key access until every consumer state has been archived or deliberately migrated. The backend's protected buckets/key have their own retirement procedure; deleting state is not ordinary workload cleanup. Review later billing reports for retained snapshots, AMI images/backing snapshots, logs, endpoints, NAT, public IPv4, or manually restored resources outside Terraform ownership.

## Troubleshooting

| Symptom | Investigate | Avoid |
|---|---|---|
| `docker compose` is unavailable | Install the Compose v2 plugin or start Docker Desktop | Assuming the Docker CLI alone supplies a running engine |
| Database container is healthy but checkout fails | Schema initialization, dependency URLs, locks, pool limits | Treating `pg_isready` as a complete application test |
| Pod restarts during DB outage | Liveness/readiness design and dependency wiring | Dependency-driven liveness restart storms |
| HPA cannot get metrics | Metrics Server, requests, resource metrics and target kind | Assuming a larger HPA maximum creates worker nodes |
| Replacement pods remain pending | Node supply, quotas, AZ capacity, IP space, topology constraints | Restarting the last healthy pods |
| Image pulls but verification fails | Exact signer/issuer, subject digest, registry auth and policy matches | Disabling admission to make the rollout pass |
| Canary has no metric result | Scraping, revision labels, fresh windows, actual routed traffic | Interpreting no data as success |
| Trace is incomplete | Context propagation, tail-sampler routing, queue/memory loss | Randomly balancing spans across stateful samplers |
| Restore succeeds but app fails | Destination keys, credentials, network, engine settings and markers | Calling a green restore job business recovery |
| New region can read stale ownership | Same-authority enforcement and old-writer fencing | Treating a copied lease row or DNS switch as global authority |
| Policy blocks a legitimate recovery | Exact risk finding, trusted scoped exception, expiry and plan binding | Removing the guard or approving an unrelated replan |
| Duplicate alert does work twice | Event namespace, durable claim and external idempotency token | Retrying with a new token after an ambiguous response |
| Key deletion is blocked | Retained encrypted data and resource ownership | Removing protection merely to make destroy finish |

## Senior project portfolio

Use each system to demonstrate a specific engineering judgment:

1. **Resilience:** distinguish safe remediation from actions that amplify an outage.
2. **Delivery:** verify artifacts independently and maintain a defensible trust chain.
3. **Recovery verification:** prove data and business behavior, not only backup completion.
4. **Observability:** explain an incident using correlated evidence.
5. **Developer experience:** remove unnecessary tickets while keeping authority constrained.
6. **FinOps:** reject savings that damage reliability or recovery.
7. **Progressive delivery:** stop a bad release using customer-impact signals.
8. **Write ownership:** prevent conflicting commits during ambiguous failure.
9. **Governance:** block dangerous plans while keeping legitimate reviewed recovery possible.
10. **Incident command:** coordinate people and controlled automation with accountable outcomes.

These are stronger portfolio claims when their scope is precise. A local exercise proves local behavior; a real regional recovery claim requires the regional experiment, its data reconciliation, and its measured limitations.

## Complete code reference

Every companion implementation below is also available at its linked path. Keep folder relationships intact. Standard Terraform and Python dependency locks remain alongside the code.

### [.dockerignore](.dockerignore)

````text
.git
.private
artifacts
.venv
**/.terraform
**/__pycache__
````

### [.gitignore](.gitignore)

````text
.private/
artifacts/
.venv/
__pycache__/
*.pyc
.terraform/
*.tfstate*
*.tfplan
*.tfvars
*.tfvars.json
!*.tfvars.example
*.hcl.private
.env
node_modules/
dist/
*.egg-info/
build/
dist/
````

### [application/Dockerfile](application/Dockerfile)

````text
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
ADD https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem /app/rds-ca.pem
RUN chmod 644 /app/rds-ca.pem
COPY application /app/application
USER 10001:10001
EXPOSE 8080
CMD ["uvicorn","application.api:app","--host","0.0.0.0","--port","8080","--workers","1"]
````

### [application/__init__.py](application/__init__.py)

````python

````

### [application/api.py](application/api.py)

````python
import json
import logging
import os
import time
from contextlib import asynccontextmanager
import httpx
from fastapi import FastAPI,HTTPException,Request
from fastapi.responses import JSONResponse,Response
from prometheus_client import Counter,Histogram,Gauge,generate_latest,CONTENT_TYPE_LATEST
from opentelemetry import trace,propagate
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.trace import Status,StatusCode,SpanKind
from application.db import pool,initialize
from application.ledger import write,Fenced,Conflict

SERVICE=os.getenv('SERVICE_NAME','checkout')
provider=TracerProvider(resource=Resource.create({'service.name':SERVICE,'service.version':os.getenv('RELEASE','v1')}))
if os.getenv('OTEL_EXPORTER_OTLP_ENDPOINT'):
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=os.environ['OTEL_EXPORTER_OTLP_ENDPOINT'].rstrip('/')+'/v1/traces')))
trace.set_tracer_provider(provider)
tracer=trace.get_tracer('veriqta')
if os.getenv('OTEL_EXPORTER_OTLP_ENDPOINT'):
    from opentelemetry.sdk._logs import LoggerProvider,LoggingHandler
    from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
    from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter
    logs=LoggerProvider(resource=Resource.create({'service.name':SERVICE}))
    logs.add_log_record_processor(BatchLogRecordProcessor(OTLPLogExporter(endpoint=os.environ['OTEL_EXPORTER_OTLP_ENDPOINT'].rstrip('/')+'/v1/logs')))
    logging.getLogger().addHandler(LoggingHandler(level=logging.INFO,logger_provider=logs))
requests=Counter('veriqta_http_requests_total','Completed requests',['service','route','status','release'])
latency=Histogram('veriqta_http_duration_seconds','Request duration',['service','route','release'],buckets=(.01,.05,.1,.25,.5,1,2,5,10))
active=Gauge('veriqta_http_active','In-flight requests',['service'])
logging.basicConfig(level=logging.INFO,format='%(message)s')
logging.getLogger().setLevel(logging.INFO)

@asynccontextmanager
async def lifespan(app):
    # Schema migration is explicit; replicas do not race to perform DDL at startup.
    pool().wait(timeout=30)
    yield
    pool().close()

app=FastAPI(title='Veriqta engineering lab',lifespan=lifespan)

@app.middleware('http')
async def telemetry(request,call_next):
    start=time.monotonic();status=500
    route=request.url.path if request.url.path in ('/healthz','/readyz','/checkout','/pay','/reserve','/ledger','/metrics') else '/other'
    active.labels(SERVICE).inc()
    with tracer.start_as_current_span(SERVICE+route,context=propagate.extract(dict(request.headers)),kind=SpanKind.SERVER) as span:
        try:
            result=await call_next(request);status=result.status_code
            if status>=500:span.set_status(Status(StatusCode.ERROR))
            return result
        finally:
            elapsed=time.monotonic()-start
            requests.labels(SERVICE,route,str(status),os.getenv('RELEASE','v1')).inc()
            latency.labels(SERVICE,route,os.getenv('RELEASE','v1')).observe(elapsed)
            active.labels(SERVICE).dec()
            logging.info(json.dumps({'service':SERVICE,'route':route,'status':status,'duration_ms':round(elapsed*1000,2),'trace_id':format(span.get_span_context().trace_id,'032x'),'release':os.getenv('RELEASE','v1')}))

@app.get('/healthz')
def health():return {'process':'alive'}

@app.get('/readyz')
def ready():
    try:
        with pool().connection() as conn:conn.execute('SELECT 1')
        return {'database':'reachable'}
    except Exception:raise HTTPException(503,'database unavailable')

@app.get('/metrics')
def metrics():return Response(generate_latest(),media_type=CONTENT_TYPE_LATEST)

def call(url,key):
    with tracer.start_as_current_span('dependency '+url,kind=SpanKind.CLIENT):
        headers={'Idempotency-Key':key};propagate.inject(headers)
        with httpx.Client(timeout=4) as client:
            response=client.post(url,headers=headers)
            response.raise_for_status()
            return response.json()

@app.post('/checkout')
def checkout(request:Request):
    key=request.headers.get('Idempotency-Key','')
    if not key or len(key)>100:raise HTTPException(400,'use an idempotency key up to 100 characters')
    try:
        if SERVICE=='gateway':return call(os.getenv('CHECKOUT_URL','http://checkout:8080/checkout'),key)
        call(os.getenv('PAYMENT_URL','http://payment:8080/pay'),key)
        call(os.getenv('INVENTORY_URL','http://inventory:8080/reserve'),key)
        with pool().connection() as conn:
            conn.execute('INSERT INTO orders(id,amount_cents) VALUES (%s,1000) ON CONFLICT DO NOTHING',(key,))
            conn.execute('INSERT INTO outbox(id) VALUES (%s) ON CONFLICT DO NOTHING',(key,))
        return {'order':key,'status':'accepted'}
    except Exception:
        logging.exception('checkout failed')
        raise HTTPException(503,'checkout unavailable')

@app.post('/pay')
def pay():
    delay=float(os.getenv('PAYMENT_DELAY_SECONDS','0'))
    time.sleep(min(max(delay,0),5))
    if os.getenv('PAYMENT_FAIL','false')=='true':raise HTTPException(503,'injected payment failure')
    return {'simulation':'payment approved; no external money movement'}

@app.post('/reserve')
def reserve():
    try:
        with pool().connection() as conn:conn.execute('SELECT available FROM inventory WHERE id=1 FOR UPDATE').fetchone()
        return {'simulation':'inventory checked; no stock mutation'}
    except Exception:raise HTTPException(503,'inventory dependency unavailable')

@app.post('/ledger')
async def ledger(request:Request):
    body=await request.json()
    try:
        key=request.headers.get('Idempotency-Key','')
        if not key or len(key)>100:raise ValueError('invalid idempotency key')
        amount=body['amount_cents']
        if type(amount) is not int:raise ValueError('integer cents required')
        with pool().connection() as conn:
            created=write(conn,os.getenv('WRITE_OWNER','primary'),int(os.getenv('WRITE_EPOCH','1')),key,amount)
        return {'created':created,'key':key}
    except Fenced:raise HTTPException(409,'writer fenced')
    except (Conflict,ValueError,KeyError,TypeError):raise HTTPException(400,'invalid or conflicting transaction')
````

### [application/db.py](application/db.py)

````python
import json
import os
import time
from functools import lru_cache
from pathlib import Path
import boto3
from psycopg.conninfo import make_conninfo
from psycopg_pool import ConnectionPool

@lru_cache(maxsize=1)
def pool():
    if os.getenv('DATABASE_URL'):
        conninfo=os.environ['DATABASE_URL']
    else:
        secret=json.loads(boto3.client('secretsmanager').get_secret_value(SecretId=os.environ['DB_SECRET_ARN'])['SecretString'])
        conninfo=make_conninfo(host=os.environ['DB_HOST'],dbname='veriqta',user=secret['username'],
                              password=secret['password'],sslmode='verify-full',
                              sslrootcert='/app/rds-ca.pem',connect_timeout=3)
    return ConnectionPool(conninfo,min_size=1,max_size=int(os.getenv('POOL_SIZE','5')),
                          timeout=2,kwargs={'options':'-c statement_timeout=3000 -c lock_timeout=1500'})

def initialize():
    with pool().connection() as conn:
        conn.execute(Path(__file__).with_name('schema.sql').read_text())
````

### [application/ledger.py](application/ledger.py)

````python
"""Write ownership is checked under the same database lock/transaction as the write."""
class Fenced(Exception): pass
class Conflict(Exception): pass

def write(conn, owner, epoch, key, amount):
    if amount <= 0:
        raise ValueError('amount must be positive')
    authority=conn.execute('SELECT owner,epoch,expires_at>clock_timestamp() FROM write_authority WHERE id=1 FOR UPDATE').fetchone()
    if authority is None or authority != (owner,epoch,True):
        raise Fenced('writer is not current or lease expired')
    row=conn.execute('SELECT amount_cents FROM ledger WHERE idempotency_key=%s',(key,)).fetchone()
    if row:
        if row[0] != amount: raise Conflict('idempotency key reused with a different amount')
        return False
    conn.execute('INSERT INTO ledger(idempotency_key,amount_cents,owner,epoch) VALUES (%s,%s,%s,%s)',(key,amount,owner,epoch))
    return True

def promote(conn, expected_owner, expected_epoch, new_owner, seconds=300):
    if new_owner == expected_owner or not 1 <= seconds <= 3600:
        raise ValueError('invalid promotion')
    row=conn.execute('SELECT owner,epoch FROM write_authority WHERE id=1 FOR UPDATE').fetchone()
    if row != (expected_owner,expected_epoch):raise Fenced('authority changed; review again')
    conn.execute("UPDATE write_authority SET owner=%s,epoch=epoch+1,expires_at=clock_timestamp()+(%s*interval '1 second') WHERE id=1",(new_owner,seconds))
    return expected_epoch+1
````

### [application/schema.sql](application/schema.sql)

````sql
CREATE TABLE IF NOT EXISTS orders (
 id text PRIMARY KEY,
 amount_cents bigint NOT NULL CHECK (amount_cents > 0),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE IF NOT EXISTS outbox (
 id text PRIMARY KEY REFERENCES orders(id),
 delivered boolean NOT NULL DEFAULT false
);
CREATE TABLE IF NOT EXISTS receipts (
 id text PRIMARY KEY REFERENCES orders(id),
 processed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE IF NOT EXISTS inventory (id integer PRIMARY KEY, available integer NOT NULL);
INSERT INTO inventory VALUES (1,100000) ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS write_authority (
 id integer PRIMARY KEY CHECK(id=1), owner text NOT NULL, epoch bigint NOT NULL,
 expires_at timestamptz NOT NULL
);
INSERT INTO write_authority VALUES (1,'primary',1,clock_timestamp()+interval '1 hour') ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS ledger (
 idempotency_key text PRIMARY KEY, amount_cents bigint NOT NULL CHECK(amount_cents>0),
 owner text NOT NULL, epoch bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
````

### [application/worker.py](application/worker.py)

````python
"""PostgreSQL outbox locally; SQS transport optionally. Both paths make effects idempotent."""
import json,os,time,logging
import boto3
from application.db import pool

def local_once():
    with pool().connection() as conn:
        row=conn.execute('SELECT id FROM outbox WHERE NOT delivered FOR UPDATE SKIP LOCKED LIMIT 1').fetchone()
        if row:
            conn.execute('INSERT INTO receipts(id) VALUES (%s) ON CONFLICT DO NOTHING',(row[0],))
            conn.execute('UPDATE outbox SET delivered=true WHERE id=%s',(row[0],))
        return row is not None

def sqs_once(client,url):
    # Publishing can succeed before a DB commit; duplicate deliveries are expected.
    with pool().connection() as conn:
        row=conn.execute('SELECT id FROM outbox WHERE NOT delivered FOR UPDATE SKIP LOCKED LIMIT 1').fetchone()
        if row:
            client.send_message(QueueUrl=url,MessageBody=json.dumps({'id':row[0]}))
            conn.execute('UPDATE outbox SET delivered=true WHERE id=%s',(row[0],))
    for message in client.receive_message(QueueUrl=url,MaxNumberOfMessages=10,WaitTimeSeconds=1).get('Messages',[]):
        key=json.loads(message['Body'])['id']
        with pool().connection() as conn:conn.execute('INSERT INTO receipts(id) VALUES (%s) ON CONFLICT DO NOTHING',(key,))
        # A crash before deletion replays the message, not the business effect.
        client.delete_message(QueueUrl=url,ReceiptHandle=message['ReceiptHandle'])

if __name__=='__main__':
    logging.basicConfig(level=logging.INFO)
    url=os.getenv('QUEUE_URL');client=boto3.client('sqs') if url else None
    while True:
        try:
            sqs_once(client,url) if url else local_once()
        except Exception:logging.exception('worker iteration failed; message retained for retry')
        time.sleep(1)
````

### [compose.yaml](compose.yaml)

````yaml
name: veriqta9
services:
  primary:
    image: postgres:17.6
    environment:
      POSTGRES_USER: veriqta
      POSTGRES_DB: veriqta
      POSTGRES_PASSWORD: ${PGPASSWORD:?run scripts/init_lab.py}
    ports:
    - 127.0.0.1:15432:5432
    volumes:
    - primary:/var/lib/postgresql/data
    healthcheck:
      test:
      - CMD-SHELL
      - pg_isready -U veriqta -d veriqta
      interval: 3s
      timeout: 3s
      retries: 20
  recovery:
    image: postgres:17.6
    environment:
      POSTGRES_USER: veriqta
      POSTGRES_DB: veriqta
      POSTGRES_PASSWORD: ${PGPASSWORD:?run scripts/init_lab.py}
    ports:
    - 127.0.0.1:15433:5432
    volumes:
    - recovery:/var/lib/postgresql/data
    healthcheck:
      test:
      - CMD-SHELL
      - pg_isready -U veriqta -d veriqta
      interval: 3s
      timeout: 3s
      retries: 20
  gateway:
    build:
      context: .
      dockerfile: application/Dockerfile
    image: veriqta9-app:local
    environment:
      SERVICE_NAME: gateway
      DATABASE_URL: postgresql://veriqta:${PGPASSWORD}@primary:5432/veriqta
      PAYMENT_URL: http://payment:8080/pay
      INVENTORY_URL: http://inventory:8080/reserve
      OTEL_EXPORTER_OTLP_ENDPOINT: http://otel:4318
      PAYMENT_DELAY_SECONDS: ${PAYMENT_DELAY_SECONDS:-0}
      PAYMENT_FAIL: ${PAYMENT_FAIL:-false}
      RELEASE: ${RELEASE:-v1}
    ports:
    - 127.0.0.1:18080:8080
    depends_on:
      primary:
        condition: service_healthy
    read_only: true
    tmpfs:
    - /tmp
    cap_drop:
    - ALL
    security_opt:
    - no-new-privileges:true
  checkout:
    build:
      context: .
      dockerfile: application/Dockerfile
    image: veriqta9-app:local
    environment:
      SERVICE_NAME: checkout
      DATABASE_URL: postgresql://veriqta:${PGPASSWORD}@primary:5432/veriqta
      PAYMENT_URL: http://payment:8080/pay
      INVENTORY_URL: http://inventory:8080/reserve
      OTEL_EXPORTER_OTLP_ENDPOINT: http://otel:4318
      PAYMENT_DELAY_SECONDS: ${PAYMENT_DELAY_SECONDS:-0}
      PAYMENT_FAIL: ${PAYMENT_FAIL:-false}
      RELEASE: ${RELEASE:-v1}
    ports:
    - 127.0.0.1:18081:8080
    depends_on:
      primary:
        condition: service_healthy
    read_only: true
    tmpfs:
    - /tmp
    cap_drop:
    - ALL
    security_opt:
    - no-new-privileges:true
  payment:
    build:
      context: .
      dockerfile: application/Dockerfile
    image: veriqta9-app:local
    environment:
      SERVICE_NAME: payment
      DATABASE_URL: postgresql://veriqta:${PGPASSWORD}@primary:5432/veriqta
      PAYMENT_URL: http://payment:8080/pay
      INVENTORY_URL: http://inventory:8080/reserve
      OTEL_EXPORTER_OTLP_ENDPOINT: http://otel:4318
      PAYMENT_DELAY_SECONDS: ${PAYMENT_DELAY_SECONDS:-0}
      PAYMENT_FAIL: ${PAYMENT_FAIL:-false}
      RELEASE: ${RELEASE:-v1}
    ports:
    - 127.0.0.1:18082:8080
    depends_on:
      primary:
        condition: service_healthy
    read_only: true
    tmpfs:
    - /tmp
    cap_drop:
    - ALL
    security_opt:
    - no-new-privileges:true
  inventory:
    build:
      context: .
      dockerfile: application/Dockerfile
    image: veriqta9-app:local
    environment:
      SERVICE_NAME: inventory
      DATABASE_URL: postgresql://veriqta:${PGPASSWORD}@primary:5432/veriqta
      PAYMENT_URL: http://payment:8080/pay
      INVENTORY_URL: http://inventory:8080/reserve
      OTEL_EXPORTER_OTLP_ENDPOINT: http://otel:4318
      PAYMENT_DELAY_SECONDS: ${PAYMENT_DELAY_SECONDS:-0}
      PAYMENT_FAIL: ${PAYMENT_FAIL:-false}
      RELEASE: ${RELEASE:-v1}
    ports:
    - 127.0.0.1:18083:8080
    depends_on:
      primary:
        condition: service_healthy
    read_only: true
    tmpfs:
    - /tmp
    cap_drop:
    - ALL
    security_opt:
    - no-new-privileges:true
  worker:
    image: veriqta9-app:local
    command:
    - python
    - -m
    - application.worker
    environment:
      DATABASE_URL: postgresql://veriqta:${PGPASSWORD}@primary:5432/veriqta
    depends_on:
      primary:
        condition: service_healthy
    read_only: true
    tmpfs:
    - /tmp
    cap_drop:
    - ALL
  otel:
    image: otel/opentelemetry-collector-contrib:0.137.0
    profiles:
    - observability
    volumes:
    - ./observability/collector.yaml:/etc/otel.yaml:ro
    ports: []
    command:
    - --config=/etc/otel.yaml
  prometheus:
    image: prom/prometheus:v3.7.1
    profiles:
    - observability
    volumes:
    - ./observability/prometheus.yaml:/etc/prometheus/prometheus.yaml:ro
    - ./observability/alerts.yaml:/etc/prometheus/alerts.yaml:ro
    ports:
    - 127.0.0.1:19090:9090
    command:
    - --config.file=/etc/prometheus/prometheus.yaml
    - --storage.tsdb.retention.time=24h
  tempo:
    image: grafana/tempo:2.8.2
    profiles:
    - observability
    volumes:
    - ./observability/tempo.yaml:/etc/tempo.yaml:ro
    - tempo:/var/tempo
    ports:
    - 127.0.0.1:13200:3200
    command:
    - -config.file=/etc/tempo.yaml
  loki:
    image: grafana/loki:3.5.7
    profiles:
    - observability
    volumes:
    - ./observability/loki.yaml:/etc/loki.yaml:ro
    - loki:/loki
    ports:
    - 127.0.0.1:13100:3100
    command:
    - -config.file=/etc/loki.yaml
  grafana:
    image: grafana/grafana:12.2.0
    profiles:
    - observability
    volumes:
    - grafana:/var/lib/grafana
    - ./observability/grafana/datasources:/etc/grafana/provisioning/datasources:ro
    - ./observability/grafana/dashboards:/etc/grafana/provisioning/dashboards:ro
    - ./observability/grafana/dashboard.json:/var/lib/grafana/dashboards/veriqta.json:ro
    ports:
    - 127.0.0.1:13000:3000
    environment:
      GF_AUTH_ANONYMOUS_ENABLED: 'false'
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_PASSWORD:?regenerate missing local secret
        via scripts/init_lab.py}
volumes:
  primary: {}
  recovery: {}
  grafana: {}
  tempo: {}
  loki: {}
````

### [engineering/__init__.py](engineering/__init__.py)

````python

````

### [engineering/finops.py](engineering/finops.py)

````python
"""Recommend only. Missing evidence rejects an action rather than treating missing usage as idle."""
from decimal import Decimal

def assess(row):
    import math
    reasons=[]
    for tag in ('owner','application','environment'):
        if not row.get(tag):reasons.append('missing '+tag)
    if row.get('observation_days',0)<14:reasons.append('insufficient observation window')
    if row.get('telemetry_age_minutes',9999)>60:reasons.append('stale telemetry')
    if row.get('critical_database',True):reasons.append('critical database requires an independent migration review')
    if row.get('standby_required',True):reasons.append('required recovery capacity')
    if row.get('remaining_peak_capacity',0)<row.get('required_peak_capacity',1):reasons.append('insufficient surviving capacity')
    for metric in ('p95_seconds','error_rate','rto_seconds','rpo_seconds'):
        values=(row.get(metric),row.get(metric+'_limit'))
        if any(type(v) not in (int,float) or not math.isfinite(v) or v<0 for v in values) or values[0]>values[1]:reasons.append('unproven '+metric)
    savings=Decimal(str(row.get('estimated_monthly_savings',0)))
    if not savings.is_finite() or savings<=0:reasons.append('no valid positive saving')
    if not row.get('rollback'):reasons.append('missing rollback')
    return {'resource':row.get('resource','unknown'),'owner':row.get('owner','unassigned'),
            'decision':'REJECT' if reasons else 'RECOMMEND_REVIEW','reasons':reasons,
            'estimated_monthly_savings':str(savings),'currency':row.get('currency','UNSPECIFIED')}
````

### [engineering/governance.py](engineering/governance.py)

````python
"""Normalize plans for review; exceptions must come from a separately trusted approval process."""
import datetime as dt,hashlib,json

def validate_exception(exception,plan,approvers,now=None):
    now=now or dt.datetime.now(dt.timezone.utc)
    expiry=dt.datetime.fromisoformat(exception['expires_at'])
    issued=dt.datetime.fromisoformat(exception['issued_at'])
    if issued.tzinfo is None or expiry.tzinfo is None:raise ValueError('timezone required')
    if not issued<=now<expiry or (expiry-issued).total_seconds()>259200:raise ValueError('exception expired or exceeds 72 hours')
    if exception['approver'] not in approvers or exception['approver']==exception['requester']:raise ValueError('independent trusted approver required')
    digest=hashlib.sha256(json.dumps(plan,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    if exception['plan_digest']!=digest:raise ValueError('approval is for a different plan')
    if not exception.get('ticket') or not exception.get('resource') or not exception.get('rule'):raise ValueError('exact scope and change ticket required')
    return True

def drift_direction(observed,desired):
    import ipaddress
    try:
        a,b=ipaddress.ip_network(observed),ipaddress.ip_network(desired)
        if a==b:return 'unchanged'
        if a.version!=b.version:return 'review'
        return 'widening' if a.subnet_of(b) else 'narrowing' if b.subnet_of(a) else 'review'
    except (ValueError,TypeError):return 'unknown'
````

### [engineering/incident.py](engineering/incident.py)

````python
"""Durable local incident store. BEGIN IMMEDIATE serializes remediation claims."""
import json,sqlite3,time,uuid
class IncidentStore:
    def __init__(self,path):
        self.path=str(path)
        with self.connect() as c:
            c.executescript("""
            CREATE TABLE IF NOT EXISTS incidents(id TEXT PRIMARY KEY,correlation TEXT,opened REAL,status TEXT);
            CREATE TABLE IF NOT EXISTS alerts(event_id TEXT PRIMARY KEY,incident_id TEXT,payload TEXT);
            CREATE TABLE IF NOT EXISTS actions(incident_id TEXT PRIMARY KEY,runbook TEXT,status TEXT,approver TEXT,execution_id TEXT);
            CREATE TABLE IF NOT EXISTS timeline(incident_id TEXT,at REAL,event TEXT);
            """)
    def connect(self):return sqlite3.connect(self.path,timeout=10,isolation_level=None)
    def ingest(self,event,now=None):
        now=time.time() if now is None else now
        for key in ('event_id','service','dependency','environment'):
            if not isinstance(event.get(key),str) or not event[key]:raise ValueError('missing '+key)
        event=dict(event)
        event['owner']='veriqta-platform' if event['service']=='checkout' else 'unassigned-escalate'
        burn=float(event.get('burn_rate',0))
        event['severity']='SEV1' if burn>=14.4 and event.get('impact') else 'SEV2' if burn>=6 else 'SEV3'
        correlation='|'.join(event[k] for k in ('environment','service','dependency'))
        with self.connect() as c:
            c.execute('BEGIN IMMEDIATE')
            old=c.execute('SELECT incident_id FROM alerts WHERE event_id=?',(event['event_id'],)).fetchone()
            if old:c.commit();return old[0]
            row=c.execute("SELECT id FROM incidents WHERE correlation=? AND status='open' AND opened>=? ORDER BY opened DESC LIMIT 1",(correlation,now-900)).fetchone()
            incident=row[0] if row else str(uuid.uuid4())
            if not row:c.execute('INSERT INTO incidents VALUES (?,?,?,?)',(incident,correlation,now,'open'))
            c.execute('INSERT INTO alerts VALUES (?,?,?)',(event['event_id'],incident,json.dumps(event)))
            c.execute('INSERT INTO timeline VALUES (?,?,?)',(incident,now,'alert '+event['event_id']))
            c.commit();return incident
    def claim(self,incident,runbook,approver):
        if runbook not in ('diagnose-database','restore-capacity'):raise ValueError('runbook not allowlisted')
        if not approver:raise ValueError('trusted authenticated approval required')
        with self.connect() as c:
            c.execute('BEGIN IMMEDIATE')
            if not c.execute("SELECT id FROM incidents WHERE id=? AND status='open'",(incident,)).fetchone():raise ValueError('open incident required')
            try:c.execute('INSERT INTO actions VALUES (?,?,?,?,?)',(incident,runbook,'claimed',approver,None))
            except sqlite3.IntegrityError:c.rollback();return False
            c.execute('INSERT INTO timeline VALUES (?,?,?)',(incident,time.time(),'approved '+runbook+' by '+approver))
            c.commit();return True
    def execution(self,incident,execution_id):
        with self.connect() as c:
            c.execute("UPDATE actions SET status='started',execution_id=? WHERE incident_id=? AND status='claimed'",(execution_id,incident))
    def resolve(self,incident,checks):
        if not all(checks.get(k) is True for k in ('checkout','latency','error_rate')):raise ValueError('independent recovery checks must all pass')
        with self.connect() as c:
            c.execute('BEGIN IMMEDIATE');c.execute("UPDATE incidents SET status='resolved' WHERE id=?",(incident,))
            c.execute('INSERT INTO timeline VALUES (?,?,?)',(incident,time.time(),'recovery independently verified'));c.commit()
    def report(self,incident):
        with self.connect() as c:
            return {'incident':c.execute('SELECT * FROM incidents WHERE id=?',(incident,)).fetchone(),
                    'alerts':c.execute('SELECT payload FROM alerts WHERE incident_id=?',(incident,)).fetchall(),
                    'actions':c.execute('SELECT runbook,status,approver,execution_id FROM actions WHERE incident_id=?',(incident,)).fetchall(),
                    'timeline':c.execute('SELECT at,event FROM timeline WHERE incident_id=? ORDER BY at',(incident,)).fetchall()}
````

### [engineering/platform.py](engineering/platform.py)

````python
"""Local self-service renderer. No cloud credentials or repository-write token required."""
import json,re,os,tempfile,shutil
from pathlib import Path

def render(request,destination):
    allowed={'name','owner','environment','cpu_millicores','memory_mib','expires_at'}
    if set(request)-allowed:raise ValueError('unknown or privileged fields are not accepted')
    name=request.get('name','')
    if not re.fullmatch(r'veriqta-[a-z][a-z0-9-]{1,30}',name):raise ValueError('use a veriqta- service name')
    if request.get('owner') not in ('group:default/veriqta-platform','group:default/veriqta-payments'):raise ValueError('approved owner required')
    if request.get('environment') not in ('dev','preview'):raise ValueError('self-service production is not enabled')
    if not 50<=request.get('cpu_millicores',0)<=1000 or not 64<=request.get('memory_mib',0)<=1024:raise ValueError('resource quota exceeded')
    if request['environment']=='preview':
        import datetime as dt
        expiry=dt.datetime.fromisoformat(request.get('expires_at',''))
        if expiry.tzinfo is None or not 0<(expiry-dt.datetime.now(dt.timezone.utc)).total_seconds()<=172800:raise ValueError('preview expiry must be within 48 hours')
    destination=Path(destination).resolve();destination.mkdir(parents=True,exist_ok=True)
    target=destination/name
    if target.exists():
        if json.loads((target/'request.json').read_text())==request:return target
        raise ValueError('same service name has different inputs; use a reviewed update')
    temp=Path(tempfile.mkdtemp(prefix='.pending-',dir=destination))
    try:
        (temp/'request.json').write_text(json.dumps(request,sort_keys=True,indent=2))
        (temp/'catalog-info.yaml').write_text(json.dumps({'apiVersion':'backstage.io/v1alpha1','kind':'Component','metadata':{'name':name},'spec':{'type':'service','lifecycle':'experimental','owner':request['owner']}}))
        namespace={'apiVersion':'v1','kind':'Namespace','metadata':{'name':name,'labels':{'owner':'veriqta','environment':request['environment'],'pod-security.kubernetes.io/enforce':'restricted'}}}
        (temp/'namespace.yaml').write_text(json.dumps(namespace,indent=2))
        quota={'apiVersion':'v1','kind':'ResourceQuota','metadata':{'name':'service-budget','namespace':name},'spec':{'hard':{'requests.cpu':'1000m','requests.memory':'1Gi','limits.cpu':'2000m','limits.memory':'2Gi','pods':'10'}}}
        (temp/'quota.yaml').write_text(json.dumps(quota,indent=2))
        (temp/'README.md').write_text('# '+name+'\n\nOwner: '+request['owner']+'\n\nSubmit namespace/quota manifests to the protected GitOps repository. Provisioning and deployment remain controlled by its policies.\n')
        os.rename(temp,target)
    except BaseException:
        shutil.rmtree(temp,ignore_errors=True);raise
    return target
````

### [engineering/recovery.py](engineering/recovery.py)

````python
"""A remediation decision engine. It proposes actions; it never restarts a workload itself."""
import time

def decide(state,observed,now=None):
    now=time.time() if now is None else now
    if observed.get('dependency_healthy') is not True:return 'ESCALATE_DEPENDENCY'
    if observed.get('ready',0)<observed.get('minimum_ready',2):return 'RESTORE_CAPACITY'
    if state.get('attempts',0)>=3:return 'STOP_ATTEMPT_LIMIT'
    if now-state.get('last_attempt',0)<120:return 'WAIT_COOLDOWN'
    if observed.get('crash_loop',False):return 'RESTART_ONE'
    return 'OBSERVE'
````

### [engineering/release.py](engineering/release.py)

````python
import math

def decision(m):
    if m.get('schema_backward_compatible') is not True:return 'FORWARD_FIX_REQUIRED'
    required=('requests','errors','p95_seconds','age_seconds')
    if any(k not in m or not isinstance(m[k],(int,float)) or not math.isfinite(m[k]) for k in required):return 'PAUSE_NO_EVIDENCE'
    if m['requests']<100 or m['age_seconds']>120 or m['age_seconds']<0:return 'PAUSE_NO_EVIDENCE'
    if m['errors']<0 or m['errors']>m['requests'] or m['p95_seconds']<0:return 'PAUSE_NO_EVIDENCE'
    if m['errors']/m['requests']>0.01 or m['p95_seconds']>0.5:return 'ABORT_TO_STABLE'
    return 'PROMOTE'
````

### [infrastructure/backend/main.tf](infrastructure/backend/main.tf)

````hcl
variable "trusted_principal_arns" {
  type        = set(string)
  description = "Specific existing human/workload role ARNs permitted to assume environment state roles."
  validation {
    condition     = length(var.trusted_principal_arns) > 0 && alltrue([for arn in var.trusted_principal_arns : can(regex("^arn:aws:iam::[0-9]{12}:role/.+", arn))])
    error_message = "Supply explicit IAM role ARNs; do not trust an entire account."
  }
}
resource "aws_kms_key" "state" {
  description             = "Veriqta Terraform state encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  lifecycle { prevent_destroy = true }
}
resource "aws_s3_bucket" "state" {
  bucket = "${var.name}-${var.account_id}-${var.region}-state"
  lifecycle { prevent_destroy = true }
}
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Sid = "SecureTransport", Effect = "Deny", Principal = "*", Action = "s3:*", Resource = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"], Condition = { Bool = { "aws:SecureTransport" = "false" }
    } },
    { Sid = "DoNotDeleteLiveState", Effect = "Deny", Principal = "*", Action = ["s3:DeleteObject", "s3:DeleteObjectVersion"], Resource = "${aws_s3_bucket.state.arn}/environments/*/terraform.tfstate" }
  ] })
}
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    filter { prefix = "" }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}
resource "aws_iam_role" "environment" {
  for_each = toset(["dev", "staging", "prod"])
  name     = "${var.name}-${each.key}-state"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { AWS = sort(tolist(var.trusted_principal_arns)) }
  }] })
}
resource "aws_iam_role_policy" "state" {
  for_each = aws_iam_role.environment
  role     = each.value.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = "s3:ListBucket", Resource = aws_s3_bucket.state.arn, Condition = { StringLike = { "s3:prefix" = ["environments/${each.key}/*"] }
    } },
    { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject"], Resource = ["${aws_s3_bucket.state.arn}/environments/${each.key}/terraform.tfstate", "${aws_s3_bucket.state.arn}/environments/${each.key}/*/terraform.tfstate"] },
    { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = ["${aws_s3_bucket.state.arn}/environments/${each.key}/terraform.tfstate.tflock", "${aws_s3_bucket.state.arn}/environments/${each.key}/*/terraform.tfstate.tflock"] },
    { Effect = "Allow", Action = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"], Resource = aws_kms_key.state.arn, Condition = { StringEquals = { "kms:ViaService" = "s3.${var.region}.amazonaws.com" }
    } }
  ] })
}
resource "aws_s3_bucket" "archive" {
  bucket              = "${var.name}-${var.account_id}-${var.region}-archive"
  object_lock_enabled = true
  lifecycle { prevent_destroy = true }
}
resource "aws_s3_bucket_versioning" "archive" {
  bucket = aws_s3_bucket.archive.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_public_access_block" "archive" {
  bucket                  = aws_s3_bucket.archive.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "archive" {
  bucket = aws_s3_bucket.archive.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
  }
}
resource "aws_s3_bucket_object_lock_configuration" "archive" {
  bucket     = aws_s3_bucket.archive.id
  depends_on = [aws_s3_bucket_versioning.archive]
  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 7
    }
  }
}
output "bucket" { value = aws_s3_bucket.state.id }
output "kms_key_arn" { value = aws_kms_key.state.arn }
output "archive_bucket" { value = aws_s3_bucket.archive.id }
output "state_role_arns" {
  value = { for k, v in aws_iam_role.environment : k => v.arn }
}
````

### [infrastructure/backend/tests/aws.tfmock.hcl](infrastructure/backend/tests/aws.tfmock.hcl)

````hcl
mock_data "aws_caller_identity" {
  defaults = { account_id = "123456789012", arn = "arn:aws:iam::123456789012:root", user_id = "mock" }
}
mock_data "aws_region" { defaults = { name = "us-east-1", region = "us-east-1" } }
mock_data "aws_availability_zones" {
  defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"], zone_ids = ["use1-az1", "use1-az2", "use1-az3"] }
}
mock_data "aws_ssm_parameter" { defaults = { value = "ami-0123456789abcdef0" } }
mock_resource "aws_kms_key" {
  defaults = { arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000", key_id = "00000000-0000-0000-0000-000000000000" }
}
mock_resource "aws_iam_role" { defaults = { arn = "arn:aws:iam::123456789012:role/veriqta-mock" } }
mock_resource "aws_iam_instance_profile" { defaults = { arn = "arn:aws:iam::123456789012:instance-profile/veriqta-mock" } }
mock_resource "aws_s3_bucket" { defaults = { arn = "arn:aws:s3:::veriqta-mock-bucket" } }
mock_resource "aws_db_instance" {
  defaults = { arn = "arn:aws:rds:us-east-1:123456789012:db:veriqta-mock", address = "veriqta.example.invalid", master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:veriqta-AbCdEf", secret_status = "active", kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000" }] }
}
mock_resource "aws_lb" {
  defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/veriqta/0000000000000000", arn_suffix = "app/veriqta/0000000000000000", dns_name = "veriqta.example.invalid", zone_id = "Z35SXDOTRQ7X7K" }
}
mock_resource "aws_lb_target_group" {
  defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/veriqta/0000000000000000", arn_suffix = "targetgroup/veriqta/0000000000000000" }
}
mock_resource "aws_cloudwatch_log_group" { defaults = { arn = "arn:aws:logs:us-east-1:123456789012:log-group:veriqta" } }
mock_resource "aws_sns_topic" { defaults = { arn = "arn:aws:sns:us-east-1:123456789012:veriqta" } }
mock_resource "aws_backup_vault" { defaults = { arn = "arn:aws:backup:us-west-2:123456789012:backup-vault:veriqta" } }
````

### [infrastructure/backend/tests/contract.tftest.hcl](infrastructure/backend/tests/contract.tftest.hcl)

````hcl
mock_provider "aws" {
  source = "./tests"
}
variables {
  account_id             = "123456789012"
  trusted_principal_arns = ["arn:aws:iam::123456789012:role/VeriqtaOperator"]
}
run "contract" {
  command = plan
  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "State must remain versioned."
  }
  assert {
    condition     = length(aws_iam_role.environment) == 3
    error_message = "Each environment needs a state role."
  }
}
````

### [infrastructure/backend/versions.tf](infrastructure/backend/versions.tf)

````hcl
terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "6.19.0" }
  }
}
provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]
  default_tags { tags = local.tags }
}
variable "region" {
  type    = string
  default = "us-east-1"
}
variable "account_id" {
  type = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "Supply the expected twelve-digit AWS account ID."
  }
}
variable "name" {
  type    = string
  default = "veriqta-lab"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,22}$", var.name))
    error_message = "Use 3..23 lowercase letters, digits or hyphens, beginning with a letter."
  }
}
variable "environment" {
  type    = string
  default = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Choose dev, staging or prod."
  }
}
locals {
  tags = {
    Project     = var.name
    Environment = var.environment
    Owner       = "veriqta"
    CostCenter  = "training"
    ManagedBy   = "terraform"
    Application = "portfolio"
  }
}
````

### [infrastructure/backup/main.tf](infrastructure/backup/main.tf)

````hcl
variable "database_arn" { type = string }
variable "source_vault_name" { type = string }
variable "destination_vault_arn" { type = string }
variable "key_arns" { type = set(string) }
resource "aws_iam_role" "backup" {
  name               = "${var.name}-backup"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "backup.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}
resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}
resource "aws_iam_role_policy" "keys" {
  role   = aws_iam_role.backup.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey*", "kms:DescribeKey", "kms:CreateGrant"], Resource = sort(tolist(var.key_arns)) }] })
}
resource "aws_backup_plan" "this" {
  name = var.name
  rule {
    rule_name         = "daily-copy"
    target_vault_name = var.source_vault_name
    schedule          = "cron(0 3 * * ? *)"
    lifecycle { delete_after = 14 }
    copy_action {
      destination_vault_arn = var.destination_vault_arn
      lifecycle { delete_after = 30 }
    }
  }
}
resource "aws_backup_selection" "this" {
  name         = var.name
  plan_id      = aws_backup_plan.this.id
  iam_role_arn = aws_iam_role.backup.arn
  resources    = [var.database_arn]
  depends_on   = [aws_iam_role_policy_attachment.backup, aws_iam_role_policy.keys]
}
output "backup_role_arn" { value = aws_iam_role.backup.arn }
````

### [infrastructure/backup/versions.tf](infrastructure/backup/versions.tf)

````hcl
terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers { aws = { source = "hashicorp/aws", version = "6.19.0" } }
}
provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]
  default_tags { tags = { Owner = "veriqta", Project = var.name, Environment = "lab", ManagedBy = "Terraform" } }
}
variable "account_id" { type = string }
variable "region" { type = string }
variable "name" { type = string }
````

### [infrastructure/cluster/main.tf](infrastructure/cluster/main.tf)

````hcl
variable "kubernetes_version" { type = string }
variable "administrator_role_arn" { type = string }
variable "administrator_cidrs" { type = list(string) }
variable "foundation" { type = object({ vpc_id = string, private_subnet_ids = list(string), workload_sg_id = string, secret_arn = string, kms_key_arn = string, queue_arn = string }) }
resource "aws_iam_role" "cluster" {
  name               = "${var.name}-cluster"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "eks.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}
resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}
resource "aws_eks_cluster" "this" {
  name     = var.name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }
  vpc_config {
    subnet_ids              = var.foundation.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.administrator_cidrs
  }
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  depends_on                = [aws_iam_role_policy_attachment.cluster]
}
resource "aws_eks_access_entry" "administrator" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.administrator_role_arn
  type          = "STANDARD"
}
resource "aws_eks_access_policy_association" "administrator" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.administrator_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope { type = "cluster" }
  depends_on = [aws_eks_access_entry.administrator]
}
resource "aws_iam_role" "nodes" {
  name               = "${var.name}-nodes"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}
resource "aws_iam_role_policy_attachment" "nodes" {
  for_each   = toset(["AmazonEKSWorkerNodePolicy", "AmazonEC2ContainerRegistryReadOnly", "AmazonEKS_CNI_Policy"])
  role       = aws_iam_role.nodes.name
  policy_arn = "arn:aws:iam::aws:policy/${each.key}"
}
resource "aws_launch_template" "nodes" {
  name_prefix            = "${var.name}-"
  vpc_security_group_ids = [var.foundation.workload_sg_id, aws_eks_cluster.this.vpc_config[0].cluster_security_group_id]
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 30
      encrypted   = true
      volume_type = "gp3"
    }
  }
}
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = var.name
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = var.foundation.private_subnet_ids
  instance_types  = ["m6i.large", "m6a.large"]
  capacity_type   = "ON_DEMAND"
  scaling_config {
    desired_size = 3
    min_size     = 3
    max_size     = 9
  }
  launch_template {
    id      = aws_launch_template.nodes.id
    version = tostring(aws_launch_template.nodes.latest_version)
  }
  update_config { max_unavailable = 1 }
  lifecycle { ignore_changes = [scaling_config[0].desired_size] }
  depends_on = [aws_iam_role_policy_attachment.nodes]
}
resource "aws_eks_addon" "identity" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "eks-pod-identity-agent"
  depends_on   = [aws_eks_node_group.this]
}
resource "aws_iam_role" "application" {
  name               = "${var.name}-application"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "pods.eks.amazonaws.com" }, Action = ["sts:AssumeRole", "sts:TagSession"] }] })
}
resource "aws_iam_role_policy" "application" {
  role = aws_iam_role.application.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = "secretsmanager:GetSecretValue", Resource = var.foundation.secret_arn },
    { Effect = "Allow", Action = "kms:Decrypt", Resource = var.foundation.kms_key_arn, Condition = { StringEquals = { "kms:ViaService" = "secretsmanager.${var.region}.amazonaws.com" } } },
    { Effect = "Allow", Action = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Resource = var.foundation.queue_arn }
  ] })
}
resource "aws_eks_pod_identity_association" "application" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "veriqta"
  service_account = "veriqta-app"
  role_arn        = aws_iam_role.application.arn
  depends_on      = [aws_eks_addon.identity]
}
output "cluster_name" { value = aws_eks_cluster.this.name }

output "application_role_arn" { value = aws_iam_role.application.arn }
````

### [infrastructure/cluster/tests/aws.tfmock.hcl](infrastructure/cluster/tests/aws.tfmock.hcl)

````hcl
mock_data "aws_caller_identity" {
  defaults = { account_id = "123456789012", arn = "arn:aws:iam::123456789012:root", user_id = "mock" }
}
mock_data "aws_region" { defaults = { name = "us-east-1", region = "us-east-1" } }
mock_data "aws_availability_zones" {
  defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"], zone_ids = ["use1-az1", "use1-az2", "use1-az3"] }
}
mock_data "aws_ssm_parameter" { defaults = { value = "ami-0123456789abcdef0" } }
mock_resource "aws_kms_key" {
  defaults = { arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000", key_id = "00000000-0000-0000-0000-000000000000" }
}
mock_resource "aws_iam_role" { defaults = { arn = "arn:aws:iam::123456789012:role/veriqta-mock" } }
mock_resource "aws_iam_instance_profile" { defaults = { arn = "arn:aws:iam::123456789012:instance-profile/veriqta-mock" } }
mock_resource "aws_s3_bucket" { defaults = { arn = "arn:aws:s3:::veriqta-mock-bucket" } }
mock_resource "aws_db_instance" {
  defaults = { arn = "arn:aws:rds:us-east-1:123456789012:db:veriqta-mock", address = "veriqta.example.invalid", master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:veriqta-AbCdEf", secret_status = "active", kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000" }] }
}
mock_resource "aws_lb" {
  defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/veriqta/0000000000000000", arn_suffix = "app/veriqta/0000000000000000", dns_name = "veriqta.example.invalid", zone_id = "Z35SXDOTRQ7X7K" }
}
mock_resource "aws_lb_target_group" {
  defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/veriqta/0000000000000000", arn_suffix = "targetgroup/veriqta/0000000000000000" }
}
mock_resource "aws_cloudwatch_log_group" { defaults = { arn = "arn:aws:logs:us-east-1:123456789012:log-group:veriqta" } }
mock_resource "aws_sns_topic" { defaults = { arn = "arn:aws:sns:us-east-1:123456789012:veriqta" } }
mock_resource "aws_backup_vault" { defaults = { arn = "arn:aws:backup:us-west-2:123456789012:backup-vault:veriqta" } }

mock_resource "aws_sqs_queue" {
  defaults = { arn = "arn:aws:sqs:us-east-1:123456789012:veriqta-jobs", url = "https://sqs.us-east-1.amazonaws.com/123456789012/veriqta-jobs" }
}
mock_resource "aws_eks_cluster" {
  defaults = { arn = "arn:aws:eks:us-east-1:123456789012:cluster/veriqta", endpoint = "https://example.invalid" }
}
````

### [infrastructure/cluster/tests/contract.tftest.hcl](infrastructure/cluster/tests/contract.tftest.hcl)

````hcl
mock_provider "aws" {
  source = "./tests"
}
variables {
  account_id             = "123456789012"
  region                 = "us-east-1"
  name                   = "veriqta-test"
  kubernetes_version     = "1.34"
  administrator_role_arn = "arn:aws:iam::123456789012:role/veriqta-operator"
  administrator_cidrs    = ["192.0.2.0/24"]
  foundation             = { vpc_id = "vpc-0123456789abcdef0", private_subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1", "subnet-0123456789abcdef2"], workload_sg_id = "sg-0123456789abcdef0", secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:veriqta-AbCdEf", kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000", queue_arn = "arn:aws:sqs:us-east-1:123456789012:veriqta-jobs" }
}
run "contract" {
  command = plan
  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_private_access && aws_eks_node_group.this.scaling_config[0].min_size == 3
    error_message = "Private control-plane access and initial three-node capacity are required."
  }
  assert {
    condition     = aws_eks_cluster.this.access_config[0].bootstrap_cluster_creator_admin_permissions == false
    error_message = "Cluster administration must use the explicit access entry."
  }
}
````

### [infrastructure/cluster/versions.tf](infrastructure/cluster/versions.tf)

````hcl
terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers { aws = { source = "hashicorp/aws", version = "6.19.0" } }
}
provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]
  default_tags { tags = { Owner = "veriqta", Project = var.name, Environment = "lab", ManagedBy = "Terraform" } }
}
variable "account_id" { type = string }
variable "region" { type = string }
variable "name" { type = string }
````

### [infrastructure/delivery-identity/main.tf](infrastructure/delivery-identity/main.tf)

````hcl
variable "repository" { type = string }
variable "oidc_provider_arn" { type = string }
variable "ecr_repository_arn" { type = string }
resource "aws_iam_role" "build" {
  name               = "${var.name}-build"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Federated = var.oidc_provider_arn }, Action = "sts:AssumeRoleWithWebIdentity", Condition = { StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com", "token.actions.githubusercontent.com:sub" = "repo:${var.repository}:ref:refs/heads/main" } } }] })
}
resource "aws_iam_role_policy" "build" {
  role   = aws_iam_role.build.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "ecr:GetAuthorizationToken", Resource = "*" }, { Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"], Resource = var.ecr_repository_arn }] })
}
# Promotion uses a separate protected GitOps PR identity, not the build role.
output "build_role_arn" { value = aws_iam_role.build.arn }

resource "aws_iam_role" "verify" {
  name               = "${var.name}-verify"
  assume_role_policy = aws_iam_role.build.assume_role_policy
}
resource "aws_iam_role_policy" "verify" {
  role   = aws_iam_role.verify.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "ecr:GetAuthorizationToken", Resource = "*" }, { Effect = "Allow", Action = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"], Resource = var.ecr_repository_arn }] })
}
resource "aws_iam_role" "promotion" {
  name               = "${var.name}-promotion"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Federated = var.oidc_provider_arn }, Action = "sts:AssumeRoleWithWebIdentity", Condition = { StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com", "token.actions.githubusercontent.com:sub" = "repo:${var.repository}:environment:production-promotion" } } }] })
}
output "verify_role_arn" { value = aws_iam_role.verify.arn }
output "promotion_role_arn" { value = aws_iam_role.promotion.arn }
````

### [infrastructure/delivery-identity/versions.tf](infrastructure/delivery-identity/versions.tf)

````hcl
terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers { aws = { source = "hashicorp/aws", version = "6.19.0" } }
}
provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]
  default_tags { tags = { Owner = "veriqta", Project = var.name, Environment = "lab", ManagedBy = "Terraform" } }
}
variable "account_id" { type = string }
variable "region" { type = string }
variable "name" { type = string }
````

### [infrastructure/foundation/main.tf](infrastructure/foundation/main.tf)

````hcl
variable "cidr" { type = string }
variable "deletion_protection" {
  type    = bool
  default = true
}
variable "database_engine_version" { type = string }
variable "snapshot_identifier" {
  type    = string
  default = null
}
variable "final_snapshot_suffix" {
  type    = string
  default = "retained"
}
module "network" {
  source             = "../modules/network"
  name               = var.name
  cidr               = var.cidr
  az_count           = 3
  enable_nat         = true
  allow_database     = true
  interface_services = ["ssm", "ssmmessages", "secretsmanager", "logs", "ecr.api", "ecr.dkr", "sts", "ec2", "monitoring"]
}
resource "aws_kms_key" "data" {
  enable_key_rotation     = true
  deletion_window_in_days = 30
  lifecycle { prevent_destroy = true }
}
module "database" {
  source                     = "../modules/database"
  name                       = var.name
  vpc_id                     = module.network.vpc_id
  subnet_ids                 = module.network.database_subnet_ids
  workload_security_group_id = module.network.workload_security_group_id
  kms_key_arn                = aws_kms_key.data.arn
  engine_version             = var.database_engine_version
  deletion_protection        = var.deletion_protection
  snapshot_identifier        = var.snapshot_identifier
  final_snapshot_suffix      = var.final_snapshot_suffix
}
resource "aws_sqs_queue" "dead" {
  name                      = "${var.name}-dead"
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 1209600
}
resource "aws_sqs_queue" "jobs" {
  name                       = "${var.name}-jobs"
  sqs_managed_sse_enabled    = true
  visibility_timeout_seconds = 60
  redrive_policy             = jsonencode({ deadLetterTargetArn = aws_sqs_queue.dead.arn, maxReceiveCount = 5 })
}
resource "aws_s3_bucket" "objects" { bucket = "${var.name}-${var.account_id}-${var.region}-objects" }
resource "aws_s3_bucket_versioning" "objects" {
  bucket = aws_s3_bucket.objects.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_public_access_block" "objects" {
  bucket                  = aws_s3_bucket.objects.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "objects" {
  bucket = aws_s3_bucket.objects.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.data.arn
    }
  }
}
resource "aws_s3_bucket_policy" "objects" {
  bucket = aws_s3_bucket.objects.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Deny", Principal = "*", Action = "s3:*", Resource = [aws_s3_bucket.objects.arn, "${aws_s3_bucket.objects.arn}/*"], Condition = { Bool = { "aws:SecureTransport" = "false" } } }] })
}
resource "aws_ecr_repository" "application" {
  name                 = var.name
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
  force_delete = false
}
resource "aws_backup_vault" "this" {
  name        = var.name
  kms_key_arn = aws_kms_key.data.arn
}
output "contract" { value = { vpc_id = module.network.vpc_id, private_subnet_ids = module.network.private_subnet_ids, public_subnet_ids = module.network.public_subnet_ids, workload_sg_id = module.network.workload_security_group_id, secret_arn = module.database.secret_arn, db_host = module.database.endpoint, db_arn = module.database.arn, kms_key_arn = aws_kms_key.data.arn, queue_arn = aws_sqs_queue.jobs.arn, queue_url = aws_sqs_queue.jobs.url, bucket = aws_s3_bucket.objects.id, repository_url = aws_ecr_repository.application.repository_url, vault_arn = aws_backup_vault.this.arn, vault_name = aws_backup_vault.this.name } }
````

### [infrastructure/foundation/tests/aws.tfmock.hcl](infrastructure/foundation/tests/aws.tfmock.hcl)

````hcl
mock_data "aws_caller_identity" {
  defaults = { account_id = "123456789012", arn = "arn:aws:iam::123456789012:root", user_id = "mock" }
}
mock_data "aws_region" { defaults = { name = "us-east-1", region = "us-east-1" } }
mock_data "aws_availability_zones" {
  defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"], zone_ids = ["use1-az1", "use1-az2", "use1-az3"] }
}
mock_data "aws_ssm_parameter" { defaults = { value = "ami-0123456789abcdef0" } }
mock_resource "aws_kms_key" {
  defaults = { arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000", key_id = "00000000-0000-0000-0000-000000000000" }
}
mock_resource "aws_iam_role" { defaults = { arn = "arn:aws:iam::123456789012:role/veriqta-mock" } }
mock_resource "aws_iam_instance_profile" { defaults = { arn = "arn:aws:iam::123456789012:instance-profile/veriqta-mock" } }
mock_resource "aws_s3_bucket" { defaults = { arn = "arn:aws:s3:::veriqta-mock-bucket" } }
mock_resource "aws_db_instance" {
  defaults = { arn = "arn:aws:rds:us-east-1:123456789012:db:veriqta-mock", address = "veriqta.example.invalid", master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:veriqta-AbCdEf", secret_status = "active", kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000" }] }
}
mock_resource "aws_lb" {
  defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/veriqta/0000000000000000", arn_suffix = "app/veriqta/0000000000000000", dns_name = "veriqta.example.invalid", zone_id = "Z35SXDOTRQ7X7K" }
}
mock_resource "aws_lb_target_group" {
  defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/veriqta/0000000000000000", arn_suffix = "targetgroup/veriqta/0000000000000000" }
}
mock_resource "aws_cloudwatch_log_group" { defaults = { arn = "arn:aws:logs:us-east-1:123456789012:log-group:veriqta" } }
mock_resource "aws_sns_topic" { defaults = { arn = "arn:aws:sns:us-east-1:123456789012:veriqta" } }
mock_resource "aws_backup_vault" { defaults = { arn = "arn:aws:backup:us-west-2:123456789012:backup-vault:veriqta" } }

mock_resource "aws_sqs_queue" {
  defaults = { arn = "arn:aws:sqs:us-east-1:123456789012:veriqta-jobs", url = "https://sqs.us-east-1.amazonaws.com/123456789012/veriqta-jobs" }
}
mock_resource "aws_eks_cluster" {
  defaults = { arn = "arn:aws:eks:us-east-1:123456789012:cluster/veriqta", endpoint = "https://example.invalid" }
}
````

### [infrastructure/foundation/tests/contract.tftest.hcl](infrastructure/foundation/tests/contract.tftest.hcl)

````hcl
mock_provider "aws" {
  source = "./tests"
}
variables {
  account_id              = "123456789012"
  region                  = "us-east-1"
  name                    = "veriqta-test"
  cidr                    = "10.90.0.0/16"
  database_engine_version = "17.6"
}
run "contract" {
  command = plan
  assert {
    condition     = aws_sqs_queue.jobs.sqs_managed_sse_enabled && aws_s3_bucket_public_access_block.objects.restrict_public_buckets
    error_message = "Queues must be encrypted and object storage private."
  }
}
````

### [infrastructure/foundation/versions.tf](infrastructure/foundation/versions.tf)

````hcl
terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers { aws = { source = "hashicorp/aws", version = "6.19.0" } }
}
provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]
  default_tags { tags = { Owner = "veriqta", Project = var.name, Environment = "lab", ManagedBy = "Terraform" } }
}
variable "account_id" { type = string }
variable "region" { type = string }
variable "name" { type = string }
````

### [infrastructure/incidents/main.tf](infrastructure/incidents/main.tf)

````hcl
resource "aws_iam_role" "execution" {
  name               = "${var.name}-diagnostic"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ssm.amazonaws.com" }, Action = "sts:AssumeRole", Condition = { StringEquals = { "aws:SourceAccount" = var.account_id }, ArnLike = { "aws:SourceArn" = "arn:aws:ssm:${var.region}:${var.account_id}:automation-execution/*" } } }] })
}
resource "aws_iam_role_policy" "execution" {
  role   = aws_iam_role.execution.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "rds:DescribeDBInstances", Resource = "*" }] })
}
resource "aws_ssm_document" "diagnose" {
  name            = "veriqta-diagnose-database"
  document_type   = "Automation"
  document_format = "YAML"
  content         = file("${path.module}/../../projects/10-incident-command/diagnose-database.yaml")
}
output "execution_role_arn" { value = aws_iam_role.execution.arn }
output "document_arn" { value = aws_ssm_document.diagnose.arn }
````

### [infrastructure/incidents/versions.tf](infrastructure/incidents/versions.tf)

````hcl
terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers { aws = { source = "hashicorp/aws", version = "6.19.0" } }
}
provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]
  default_tags { tags = { Owner = "veriqta", Project = var.name, Environment = "lab", ManagedBy = "Terraform" } }
}
variable "account_id" { type = string }
variable "region" { type = string }
variable "name" { type = string }
````

### [infrastructure/modules/database/main.tf](infrastructure/modules/database/main.tf)

````hcl
variable "name" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "workload_security_group_id" { type = string }
variable "kms_key_arn" { type = string }
variable "multi_az" {
  type    = bool
  default = true
}
variable "instance_class" {
  type    = string
  default = "db.t4g.small"
}
variable "engine_version" {
  type    = string
  default = null
}
variable "deletion_protection" {
  type    = bool
  default = true
}
variable "snapshot_identifier" {
  type    = string
  default = null
}
variable "final_snapshot_suffix" {
  type    = string
  default = "retained"
}
resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db"
  subnet_ids = var.subnet_ids
}
resource "aws_security_group" "this" {
  name_prefix = "${var.name}-db-"
  vpc_id      = var.vpc_id
  ingress {
    protocol        = "tcp"
    from_port       = 5432
    to_port         = 5432
    security_groups = [var.workload_security_group_id]
  }
  egress = []
}
resource "aws_db_instance" "this" {
  identifier                      = "${var.name}-db"
  engine                          = "postgres"
  engine_version                  = var.engine_version
  instance_class                  = var.instance_class
  allocated_storage               = 20
  max_allocated_storage           = 100
  storage_type                    = "gp3"
  storage_encrypted               = true
  kms_key_id                      = var.kms_key_arn
  db_name                         = var.snapshot_identifier == null ? "veriqta" : null
  username                        = var.snapshot_identifier == null ? "veriqta" : null
  manage_master_user_password     = true
  master_user_secret_kms_key_id   = var.kms_key_arn
  snapshot_identifier             = var.snapshot_identifier
  multi_az                        = var.multi_az
  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.this.id]
  publicly_accessible             = false
  backup_retention_period         = 7
  copy_tags_to_snapshot           = true
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = false
  final_snapshot_identifier       = "${var.name}-final-${var.final_snapshot_suffix}"
  auto_minor_version_upgrade      = true
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
}
output "endpoint" { value = aws_db_instance.this.address }
output "identifier" { value = aws_db_instance.this.identifier }
output "arn" { value = aws_db_instance.this.arn }
output "secret_arn" { value = aws_db_instance.this.master_user_secret[0].secret_arn }
output "security_group_id" { value = aws_security_group.this.id }
````

### [infrastructure/modules/database/tests/aws.tfmock.hcl](infrastructure/modules/database/tests/aws.tfmock.hcl)

````hcl
mock_data "aws_caller_identity" {
  defaults = { account_id = "123456789012", arn = "arn:aws:iam::123456789012:root", user_id = "mock" }
}
mock_data "aws_region" { defaults = { name = "us-east-1", region = "us-east-1" } }
mock_data "aws_availability_zones" {
  defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"], zone_ids = ["use1-az1", "use1-az2", "use1-az3"] }
}
mock_data "aws_ssm_parameter" { defaults = { value = "ami-0123456789abcdef0" } }
mock_resource "aws_kms_key" {
  defaults = { arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000", key_id = "00000000-0000-0000-0000-000000000000" }
}
mock_resource "aws_iam_role" { defaults = { arn = "arn:aws:iam::123456789012:role/veriqta-mock" } }
mock_resource "aws_iam_instance_profile" { defaults = { arn = "arn:aws:iam::123456789012:instance-profile/veriqta-mock" } }
mock_resource "aws_s3_bucket" { defaults = { arn = "arn:aws:s3:::veriqta-mock-bucket" } }
mock_resource "aws_db_instance" {
  defaults = { arn = "arn:aws:rds:us-east-1:123456789012:db:veriqta-mock", address = "veriqta.example.invalid", master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:veriqta-AbCdEf", secret_status = "active", kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000" }] }
}
mock_resource "aws_lb" {
  defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/veriqta/0000000000000000", arn_suffix = "app/veriqta/0000000000000000", dns_name = "veriqta.example.invalid", zone_id = "Z35SXDOTRQ7X7K" }
}
mock_resource "aws_lb_target_group" {
  defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/veriqta/0000000000000000", arn_suffix = "targetgroup/veriqta/0000000000000000" }
}
mock_resource "aws_cloudwatch_log_group" { defaults = { arn = "arn:aws:logs:us-east-1:123456789012:log-group:veriqta" } }
mock_resource "aws_sns_topic" { defaults = { arn = "arn:aws:sns:us-east-1:123456789012:veriqta" } }
mock_resource "aws_backup_vault" { defaults = { arn = "arn:aws:backup:us-west-2:123456789012:backup-vault:veriqta" } }
````

### [infrastructure/modules/database/tests/security.tftest.hcl](infrastructure/modules/database/tests/security.tftest.hcl)

````hcl
mock_provider "aws" {
  source = "./tests"
}
variables {
  name                       = "veriqta-test"
  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  workload_security_group_id = "sg-0123456789abcdef0"
  kms_key_arn                = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
}
run "security_contract" {
  command = plan
  assert {
    condition     = aws_db_instance.this.multi_az && !aws_db_instance.this.publicly_accessible && aws_db_instance.this.storage_encrypted
    error_message = "Database must remain encrypted, private and Multi-AZ."
  }
  assert {
    condition     = aws_db_instance.this.manage_master_user_password && aws_db_instance.this.deletion_protection && !aws_db_instance.this.skip_final_snapshot
    error_message = "Credential and deletion safeguards must remain enabled."
  }
}
````

### [infrastructure/modules/database/versions.tf](infrastructure/modules/database/versions.tf)

````hcl
terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "6.19.0" }
  }
}
````

### [infrastructure/modules/network/main.tf](infrastructure/modules/network/main.tf)

````hcl
variable "name" { type = string }
variable "cidr" {
  type    = string
  default = "10.64.0.0/16"
  validation {
    condition     = can(cidrsubnet(var.cidr, 8, 30))
    error_message = "Supply an IPv4 network large enough for the subnet layout."
  }
}
variable "az_count" {
  type    = number
  default = 2
  validation {
    condition     = contains([2, 3], var.az_count)
    error_message = "Choose two or three AZs."
  }
}
variable "interface_services" {
  type    = set(string)
  default = ["ssm", "ssmmessages", "logs", "secretsmanager"]
}
variable "enable_nat" {
  type    = bool
  default = false
}
variable "enable_proxy" {
  type    = bool
  default = false
}
variable "proxy_domains" {
  type    = list(string)
  default = [".amazonlinux.com", "example.com"]
  validation {
    condition     = length(var.proxy_domains) > 0 && alltrue([for d in var.proxy_domains : can(regex("^[.]?[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$", d))])
    error_message = "Use explicit domain names without whitespace or proxy directives."
  }

}
variable "allow_database" {
  type    = bool
  default = false
}
variable "flow_logs" {
  type    = bool
  default = true
}
data "aws_availability_zones" "available" { state = "available" }
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
locals {
  azs            = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  az_map         = { for i, az in local.azs : az => i }
  private_cidrs  = [for i in range(var.az_count) : cidrsubnet(var.cidr, 8, i + 10)]
  database_cidrs = [for i in range(var.az_count) : cidrsubnet(var.cidr, 8, i + 20)]
}
resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.name }
}
resource "aws_internet_gateway" "this" { vpc_id = aws_vpc.this.id }
resource "aws_subnet" "public" {
  for_each                = local.az_map
  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = cidrsubnet(var.cidr, 8, each.value)
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.name}-public-${each.key}" }
}
resource "aws_subnet" "private" {
  for_each          = local.az_map
  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.cidr, 8, each.value + 10)
  tags              = { Name = "${var.name}-private-${each.key}" }
}
resource "aws_subnet" "database" {
  for_each          = local.az_map
  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.cidr, 8, each.value + 20)
}
resource "aws_route_table" "public" { vpc_id = aws_vpc.this.id }
resource "aws_route" "internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}
resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table" "private" {
  for_each = local.az_map
  vpc_id   = aws_vpc.this.id
}
resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}
resource "aws_route_table" "database" { vpc_id = aws_vpc.this.id }
resource "aws_route_table_association" "database" {
  for_each       = aws_subnet.database
  subnet_id      = each.value.id
  route_table_id = aws_route_table.database.id
}
resource "aws_eip" "nat" {
  for_each = var.enable_nat ? local.az_map : {}
  domain   = "vpc"
}
resource "aws_nat_gateway" "this" {
  for_each      = aws_eip.nat
  allocation_id = each.value.id
  subnet_id     = aws_subnet.public[each.key].id
  depends_on    = [aws_route.internet]
}
resource "aws_route" "nat" {
  for_each               = aws_nat_gateway.this
  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = each.value.id
}
resource "aws_security_group" "endpoints" {
  name_prefix = "${var.name}-endpoints-"
  vpc_id      = aws_vpc.this.id
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = local.private_cidrs
  }
  egress = []
}
resource "aws_vpc_endpoint" "gateway" {
  for_each          = toset(["s3", "dynamodb"])
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.${each.key}"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for rt in aws_route_table.private : rt.id]
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = "*", Action = "*", Resource = "*", Condition = { StringEquals = { "aws:PrincipalAccount" = data.aws_caller_identity.current.account_id }
  } }] })
}
resource "aws_vpc_endpoint" "interface" {
  for_each            = var.interface_services
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.endpoints.id]
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = "*", Action = "*", Resource = "*", Condition = { StringEquals = { "aws:PrincipalAccount" = data.aws_caller_identity.current.account_id }
  } }] })
}
resource "aws_security_group" "workload" {
  name_prefix = "${var.name}-workload-"
  vpc_id      = aws_vpc.this.id
  ingress     = []
  egress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.endpoints.id]
  }
  egress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [for ep in aws_vpc_endpoint.gateway : ep.prefix_list_id]
  }
  dynamic "egress" {
    for_each = var.allow_database ? [1] : []
    content {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = local.database_cidrs
    }
  }
  dynamic "egress" {
    for_each = var.enable_proxy ? [1] : []
    content {
      from_port       = 3128
      to_port         = 3128
      protocol        = "tcp"
      security_groups = [aws_security_group.proxy[0].id]
    }
  }
}
resource "aws_security_group" "proxy" {
  count       = var.enable_proxy ? 1 : 0
  name_prefix = "${var.name}-proxy-"
  vpc_id      = aws_vpc.this.id
  ingress {
    from_port   = 3128
    to_port     = 3128
    protocol    = "tcp"
    cidr_blocks = local.private_cidrs
  }
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
data "aws_ssm_parameter" "ami" {
  count = var.enable_proxy ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}
resource "aws_instance" "proxy" {
  count                       = var.enable_proxy ? 1 : 0
  ami                         = nonsensitive(data.aws_ssm_parameter.ami[0].value)
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public[local.azs[0]].id
  vpc_security_group_ids      = [aws_security_group.proxy[0].id]
  associate_public_ip_address = true
  metadata_options { http_tokens = "required" }
  root_block_device { encrypted = true }
  user_data  = templatefile("${path.module}/proxy.sh.tftpl", { domains = join(" ", var.proxy_domains) })
  depends_on = [aws_route.internet]
}
resource "aws_cloudwatch_log_group" "flow" {
  count             = var.flow_logs ? 1 : 0
  name              = "/veriqta/${var.name}/flow"
  retention_in_days = 7
}
resource "aws_iam_role" "flow" {
  count = var.flow_logs ? 1 : 0
  name  = "${var.name}-flow"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "vpc-flow-logs.amazonaws.com" }
  }] })
}
resource "aws_iam_role_policy" "flow" {
  count  = var.flow_logs ? 1 : 0
  role   = aws_iam_role.flow[0].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"], Resource = "${aws_cloudwatch_log_group.flow[0].arn}:*" }] })
}
resource "aws_flow_log" "this" {
  count           = var.flow_logs ? 1 : 0
  vpc_id          = aws_vpc.this.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow[0].arn
  log_destination = aws_cloudwatch_log_group.flow[0].arn
  depends_on      = [aws_iam_role_policy.flow]
}
output "vpc_id" { value = aws_vpc.this.id }
output "public_subnet_ids" { value = [for az in local.azs : aws_subnet.public[az].id] }
output "private_subnet_ids" { value = [for az in local.azs : aws_subnet.private[az].id] }
output "database_subnet_ids" { value = [for az in local.azs : aws_subnet.database[az].id] }
output "workload_security_group_id" { value = aws_security_group.workload.id }
output "database_cidrs" { value = local.database_cidrs }
output "proxy_private_ip" { value = try(aws_instance.proxy[0].private_ip, null) }
output "private_route_table_ids" {
  value = { for az, rt in aws_route_table.private : az => rt.id }
}
````

### [infrastructure/modules/network/proxy.sh.tftpl](infrastructure/modules/network/proxy.sh.tftpl)

````text
#!/bin/bash
set -euo pipefail
dnf install -y squid
cat > /etc/squid/squid.conf <<'CONFIG'
acl allowed_domains dstdomain ${domains}
acl SSL_ports port 443
acl Safe_ports port 80 443
acl CONNECT method CONNECT
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow allowed_domains
http_access deny all
http_port 3128
CONFIG
systemctl enable --now squid
````

### [infrastructure/modules/network/tests/aws.tfmock.hcl](infrastructure/modules/network/tests/aws.tfmock.hcl)

````hcl
mock_data "aws_caller_identity" {
  defaults = { account_id = "123456789012", arn = "arn:aws:iam::123456789012:root", user_id = "mock" }
}
mock_data "aws_region" { defaults = { name = "us-east-1", region = "us-east-1" } }
mock_data "aws_availability_zones" {
  defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"], zone_ids = ["use1-az1", "use1-az2", "use1-az3"] }
}
mock_data "aws_ssm_parameter" { defaults = { value = "ami-0123456789abcdef0" } }
mock_resource "aws_kms_key" {
  defaults = { arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000", key_id = "00000000-0000-0000-0000-000000000000" }
}
mock_resource "aws_iam_role" { defaults = { arn = "arn:aws:iam::123456789012:role/veriqta-mock" } }
mock_resource "aws_iam_instance_profile" { defaults = { arn = "arn:aws:iam::123456789012:instance-profile/veriqta-mock" } }
mock_resource "aws_s3_bucket" { defaults = { arn = "arn:aws:s3:::veriqta-mock-bucket" } }
mock_resource "aws_db_instance" {
  defaults = { arn = "arn:aws:rds:us-east-1:123456789012:db:veriqta-mock", address = "veriqta.example.invalid", master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:veriqta-AbCdEf", secret_status = "active", kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000" }] }
}
mock_resource "aws_lb" {
  defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/veriqta/0000000000000000", arn_suffix = "app/veriqta/0000000000000000", dns_name = "veriqta.example.invalid", zone_id = "Z35SXDOTRQ7X7K" }
}
mock_resource "aws_lb_target_group" {
  defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/veriqta/0000000000000000", arn_suffix = "targetgroup/veriqta/0000000000000000" }
}
mock_resource "aws_cloudwatch_log_group" { defaults = { arn = "arn:aws:logs:us-east-1:123456789012:log-group:veriqta" } }
mock_resource "aws_sns_topic" { defaults = { arn = "arn:aws:sns:us-east-1:123456789012:veriqta" } }
mock_resource "aws_backup_vault" { defaults = { arn = "arn:aws:backup:us-west-2:123456789012:backup-vault:veriqta" } }
````

### [infrastructure/modules/network/tests/security.tftest.hcl](infrastructure/modules/network/tests/security.tftest.hcl)

````hcl
mock_provider "aws" {
  source = "./tests"
}
variables {
  name = "veriqta-test"
}
run "security_contract" {
  command = plan
  assert {
    condition     = length(aws_subnet.private) == 2 && length(aws_subnet.database) == 2
    error_message = "Default network contract requires two AZs."
  }
  assert {
    condition     = alltrue([for r in aws_security_group.workload.egress : try(length(r.cidr_blocks), 0) == 0])
    error_message = "Workloads must not get direct CIDR-based internet egress."
  }
}

run "nat_does_not_open_egress" {
  command = plan
  variables {
    enable_nat = true
  }
  assert {
    condition     = length(aws_nat_gateway.this) == 2 && alltrue([for r in aws_security_group.workload.egress : try(length(r.cidr_blocks), 0) == 0])
    error_message = "Per-AZ NAT must not bypass workload egress restrictions."
  }
}
````

### [infrastructure/modules/network/versions.tf](infrastructure/modules/network/versions.tf)

````hcl
terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "6.19.0" }
  }
}
````

### [infrastructure/retain-data-key.tf.example](infrastructure/retain-data-key.tf.example)

````hcl
# Replace only a retired foundation's main.tf after consumers/data resources can be removed.
# Keep its provider/backend, account, Region, name and state unchanged.
resource "aws_kms_key" "data" {
 enable_key_rotation=true
 deletion_window_in_days=30
 lifecycle { prevent_destroy=true }
}
output "retained_data_key_arn" { value=aws_kms_key.data.arn }
````

### [kubernetes/alb-ingress.example.yaml](kubernetes/alb-ingress.example.yaml)

````yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: veriqta-gateway
  namespace: veriqta
  annotations:
    alb.ingress.kubernetes.io/scheme: internal
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/certificate-arn: REPLACE_WITH_VALIDATED_ACM_CERTIFICATE_ARN
    alb.ingress.kubernetes.io/healthcheck-path: /readyz
spec:
  ingressClassName: alb
  rules:
    - host: REPLACE_WITH_PRIVATE_VERIFIED_DOMAIN
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: {service: {name: gateway, port: {number: 8080}}}
````

### [kubernetes/checkout-deployment.yaml](kubernetes/checkout-deployment.yaml)

````yaml
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": {
    "name": "checkout",
    "namespace": "veriqta"
  },
  "spec": {
    "replicas": 3,
    "selector": {
      "matchLabels": {
        "app": "checkout"
      }
    },
    "template": {
      "metadata": {
        "labels": {
          "app": "checkout"
        }
      },
      "spec": {
        "serviceAccountName": "veriqta-app",
        "securityContext": {
          "runAsNonRoot": true,
          "runAsUser": 10001,
          "seccompProfile": {
            "type": "RuntimeDefault"
          }
        },
        "containers": [
          {
            "name": "checkout",
            "image": "veriqta9-app:local",
            "ports": [
              {
                "name": "http",
                "containerPort": 8080
              }
            ],
            "env": [
              {
                "name": "SERVICE_NAME",
                "value": "checkout"
              },
              {
                "name": "DB_HOST",
                "valueFrom": {
                  "configMapKeyRef": {
                    "name": "veriqta-config",
                    "key": "DB_HOST"
                  }
                }
              },
              {
                "name": "DB_SECRET_ARN",
                "valueFrom": {
                  "configMapKeyRef": {
                    "name": "veriqta-config",
                    "key": "DB_SECRET_ARN"
                  }
                }
              },
              {
                "name": "OTEL_EXPORTER_OTLP_ENDPOINT",
                "value": "http://otel.monitoring:4318"
              },
              {
                "name": "RELEASE",
                "value": "v1"
              }
            ],
            "resources": {
              "requests": {
                "cpu": "100m",
                "memory": "128Mi"
              },
              "limits": {
                "cpu": "500m",
                "memory": "256Mi"
              }
            },
            "securityContext": {
              "allowPrivilegeEscalation": false,
              "readOnlyRootFilesystem": true,
              "capabilities": {
                "drop": [
                  "ALL"
                ]
              }
            },
            "readinessProbe": {
              "httpGet": {
                "path": "/readyz",
                "port": "http"
              },
              "periodSeconds": 5
            },
            "livenessProbe": {
              "httpGet": {
                "path": "/healthz",
                "port": "http"
              },
              "initialDelaySeconds": 20,
              "periodSeconds": 10
            },
            "volumeMounts": [
              {
                "name": "tmp",
                "mountPath": "/tmp"
              }
            ]
          }
        ],
        "volumes": [
          {
            "name": "tmp",
            "emptyDir": {}
          }
        ],
        "topologySpreadConstraints": [
          {
            "maxSkew": 1,
            "topologyKey": "topology.kubernetes.io/zone",
            "whenUnsatisfiable": "ScheduleAnyway",
            "labelSelector": {
              "matchLabels": {
                "app": "checkout"
              }
            }
          },
          {
            "maxSkew": 1,
            "topologyKey": "kubernetes.io/hostname",
            "whenUnsatisfiable": "ScheduleAnyway",
            "labelSelector": {
              "matchLabels": {
                "app": "checkout"
              }
            }
          }
        ]
      }
    }
  }
}
````

### [kubernetes/checkout-service.yaml](kubernetes/checkout-service.yaml)

````yaml
{
  "apiVersion": "v1",
  "kind": "Service",
  "metadata": {
    "name": "checkout",
    "namespace": "veriqta"
  },
  "spec": {
    "selector": {
      "app": "checkout"
    },
    "ports": [
      {
        "name": "http",
        "port": 8080,
        "targetPort": "http"
      }
    ]
  }
}
````

### [kubernetes/config.example.yaml](kubernetes/config.example.yaml)

````yaml
{
  "apiVersion": "v1",
  "kind": "ConfigMap",
  "metadata": {
    "name": "veriqta-config",
    "namespace": "veriqta"
  },
  "data": {
    "DB_HOST": "REPLACE_FROM_FOUNDATION",
    "DB_SECRET_ARN": "REPLACE_FROM_FOUNDATION"
  }
}
````

### [kubernetes/gateway-deployment.yaml](kubernetes/gateway-deployment.yaml)

````yaml
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": {
    "name": "gateway",
    "namespace": "veriqta"
  },
  "spec": {
    "replicas": 2,
    "selector": {
      "matchLabels": {
        "app": "gateway"
      }
    },
    "template": {
      "metadata": {
        "labels": {
          "app": "gateway"
        }
      },
      "spec": {
        "serviceAccountName": "veriqta-app",
        "securityContext": {
          "runAsNonRoot": true,
          "runAsUser": 10001,
          "seccompProfile": {
            "type": "RuntimeDefault"
          }
        },
        "containers": [
          {
            "name": "gateway",
            "image": "veriqta9-app:local",
            "ports": [
              {
                "name": "http",
                "containerPort": 8080
              }
            ],
            "env": [
              {
                "name": "SERVICE_NAME",
                "value": "gateway"
              },
              {
                "name": "DB_HOST",
                "valueFrom": {
                  "configMapKeyRef": {
                    "name": "veriqta-config",
                    "key": "DB_HOST"
                  }
                }
              },
              {
                "name": "DB_SECRET_ARN",
                "valueFrom": {
                  "configMapKeyRef": {
                    "name": "veriqta-config",
                    "key": "DB_SECRET_ARN"
                  }
                }
              },
              {
                "name": "OTEL_EXPORTER_OTLP_ENDPOINT",
                "value": "http://otel.monitoring:4318"
              },
              {
                "name": "RELEASE",
                "value": "v1"
              }
            ],
            "resources": {
              "requests": {
                "cpu": "100m",
                "memory": "128Mi"
              },
              "limits": {
                "cpu": "500m",
                "memory": "256Mi"
              }
            },
            "securityContext": {
              "allowPrivilegeEscalation": false,
              "readOnlyRootFilesystem": true,
              "capabilities": {
                "drop": [
                  "ALL"
                ]
              }
            },
            "readinessProbe": {
              "httpGet": {
                "path": "/readyz",
                "port": "http"
              },
              "periodSeconds": 5
            },
            "livenessProbe": {
              "httpGet": {
                "path": "/healthz",
                "port": "http"
              },
              "initialDelaySeconds": 20,
              "periodSeconds": 10
            },
            "volumeMounts": [
              {
                "name": "tmp",
                "mountPath": "/tmp"
              }
            ]
          }
        ],
        "volumes": [
          {
            "name": "tmp",
            "emptyDir": {}
          }
        ],
        "topologySpreadConstraints": [
          {
            "maxSkew": 1,
            "topologyKey": "topology.kubernetes.io/zone",
            "whenUnsatisfiable": "ScheduleAnyway",
            "labelSelector": {
              "matchLabels": {
                "app": "gateway"
              }
            }
          },
          {
            "maxSkew": 1,
            "topologyKey": "kubernetes.io/hostname",
            "whenUnsatisfiable": "ScheduleAnyway",
            "labelSelector": {
              "matchLabels": {
                "app": "gateway"
              }
            }
          }
        ]
      }
    }
  }
}
````

### [kubernetes/gateway-service.yaml](kubernetes/gateway-service.yaml)

````yaml
{
  "apiVersion": "v1",
  "kind": "Service",
  "metadata": {
    "name": "gateway",
    "namespace": "veriqta"
  },
  "spec": {
    "selector": {
      "app": "gateway"
    },
    "ports": [
      {
        "name": "http",
        "port": 8080,
        "targetPort": "http"
      }
    ]
  }
}
````

### [kubernetes/hpa.yaml](kubernetes/hpa.yaml)

````yaml
{
  "apiVersion": "autoscaling/v2",
  "kind": "HorizontalPodAutoscaler",
  "metadata": {
    "name": "checkout",
    "namespace": "veriqta"
  },
  "spec": {
    "scaleTargetRef": {
      "apiVersion": "apps/v1",
      "kind": "Deployment",
      "name": "checkout"
    },
    "minReplicas": 3,
    "maxReplicas": 12,
    "metrics": [
      {
        "type": "Resource",
        "resource": {
          "name": "cpu",
          "target": {
            "type": "Utilization",
            "averageUtilization": 60
          }
        }
      }
    ],
    "behavior": {
      "scaleDown": {
        "stabilizationWindowSeconds": 300
      }
    }
  }
}
````

### [kubernetes/inventory-deployment.yaml](kubernetes/inventory-deployment.yaml)

````yaml
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": {
    "name": "inventory",
    "namespace": "veriqta"
  },
  "spec": {
    "replicas": 2,
    "selector": {
      "matchLabels": {
        "app": "inventory"
      }
    },
    "template": {
      "metadata": {
        "labels": {
          "app": "inventory"
        }
      },
      "spec": {
        "serviceAccountName": "veriqta-app",
        "securityContext": {
          "runAsNonRoot": true,
          "runAsUser": 10001,
          "seccompProfile": {
            "type": "RuntimeDefault"
          }
        },
        "containers": [
          {
            "name": "inventory",
            "image": "veriqta9-app:local",
            "ports": [
              {
                "name": "http",
                "containerPort": 8080
              }
            ],
            "env": [
              {
                "name": "SERVICE_NAME",
                "value": "inventory"
              },
              {
                "name": "DB_HOST",
                "valueFrom": {
                  "configMapKeyRef": {
                    "name": "veriqta-config",
                    "key": "DB_HOST"
                  }
                }
              },
              {
                "name": "DB_SECRET_ARN",
                "valueFrom": {
                  "configMapKeyRef": {
                    "name": "veriqta-config",
                    "key": "DB_SECRET_ARN"
                  }
                }
              },
              {
                "name": "OTEL_EXPORTER_OTLP_ENDPOINT",
                "value": "http://otel.monitoring:4318"
              },
              {
                "name": "RELEASE",
                "value": "v1"
              }
            ],
            "resources": {
              "requests": {
                "cpu": "100m",
                "memory": "128Mi"
              },
              "limits": {
                "cpu": "500m",
                "memory": "256Mi"
              }
            },
            "securityContext": {
              "allowPrivilegeEscalation": false,
              "readOnlyRootFilesystem": true,
              "capabilities": {
                "drop": [
                  "ALL"
                ]
              }
            },
            "readinessProbe": {
              "httpGet": {
                "path": "/readyz",
                "port": "http"
              },
              "periodSeconds": 5
            },
            "livenessProbe": {
              "httpGet": {
                "path": "/healthz",
                "port": "http"
              },
              "initialDelaySeconds": 20,
              "periodSeconds": 10
            },
            "volumeMounts": [
              {
                "name": "tmp",
                "mountPath": "/tmp"
              }
            ]
          }
        ],
        "volumes": [
          {
            "name": "tmp",
            "emptyDir": {}
          }
        ],
        "topologySpreadConstraints": [
          {
            "maxSkew": 1,
            "topologyKey": "topology.kubernetes.io/zone",
            "whenUnsatisfiable": "ScheduleAnyway",
            "labelSelector": {
              "matchLabels": {
                "app": "inventory"
              }
            }
          },
          {
            "maxSkew": 1,
            "topologyKey": "kubernetes.io/hostname",
            "whenUnsatisfiable": "ScheduleAnyway",
            "labelSelector": {
              "matchLabels": {
                "app": "inventory"
              }
            }
          }
        ]
      }
    }
  }
}
````

### [kubernetes/inventory-service.yaml](kubernetes/inventory-service.yaml)

````yaml
{
  "apiVersion": "v1",
  "kind": "Service",
  "metadata": {
    "name": "inventory",
    "namespace": "veriqta"
  },
  "spec": {
    "selector": {
      "app": "inventory"
    },
    "ports": [
      {
        "name": "http",
        "port": 8080,
        "targetPort": "http"
      }
    ]
  }
}
````

### [kubernetes/kustomization.yaml](kubernetes/kustomization.yaml)

````yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - serviceaccount.yaml
  - gateway-deployment.yaml
  - gateway-service.yaml
  - checkout-deployment.yaml
  - checkout-service.yaml
  - payment-deployment.yaml
  - payment-service.yaml
  - inventory-deployment.yaml
  - inventory-service.yaml
  - pdb.yaml
  - hpa.yaml
  - worker-deployment.yaml
````

### [kubernetes/namespace.yaml](kubernetes/namespace.yaml)

````yaml
{
  "apiVersion": "v1",
  "kind": "Namespace",
  "metadata": {
    "name": "veriqta",
    "labels": {
      "pod-security.kubernetes.io/enforce": "restricted"
    }
  }
}
````

### [kubernetes/payment-deployment.yaml](kubernetes/payment-deployment.yaml)

````yaml
{
  "apiVersion": "apps/v1",
  "kind": "Deployment",
  "metadata": {
    "name": "payment",
    "namespace": "veriqta"
  },
  "spec": {
    "replicas": 2,
    "selector": {
      "matchLabels": {
        "app": "payment"
      }
    },
    "template": {
      "metadata": {
        "labels": {
          "app": "payment"
        }
      },
      "spec": {
        "serviceAccountName": "veriqta-app",
        "securityContext": {
          "runAsNonRoot": true,
          "runAsUser": 10001,
          "seccompProfile": {
            "type": "RuntimeDefault"
          }
        },
        "containers": [
          {
            "name": "payment",
            "image": "veriqta9-app:local",
            "ports": [
              {
                "name": "http",
                "containerPort": 8080
              }
            ],
            "env": [
              {
                "name": "SERVICE_NAME",
                "value": "payment"
              },
              {
                "name": "DB_HOST",
                "valueFrom": {
                  "configMapKeyRef": {
                    "name": "veriqta-config",
                    "key": "DB_HOST"
                  }
                }
              },
              {
                "name": "DB_SECRET_ARN",
                "valueFrom": {
                  "configMapKeyRef": {
                    "name": "veriqta-config",
                    "key": "DB_SECRET_ARN"
                  }
                }
              },
              {
                "name": "OTEL_EXPORTER_OTLP_ENDPOINT",
                "value": "http://otel.monitoring:4318"
              },
              {
                "name": "RELEASE",
                "value": "v1"
              }
            ],
            "resources": {
              "requests": {
                "cpu": "100m",
                "memory": "128Mi"
              },
              "limits": {
                "cpu": "500m",
                "memory": "256Mi"
              }
            },
            "securityContext": {
              "allowPrivilegeEscalation": false,
              "readOnlyRootFilesystem": true,
              "capabilities": {
                "drop": [
                  "ALL"
                ]
              }
            },
            "readinessProbe": {
              "httpGet": {
                "path": "/readyz",
                "port": "http"
              },
              "periodSeconds": 5
            },
            "livenessProbe": {
              "httpGet": {
                "path": "/healthz",
                "port": "http"
              },
              "initialDelaySeconds": 20,
              "periodSeconds": 10
            },
            "volumeMounts": [
              {
                "name": "tmp",
                "mountPath": "/tmp"
              }
            ]
          }
        ],
        "volumes": [
          {
            "name": "tmp",
            "emptyDir": {}
          }
        ],
        "topologySpreadConstraints": [
          {
            "maxSkew": 1,
            "topologyKey": "topology.kubernetes.io/zone",
            "whenUnsatisfiable": "ScheduleAnyway",
            "labelSelector": {
              "matchLabels": {
                "app": "payment"
              }
            }
          },
          {
            "maxSkew": 1,
            "topologyKey": "kubernetes.io/hostname",
            "whenUnsatisfiable": "ScheduleAnyway",
            "labelSelector": {
              "matchLabels": {
                "app": "payment"
              }
            }
          }
        ]
      }
    }
  }
}
````

### [kubernetes/payment-service.yaml](kubernetes/payment-service.yaml)

````yaml
{
  "apiVersion": "v1",
  "kind": "Service",
  "metadata": {
    "name": "payment",
    "namespace": "veriqta"
  },
  "spec": {
    "selector": {
      "app": "payment"
    },
    "ports": [
      {
        "name": "http",
        "port": 8080,
        "targetPort": "http"
      }
    ]
  }
}
````

### [kubernetes/pdb.yaml](kubernetes/pdb.yaml)

````yaml
{
  "apiVersion": "policy/v1",
  "kind": "PodDisruptionBudget",
  "metadata": {
    "name": "checkout",
    "namespace": "veriqta"
  },
  "spec": {
    "minAvailable": 2,
    "selector": {
      "matchLabels": {
        "app": "checkout"
      }
    }
  }
}
````

### [kubernetes/podmonitor.yaml](kubernetes/podmonitor.yaml)

````yaml
{
  "apiVersion": "monitoring.coreos.com/v1",
  "kind": "PodMonitor",
  "metadata": {
    "name": "veriqta",
    "namespace": "monitoring",
    "labels": {
      "release": "prometheus"
    }
  },
  "spec": {
    "namespaceSelector": {
      "matchNames": [
        "veriqta",
        "veriqta-release"
      ]
    },
    "selector": {
      "matchExpressions": [
        {
          "key": "app",
          "operator": "In",
          "values": [
            "gateway",
            "checkout",
            "payment",
            "inventory"
          ]
        }
      ]
    },
    "podMetricsEndpoints": [
      {
        "port": "http",
        "path": "/metrics",
        "interval": "5s"
      }
    ]
  }
}
````

### [kubernetes/serviceaccount.yaml](kubernetes/serviceaccount.yaml)

````yaml
{
  "apiVersion": "v1",
  "kind": "ServiceAccount",
  "metadata": {
    "name": "veriqta-app",
    "namespace": "veriqta"
  }
}
````

### [kubernetes/worker-deployment.yaml](kubernetes/worker-deployment.yaml)

````yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: worker
  namespace: veriqta
spec:
  replicas: 2
  selector:
    matchLabels:
      app: worker
  template:
    metadata:
      labels:
        app: worker
    spec:
      serviceAccountName: veriqta-app
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: worker
        image: veriqta9-app:local
        env:
        - name: SERVICE_NAME
          value: checkout
        - name: DB_HOST
          valueFrom:
            configMapKeyRef:
              name: veriqta-config
              key: DB_HOST
        - name: DB_SECRET_ARN
          valueFrom:
            configMapKeyRef:
              name: veriqta-config
              key: DB_SECRET_ARN
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: http://otel.monitoring:4318
        - name: RELEASE
          value: v1
        - name: QUEUE_URL
          valueFrom:
            configMapKeyRef:
              name: veriqta-config
              key: QUEUE_URL
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
        volumeMounts:
        - name: tmp
          mountPath: /tmp
        command:
        - python
        - -m
        - application.worker
      volumes:
      - name: tmp
        emptyDir: {}
````

### [observability/alerts.yaml](observability/alerts.yaml)

````yaml
groups:
  - name: veriqta-slo
    rules:
      - alert: CheckoutFastBurn
        expr: |
          (sum(rate(veriqta_http_requests_total{service="checkout",route="/checkout",status=~"5.."}[5m])) / clamp_min(sum(rate(veriqta_http_requests_total{service="checkout",route="/checkout"}[5m])),0.001) > 0.0144)
          and
          (sum(rate(veriqta_http_requests_total{service="checkout",route="/checkout",status=~"5.."}[1m])) / clamp_min(sum(rate(veriqta_http_requests_total{service="checkout",route="/checkout"}[1m])),0.001) > 0.0144)
        for: 1m
        labels: {severity: page, service: checkout, owner: veriqta-platform}
        annotations: {summary: 'Checkout is burning a 99.9% availability budget faster than 14.4x'}
      - alert: CheckoutTelemetryAbsent
        expr: absent_over_time(veriqta_http_requests_total{service="checkout"}[5m])
        for: 1m
        labels: {severity: ticket, service: checkout}
        annotations: {summary: 'Checkout telemetry is absent; release evidence is unavailable'}
````

### [observability/collector.yaml](observability/collector.yaml)

````yaml
receivers:
  otlp:
    protocols:
      grpc: {endpoint: '0.0.0.0:4317'}
      http: {endpoint: '0.0.0.0:4318'}
processors:
  memory_limiter: {check_interval: 1s, limit_mib: 256, spike_limit_mib: 64}
  tail_sampling:
    decision_wait: 10s
    num_traces: 10000
    expected_new_traces_per_sec: 100
    policies:
      - name: errors
        type: status_code
        status_code: {status_codes: [ERROR]}
      - name: slow
        type: latency
        latency: {threshold_ms: 500}
      - name: baseline
        type: probabilistic
        probabilistic: {sampling_percentage: 10}
  batch: {}
exporters:
  otlphttp/tempo: {endpoint: 'http://tempo:4318'}
  otlphttp/loki: {endpoint: 'http://loki:3100/otlp'}
service:
  pipelines:
    traces: {receivers: [otlp], processors: [memory_limiter, tail_sampling, batch], exporters: [otlphttp/tempo]}
    logs: {receivers: [otlp], processors: [memory_limiter, batch], exporters: [otlphttp/loki]}
````

### [observability/grafana/dashboard.json](observability/grafana/dashboard.json)

````json
{
  "title": "Veriqta incident investigation",
  "uid": "veriqta-investigate",
  "schemaVersion": 39,
  "version": 1,
  "time": {
    "from": "now-15m",
    "to": "now"
  },
  "panels": [
    {
      "id": 1,
      "title": "Checkout request rate",
      "type": "timeseries",
      "datasource": {
        "type": "prometheus",
        "uid": "prometheus"
      },
      "gridPos": {
        "x": 0,
        "y": 0,
        "w": 12,
        "h": 8
      },
      "targets": [
        {
          "refId": "A",
          "expr": "sum(rate(veriqta_http_requests_total{service=\"checkout\",route=\"/checkout\"}[1m]))"
        }
      ]
    },
    {
      "id": 2,
      "title": "Checkout error fraction",
      "type": "timeseries",
      "datasource": {
        "type": "prometheus",
        "uid": "prometheus"
      },
      "gridPos": {
        "x": 12,
        "y": 0,
        "w": 12,
        "h": 8
      },
      "targets": [
        {
          "refId": "A",
          "expr": "sum(rate(veriqta_http_requests_total{service=\"checkout\",route=\"/checkout\",status=~\"5..\"}[1m])) / clamp_min(sum(rate(veriqta_http_requests_total{service=\"checkout\",route=\"/checkout\"}[1m])),0.001)"
        }
      ]
    },
    {
      "id": 3,
      "title": "Checkout p95 seconds",
      "type": "timeseries",
      "datasource": {
        "type": "prometheus",
        "uid": "prometheus"
      },
      "gridPos": {
        "x": 0,
        "y": 8,
        "w": 12,
        "h": 8
      },
      "targets": [
        {
          "refId": "A",
          "expr": "histogram_quantile(0.95,sum by(le)(rate(veriqta_http_duration_seconds_bucket{service=\"checkout\",route=\"/checkout\"}[1m])))"
        }
      ]
    },
    {
      "id": 4,
      "title": "In-flight dependency work",
      "type": "timeseries",
      "datasource": {
        "type": "prometheus",
        "uid": "prometheus"
      },
      "gridPos": {
        "x": 12,
        "y": 8,
        "w": 12,
        "h": 8
      },
      "targets": [
        {
          "refId": "A",
          "expr": "sum by(service)(veriqta_http_active)"
        }
      ]
    }
  ]
}
````

### [observability/grafana/dashboards/provider.yaml](observability/grafana/dashboards/provider.yaml)

````yaml
{
  "apiVersion": 1,
  "providers": [
    {
      "name": "Veriqta",
      "type": "file",
      "options": {
        "path": "/var/lib/grafana/dashboards"
      }
    }
  ]
}
````

### [observability/grafana/datasources/datasources.yaml](observability/grafana/datasources/datasources.yaml)

````yaml
{
  "apiVersion": 1,
  "datasources": [
    {
      "name": "Prometheus",
      "type": "prometheus",
      "uid": "prometheus",
      "access": "proxy",
      "url": "http://prometheus:9090",
      "isDefault": true
    },
    {
      "name": "Tempo",
      "type": "tempo",
      "uid": "tempo",
      "access": "proxy",
      "url": "http://tempo:3200"
    },
    {
      "name": "Loki",
      "type": "loki",
      "uid": "loki",
      "access": "proxy",
      "url": "http://loki:3100",
      "jsonData": {
        "derivedFields": [
          {
            "datasourceUid": "tempo",
            "matcherRegex": "\"trace_id\":\\s*\"([0-9a-f]{32})\"",
            "name": "TraceID",
            "url": "${__value.raw}"
          }
        ]
      }
    }
  ]
}
````

### [observability/loki.yaml](observability/loki.yaml)

````yaml
auth_enabled: false
server: {http_listen_port: 3100}
common:
  path_prefix: /loki
  storage:
    filesystem: {chunks_directory: /loki/chunks, rules_directory: /loki/rules}
  replication_factor: 1
  ring:
    kvstore: {store: inmemory}
schema_config:
  configs:
    - from: '2024-04-01'
      store: tsdb
      object_store: filesystem
      schema: v13
      index: {prefix: index_, period: 24h}
limits_config: {allow_structured_metadata: true, retention_period: 24h}
compactor:
  working_directory: /loki/compactor
  retention_enabled: true
  delete_request_store: filesystem
````

### [observability/prometheus.yaml](observability/prometheus.yaml)

````yaml
global: {scrape_interval: 5s, evaluation_interval: 5s}
rule_files: [/etc/prometheus/alerts.yaml]
scrape_configs:
  - job_name: veriqta
    static_configs:
      - targets: ['gateway:8080','checkout:8080','payment:8080','inventory:8080']
````

### [observability/tempo.yaml](observability/tempo.yaml)

````yaml
server: {http_listen_port: 3200}
distributor:
  receivers:
    otlp:
      protocols:
        grpc: {endpoint: '0.0.0.0:4317'}
        http: {endpoint: '0.0.0.0:4318'}
storage:
  trace:
    backend: local
    wal: {path: /var/tempo/wal}
    local: {path: /var/tempo/blocks}
compactor:
  compaction: {block_retention: 24h}
````

### [policies/terraform.rego](policies/terraform.rego)

````rego
package veriqta.terraform
import rego.v1

changes := object.get(input,"resource_changes",[])

violations contains {"address":r.address,"rule":"destructive","reason":"deletion or replacement"} if {
 some r in changes
 "delete" in r.change.actions
}
violations contains {"address":r.address,"rule":"encryption","reason":"RDS encryption is not proven"} if {
 some r in changes
 r.type == "aws_db_instance"
 not "delete" in r.change.actions
 object.get(r.change.after,"storage_encrypted",false) != true
}
violations contains {"address":r.address,"rule":"public-database","reason":"public RDS access"} if {
 some r in changes
 r.type == "aws_db_instance"
 r.change.after.publicly_accessible == true
}
violations contains {"address":r.address,"rule":"owner","reason":"missing owner tag"} if {
 some r in changes
 r.mode == "managed"
 r.type in {"aws_db_instance","aws_vpc","aws_s3_bucket","aws_eks_cluster","aws_iam_role","aws_sqs_queue"}
 object.get(object.get(object.get(r.change,"after",{}),"tags_all",{}),"Owner","") == ""
}
violations contains {"address":r.address,"rule":"public-ingress","reason":"public management port"} if {
 some r in changes
 r.type == "aws_vpc_security_group_ingress_rule"
 cidr := object.get(r.change.after,"cidr_ipv4",object.get(r.change.after,"cidr_ipv6",""))
 cidr in {"0.0.0.0/0","::/0"}
 not "delete" in r.change.actions
}
violations contains {"address":r.address,"rule":"iam-review","reason":"all IAM policy changes require policy-specific review"} if {
 some r in changes
 r.type in {"aws_iam_policy","aws_iam_role_policy"}
 r.change.actions != ["no-op"]
}

violations contains {"address":r.address,"rule":"unknown-ingress","reason":"unresolved network policy"} if {
 some r in changes
 r.type == "aws_vpc_security_group_ingress_rule"
 some key in {"cidr_ipv4","cidr_ipv6","ip_protocol","from_port","to_port"}
 object.get(object.get(r.change,"after_unknown",{}),key,false) == true
}
````

### [policies/terraform_test.rego](policies/terraform_test.rego)

````rego
package veriqta.terraform_test
import rego.v1
import data.veriqta.terraform.violations

test_database_replacement if {
 v := violations with input as {"resource_changes":[{"address":"db","type":"aws_db_instance","change":{"actions":["delete","create"],"after":{"storage_encrypted":true}}}]}
 some finding in v
 finding.rule == "destructive"
}
test_public_database if {
 v := violations with input as {"resource_changes":[{"address":"db","type":"aws_db_instance","change":{"actions":["update"],"after":{"storage_encrypted":true,"publicly_accessible":true}}}]}
 some finding in v
 finding.rule == "public-database"
}
````

### [projects/01-resilience/argocd-application.yaml](projects/01-resilience/argocd-application.yaml)

````yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: {name: veriqta-app, namespace: argocd}
spec:
  project: veriqta
  source:
    repoURL: https://github.com/YOUR-ORGANIZATION/YOUR-LAB-GITOPS.git
    targetRevision: main
    path: kubernetes
  destination: {server: 'https://kubernetes.default.svc', namespace: veriqta}
  syncPolicy:
    syncOptions: [CreateNamespace=true]
````

### [projects/01-resilience/argocd-project.yaml](projects/01-resilience/argocd-project.yaml)

````yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata: {name: veriqta, namespace: argocd}
spec:
  sourceRepos: ['https://github.com/YOUR-ORGANIZATION/YOUR-LAB-GITOPS.git']
  destinations: [{server: 'https://kubernetes.default.svc', namespace: veriqta}]
  namespaceResourceWhitelist: [{group: '*', kind: '*'}]
  clusterResourceWhitelist: [{group: '', kind: Namespace}]
````

### [projects/01-resilience/scenario.json](projects/01-resilience/scenario.json)

````json
{
  "state": {
    "attempts": 2,
    "last_attempt": 0
  },
  "observed": {
    "dependency_healthy": false,
    "ready": 1,
    "minimum_ready": 2,
    "crash_loop": true
  }
}
````

### [projects/02-secure-delivery/cluster-image-policy.yaml](projects/02-secure-delivery/cluster-image-policy.yaml)

````yaml
apiVersion: policy.sigstore.dev/v1beta1
kind: ClusterImagePolicy
metadata: {name: veriqta-release}
spec:
  images:
    - glob: 'ACCOUNT.dkr.ecr.REGION.amazonaws.com/veriqta**'
  authorities:
    - keyless:
        identities:
          - issuer: https://token.actions.githubusercontent.com
            subject: https://github.com/ORGANIZATION/REPOSITORY/.github/workflows/release.yml@refs/heads/main
````

### [projects/02-secure-delivery/digest-policy.yaml](projects/02-secure-delivery/digest-policy.yaml)

````yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata: {name: veriqta-digest}
spec:
  failurePolicy: Fail
  matchConstraints:
    namespaceSelector:
      matchLabels: {policy.sigstore.dev/include: 'true'}
    resourceRules:
      - apiGroups: ['']
        apiVersions: [v1]
        operations: [CREATE, UPDATE]
        resources: [pods]
  validations:
    - expression: "object.spec.containers.all(c, c.image.matches('^.+@sha256:[a-f0-9]{64}$'))"
      message: Images must be pinned by immutable digest.
    - expression: "!has(object.spec.initContainers) || object.spec.initContainers.all(c, c.image.matches('^.+@sha256:[a-f0-9]{64}$'))"
      message: Init containers must also be pinned by digest.
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata: {name: veriqta-digest}
spec:
  policyName: veriqta-digest
  validationActions: [Deny]
````

### [projects/05-self-service/backstage-config.yaml](projects/05-self-service/backstage-config.yaml)

````yaml
app: {title: Veriqta Developer Portal, baseUrl: 'http://localhost:3000'}
backend:
  baseUrl: http://localhost:7007
  listen: {port: 7007}
  cors: {origin: 'http://localhost:3000', credentials: true}
  database:
    client: pg
    connection: ${BACKSTAGE_DATABASE_URL}
integrations:
  github:
    - host: github.com
      token: ${BACKSTAGE_GITHUB_TOKEN}
catalog:
  rules: [{allow: [Component, System, API, Resource, Location, Template, Group, User]}]
  locations:
    - type: file
      target: ../../veriqta-template/backstage-template.yaml
permission: {enabled: true}
````

### [projects/05-self-service/backstage-template.yaml](projects/05-self-service/backstage-template.yaml)

````yaml
apiVersion: scaffolder.backstage.io/v1beta3
kind: Template
metadata: {name: veriqta-service, title: Veriqta approved service}
spec:
  owner: group:default/veriqta-platform
  type: service
  parameters:
    - title: Service identity
      required: [name, owner]
      properties:
        name: {type: string, pattern: '^veriqta-[a-z][a-z0-9-]{1,30}$'}
        owner: {type: string, enum: ['group:default/veriqta-platform','group:default/veriqta-payments']}
  steps:
    - id: fetch
      name: Fetch approved skeleton
      action: fetch:template
      input:
        url: ./skeleton
        values: {name: '${{ parameters.name }}', owner: '${{ parameters.owner }}'}
    - id: publish
      name: Create service repository
      action: publish:github
      input:
        repoUrl: github.com?owner=YOUR-ORGANIZATION&repo=${{ parameters.name }}
        repoVisibility: private
        defaultBranch: main
    - id: register
      name: Register ownership
      action: catalog:register
      input:
        repoContentsUrl: ${{ steps.publish.output.repoContentsUrl }}
        catalogInfoPath: /catalog-info.yaml
  output:
    links:
      - {title: Service repository, url: '${{ steps.publish.output.remoteUrl }}'}
````

### [projects/05-self-service/permission-module.ts](projects/05-self-service/permission-module.ts)

````typescript
import { createBackendModule } from '@backstage/backend-plugin-api';
import { policyExtensionPoint } from '@backstage/plugin-permission-node/alpha';
import { VeriqtaPermissionPolicy } from './permission-policy';
export default createBackendModule({
  pluginId: 'permission', moduleId: 'veriqta-policy',
  register(reg) {
    reg.registerInit({ deps: { policy: policyExtensionPoint },
      async init({ policy }) { policy.setPolicy(new VeriqtaPermissionPolicy()); },
    });
  },
});
````

### [projects/05-self-service/permission-policy.ts](projects/05-self-service/permission-policy.ts)

````typescript
import { AuthorizeResult, isPermission, PolicyDecision } from '@backstage/plugin-permission-common';
import { PermissionPolicy, PolicyQuery, PolicyQueryUser } from '@backstage/plugin-permission-node';
import { actionExecutePermission, taskCreatePermission, taskReadPermission, taskCancelPermission, templateParameterReadPermission, templateStepReadPermission } from '@backstage/plugin-scaffolder-common/alpha';
import { createScaffolderActionConditionalDecision, scaffolderActionConditions, createScaffolderTaskConditionalDecision, scaffolderTaskConditions } from '@backstage/plugin-scaffolder-backend/alpha';

export class VeriqtaPermissionPolicy implements PermissionPolicy {
  async handle(request: PolicyQuery, user?: PolicyQueryUser): Promise<PolicyDecision> {
    const member = user?.info.ownershipEntityRefs.some(ref =>
      ['group:default/veriqta-platform', 'group:default/veriqta-payments'].includes(ref));
    if (!member) return { result: AuthorizeResult.DENY };
    if (isPermission(request.permission, actionExecutePermission)) {
      return createScaffolderActionConditionalDecision(request.permission, {
        anyOf: ['fetch:template', 'publish:github', 'catalog:register'].map(actionId =>
          scaffolderActionConditions.hasActionId({ actionId })),
      });
    }
    if (isPermission(request.permission, taskReadPermission) || isPermission(request.permission, taskCancelPermission)) {
      return createScaffolderTaskConditionalDecision(request.permission,
        scaffolderTaskConditions.isTaskOwner({ createdBy: [user!.info.userEntityRef] }));
    }
    if (isPermission(request.permission, taskCreatePermission) ||
        isPermission(request.permission, templateParameterReadPermission) ||
        isPermission(request.permission, templateStepReadPermission) ||
        request.permission.name === 'catalog.entity.read') return { result: AuthorizeResult.ALLOW };
    return { result: AuthorizeResult.DENY };
  }
}
````

### [projects/05-self-service/request.json](projects/05-self-service/request.json)

````json
{
  "name": "veriqta-orders",
  "owner": "group:default/veriqta-platform",
  "environment": "dev",
  "cpu_millicores": 250,
  "memory_mib": 256
}
````

### [projects/05-self-service/skeleton/catalog-info.yaml](projects/05-self-service/skeleton/catalog-info.yaml)

````yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata: {name: '${{ values.name }}'}
spec: {type: service, lifecycle: experimental, owner: '${{ values.owner }}'}
````

### [projects/06-finops/recommendations.json](projects/06-finops/recommendations.json)

````json
[
  {
    "resource": "veriqta-batch",
    "owner": "veriqta-platform",
    "application": "batch",
    "environment": "dev",
    "currency": "USD",
    "observation_days": 21,
    "telemetry_age_minutes": 10,
    "critical_database": false,
    "standby_required": false,
    "remaining_peak_capacity": 120,
    "required_peak_capacity": 100,
    "p95_seconds": 0.2,
    "p95_seconds_limit": 0.5,
    "error_rate": 0.001,
    "error_rate_limit": 0.01,
    "rto_seconds": 200,
    "rto_seconds_limit": 300,
    "rpo_seconds": 30,
    "rpo_seconds_limit": 60,
    "estimated_monthly_savings": "25.50",
    "rollback": "restore previous instance size and verify queue drain"
  },
  {
    "resource": "veriqta-standby",
    "owner": "veriqta-platform",
    "application": "batch",
    "environment": "dev",
    "currency": "USD",
    "observation_days": 21,
    "telemetry_age_minutes": 10,
    "critical_database": false,
    "standby_required": true,
    "remaining_peak_capacity": 120,
    "required_peak_capacity": 100,
    "p95_seconds": 0.2,
    "p95_seconds_limit": 0.5,
    "error_rate": 0.001,
    "error_rate_limit": 0.01,
    "rto_seconds": 200,
    "rto_seconds_limit": 300,
    "rpo_seconds": 30,
    "rpo_seconds_limit": 60,
    "estimated_monthly_savings": "25.50",
    "rollback": "restore previous instance size and verify queue drain"
  },
  {
    "resource": "veriqta-db",
    "owner": "veriqta-platform",
    "application": "batch",
    "environment": "dev",
    "currency": "USD",
    "observation_days": 21,
    "telemetry_age_minutes": 10,
    "critical_database": true,
    "standby_required": false,
    "remaining_peak_capacity": 120,
    "required_peak_capacity": 100,
    "p95_seconds": 0.2,
    "p95_seconds_limit": 0.5,
    "error_rate": 0.001,
    "error_rate_limit": 0.01,
    "rto_seconds": 200,
    "rto_seconds_limit": 300,
    "rpo_seconds": 30,
    "rpo_seconds_limit": 60,
    "estimated_monthly_savings": "25.50",
    "rollback": "restore previous instance size and verify queue drain"
  }
]
````

### [projects/07-progressive-delivery/analysis.yaml](projects/07-progressive-delivery/analysis.yaml)

````yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: checkout-slo
  namespace: veriqta-release
spec:
  args:
  - name: canary-hash
  metrics:
  - name: request-evidence
    interval: 30s
    count: 3
    inconclusiveLimit: 1
    successCondition: len(result) == 1 && result[0] >= 100
    provider:
      prometheus:
        address: http://prometheus-operated.monitoring.svc:9090
        query: sum(increase(veriqta_http_requests_total{service="checkout",route="/checkout",release="{{args.canary-hash}}"}[2m]))
  - name: error-rate
    interval: 30s
    count: 3
    failureLimit: 0
    inconclusiveLimit: 1
    successCondition: len(result) == 1 && result[0] <= 0.01
    failureCondition: len(result) == 1 && result[0] > 0.01
    provider:
      prometheus:
        address: http://prometheus-operated.monitoring.svc:9090
        query: (sum(increase(veriqta_http_requests_total{service="checkout",route="/checkout",release="{{args.canary-hash}}",status=~"5.."}[2m]))
          or vector(0)) / sum(increase(veriqta_http_requests_total{service="checkout",route="/checkout",release="{{args.canary-hash}}"}[2m]))
  - name: p95
    interval: 30s
    count: 3
    failureLimit: 0
    inconclusiveLimit: 1
    successCondition: len(result) == 1 && result[0] <= 0.5
    failureCondition: len(result) == 1 && result[0] > 0.5
    provider:
      prometheus:
        address: http://prometheus-operated.monitoring.svc:9090
        query: histogram_quantile(0.95,sum by(le)(rate(veriqta_http_duration_seconds_bucket{service="checkout",route="/checkout",release="{{args.canary-hash}}"}[2m])))
````

### [projects/07-progressive-delivery/bad.json](projects/07-progressive-delivery/bad.json)

````json
{
  "requests": 1000,
  "errors": 35,
  "p95_seconds": 1.2,
  "age_seconds": 10,
  "schema_backward_compatible": true
}
````

### [projects/07-progressive-delivery/blue-green.yaml](projects/07-progressive-delivery/blue-green.yaml)

````yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: checkout
  namespace: veriqta-release
spec:
  replicas: 3
  selector:
    matchLabels:
      app: checkout
  template:
    metadata:
      labels:
        app: checkout
    spec:
      serviceAccountName: veriqta-app
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: checkout
        image: veriqta9-app:local
        ports:
        - name: http
          containerPort: 8080
        env:
        - name: SERVICE_NAME
          value: checkout
        - name: DB_HOST
          valueFrom:
            configMapKeyRef:
              name: veriqta-config
              key: DB_HOST
        - name: DB_SECRET_ARN
          valueFrom:
            configMapKeyRef:
              name: veriqta-config
              key: DB_SECRET_ARN
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: http://otel.monitoring:4318
        - name: RELEASE
          valueFrom:
            fieldRef:
              fieldPath: metadata.labels['rollouts-pod-template-hash']
        - name: PAYMENT_URL
          value: http://payment.veriqta.svc:8080/pay
        - name: INVENTORY_URL
          value: http://inventory.veriqta.svc:8080/reserve
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
        readinessProbe:
          httpGet:
            path: /readyz
            port: http
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /healthz
            port: http
          initialDelaySeconds: 20
          periodSeconds: 10
        volumeMounts:
        - name: tmp
          mountPath: /tmp
      volumes:
      - name: tmp
        emptyDir: {}
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            app: checkout
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            app: checkout
  strategy:
    blueGreen:
      activeService: checkout-stable
      previewService: checkout-canary
      autoPromotionEnabled: false
      scaleDownDelaySeconds: 60
````

### [projects/07-progressive-delivery/good.json](projects/07-progressive-delivery/good.json)

````json
{
  "requests": 1000,
  "errors": 2,
  "p95_seconds": 0.2,
  "age_seconds": 10,
  "schema_backward_compatible": true
}
````

### [projects/07-progressive-delivery/hpa.yaml](projects/07-progressive-delivery/hpa.yaml)

````yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: checkout
  namespace: veriqta-release
spec:
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
  maxReplicas: 12
  metrics:
  - resource:
      name: cpu
      target:
        averageUtilization: 60
        type: Utilization
    type: Resource
  minReplicas: 3
  scaleTargetRef:
    apiVersion: argoproj.io/v1alpha1
    kind: Rollout
    name: checkout
````

### [projects/07-progressive-delivery/ingress.yaml](projects/07-progressive-delivery/ingress.yaml)

````yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: checkout
  namespace: veriqta-release
spec:
  ingressClassName: nginx
  rules:
  - host: checkout.veriqta.test
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: checkout-stable
            port:
              number: 8080
````

### [projects/07-progressive-delivery/migration-expand.sql](projects/07-progressive-delivery/migration-expand.sql)

````sql
ALTER TABLE orders ADD COLUMN IF NOT EXISTS currency text DEFAULT 'USD';
````

### [projects/07-progressive-delivery/migration-unsafe.sql](projects/07-progressive-delivery/migration-unsafe.sql)

````sql
-- Deliberately unsafe review fixture. Do not execute against a live database.
ALTER TABLE orders DROP COLUMN amount_cents;
````

### [projects/07-progressive-delivery/namespace.yaml](projects/07-progressive-delivery/namespace.yaml)

````yaml
apiVersion: v1
kind: Namespace
metadata:
  labels:
    pod-security.kubernetes.io/enforce: restricted
  name: veriqta-release
````

### [projects/07-progressive-delivery/rollout.yaml](projects/07-progressive-delivery/rollout.yaml)

````yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: checkout
  namespace: veriqta-release
spec:
  replicas: 3
  selector:
    matchLabels:
      app: checkout
  template:
    metadata:
      labels:
        app: checkout
    spec:
      serviceAccountName: veriqta-app
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: checkout
        image: veriqta9-app:local
        ports:
        - name: http
          containerPort: 8080
        env:
        - name: SERVICE_NAME
          value: checkout
        - name: DB_HOST
          valueFrom:
            configMapKeyRef:
              name: veriqta-config
              key: DB_HOST
        - name: DB_SECRET_ARN
          valueFrom:
            configMapKeyRef:
              name: veriqta-config
              key: DB_SECRET_ARN
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: http://otel.monitoring:4318
        - name: RELEASE
          valueFrom:
            fieldRef:
              fieldPath: metadata.labels['rollouts-pod-template-hash']
        - name: PAYMENT_URL
          value: http://payment.veriqta.svc:8080/pay
        - name: INVENTORY_URL
          value: http://inventory.veriqta.svc:8080/reserve
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
        readinessProbe:
          httpGet:
            path: /readyz
            port: http
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /healthz
            port: http
          initialDelaySeconds: 20
          periodSeconds: 10
        volumeMounts:
        - name: tmp
          mountPath: /tmp
      volumes:
      - name: tmp
        emptyDir: {}
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            app: checkout
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            app: checkout
  strategy:
    canary:
      stableService: checkout-stable
      canaryService: checkout-canary
      trafficRouting:
        nginx:
          stableIngress: checkout
      steps:
      - setWeight: 10
      - pause:
          duration: 60s
      - analysis:
          templates:
          - templateName: checkout-slo
          args:
          - name: canary-hash
            valueFrom:
              podTemplateHashValue: Latest
      - setWeight: 50
      - pause: {}
      - setWeight: 100
````

### [projects/07-progressive-delivery/service-canary.yaml](projects/07-progressive-delivery/service-canary.yaml)

````yaml
apiVersion: v1
kind: Service
metadata:
  name: checkout-canary
  namespace: veriqta-release
spec:
  selector:
    app: checkout
  ports:
  - name: http
    port: 8080
    targetPort: http
````

### [projects/07-progressive-delivery/service-stable.yaml](projects/07-progressive-delivery/service-stable.yaml)

````yaml
apiVersion: v1
kind: Service
metadata:
  name: checkout-stable
  namespace: veriqta-release
spec:
  selector:
    app: checkout
  ports:
  - name: http
    port: 8080
    targetPort: http
````

### [projects/09-governance/compliant-plan.json](projects/09-governance/compliant-plan.json)

````json
{
  "resource_changes": [
    {
      "address": "aws_db_instance.database",
      "mode": "managed",
      "type": "aws_db_instance",
      "change": {
        "actions": [
          "update"
        ],
        "after": {
          "storage_encrypted": true,
          "publicly_accessible": false,
          "tags_all": {
            "Owner": "veriqta"
          }
        }
      }
    }
  ]
}
````

### [projects/09-governance/dangerous-plan.json](projects/09-governance/dangerous-plan.json)

````json
{
  "resource_changes": [
    {
      "address": "aws_db_instance.database",
      "mode": "managed",
      "type": "aws_db_instance",
      "change": {
        "actions": [
          "delete",
          "create"
        ],
        "after": {
          "storage_encrypted": false,
          "publicly_accessible": true,
          "tags_all": {
            "Owner": ""
          }
        }
      }
    },
    {
      "address": "aws_iam_role_policy.admin",
      "mode": "managed",
      "type": "aws_iam_role_policy",
      "change": {
        "actions": [
          "create"
        ],
        "after": {
          "policy": "{\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"*\",\"Resource\":\"*\"}]}"
        }
      }
    }
  ]
}
````

### [projects/10-incident-command/alerts.json](projects/10-incident-command/alerts.json)

````json
[
  {
    "event_id": "veriqta-app-1",
    "service": "checkout",
    "dependency": "postgres",
    "environment": "lab",
    "burn_rate": 20,
    "impact": "checkout failures"
  },
  {
    "event_id": "veriqta-db-1",
    "service": "checkout",
    "dependency": "postgres",
    "environment": "lab",
    "burn_rate": 20,
    "impact": "database saturation"
  }
]
````

### [projects/10-incident-command/diagnose-database.yaml](projects/10-incident-command/diagnose-database.yaml)

````yaml
schemaVersion: '0.3'
description: Veriqta approved read-only database diagnosis
assumeRole: '{{ AutomationAssumeRole }}'
parameters:
  AutomationAssumeRole: {type: String, description: Approved diagnostic execution role}
  DatabaseIdentifier: {type: String, allowedPattern: '^veriqta-[a-z0-9-]+$'}
mainSteps:
  - name: inspect
    action: aws:executeAwsApi
    inputs:
      Service: rds
      Api: DescribeDBInstances
      DBInstanceIdentifier: '{{ DatabaseIdentifier }}'
    outputs:
      - {Name: Status, Selector: '$.DBInstances[0].DBInstanceStatus', Type: String}
````

### [pyproject.toml](pyproject.toml)

````toml
[build-system]
requires = ["setuptools>=75,<81"]
build-backend = "setuptools.build_meta"

[project]
name = "veriqta-devops-projects"
version = "1.0.0"
requires-python = ">=3.11"

[tool.setuptools.packages.find]
include = ["application*", "engineering*"]
````

### [requirements.txt](requirements.txt)

````text
fastapi==0.115.12
uvicorn==0.34.3
psycopg[binary]==3.2.12
psycopg-pool==3.2.6
boto3==1.40.64
prometheus-client==0.22.1
opentelemetry-api==1.37.0
opentelemetry-sdk==1.37.0
opentelemetry-exporter-otlp-proto-http==1.37.0
cryptography==45.0.7
PyYAML==6.0.2
httpx==0.28.1
````

### [scripts/backup.py](scripts/backup.py)

````python
"""Encrypted local PostgreSQL + object-directory backup/restore. No cloud API calls."""
import argparse,base64,datetime as dt,hashlib,json,subprocess
from pathlib import Path
from cryptography.fernet import Fernet
ROOT=Path(__file__).resolve().parents[1]
def compose(*args,input=None):
    return subprocess.run(['docker','compose','--env-file',str(ROOT/'.private/lab.env'),'-f',str(ROOT/'compose.yaml'),*args],input=input,capture_output=True,check=True).stdout
p=argparse.ArgumentParser();p.add_argument('action',choices=['backup','restore']);p.add_argument('file',type=Path);p.add_argument('--objects',type=Path,default=ROOT/'.private/objects');p.add_argument('--key',type=Path,default=ROOT/'.private/backup.key');a=p.parse_args()
fernet=Fernet(a.key.read_bytes().strip())
if a.action=='backup':
    dump=compose('exec','-T','primary','pg_dump','-U','veriqta','-d','veriqta','-Fc')
    objects={}
    if a.objects.exists():
        for f in a.objects.rglob('*'):
            if f.is_symlink():raise ValueError('symlink objects are not accepted')
            if f.is_file():objects[str(f.relative_to(a.objects))]=base64.b64encode(f.read_bytes()).decode()
    data={'captured_at':dt.datetime.now(dt.timezone.utc).isoformat(),'dump':base64.b64encode(dump).decode(),'objects':objects,
          'dump_digest':hashlib.sha256(dump).hexdigest()}
    a.file.parent.mkdir(parents=True,exist_ok=True);a.file.write_bytes(fernet.encrypt(json.dumps(data).encode()))
    print('Encrypted backup created; validate by restoring it to recovery.')
else:
    started=dt.datetime.now(dt.timezone.utc)
    data=json.loads(fernet.decrypt(a.file.read_bytes()))
    dump=base64.b64decode(data['dump'])
    if hashlib.sha256(dump).hexdigest()!=data['dump_digest']:raise ValueError('dump integrity failed')
    # Always the isolated recovery database; never default to the primary.
    compose('exec','-T','recovery','pg_restore','-U','veriqta','-d','veriqta','--clean','--if-exists','--no-owner','--exit-on-error',input=dump)
    a.objects.mkdir(parents=True,exist_ok=True)
    for name,encoded in data['objects'].items():
        target=(a.objects/name).resolve()
        if not target.is_relative_to(a.objects.resolve()):raise ValueError('unsafe object path')
        target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(base64.b64decode(encoded))
    print(json.dumps({'restore_seconds':(dt.datetime.now(dt.timezone.utc)-started).total_seconds(),'backup_captured_at':data['captured_at'],
                      'status':'restore completed; application/marker verification still required'}))
````

### [scripts/compose_recovery.py](scripts/compose_recovery.py)

````python
"""Run an isolated local restore/new-write drill after compose_smoke.py; no AWS APIs."""
import json,os,subprocess,sys,time,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
os.chdir(ROOT)
def run(*args,env=None):subprocess.run([sys.executable,*args],check=True,env=env)
password=dict(line.split('=',1) for line in (ROOT/'.private/lab.env').read_text().splitlines())['PGPASSWORD']
objects=ROOT/'.private/objects';objects.mkdir(exist_ok=True)
(objects/'veriqta-probe.txt').write_text('veriqta recovery object\n')
started=time.monotonic()
run('scripts/lab.py','stop','gateway','checkout','worker')
run('scripts/backup.py','backup','.private/ci-backup.fernet')
run('scripts/backup.py','restore','.private/ci-backup.fernet','--objects','.private/recovered-objects')
assert (ROOT/'.private/recovered-objects/veriqta-probe.txt').read_bytes()==(objects/'veriqta-probe.txt').read_bytes()
env=dict(os.environ,PRIMARY_DATABASE_URL=f'postgresql://veriqta:{password}@127.0.0.1:15432/veriqta',RECOVERY_DATABASE_URL=f'postgresql://veriqta:{password}@127.0.0.1:15433/veriqta')
run('scripts/verify_recovery.py','--marker','veriqta-smoke-0',env=env)
env.update(DATABASE_URL=env['RECOVERY_DATABASE_URL'],SERVICE_NAME='checkout',PAYMENT_URL='http://127.0.0.1:18082/pay',INVENTORY_URL='http://127.0.0.1:18083/reserve')
env.pop('OTEL_EXPORTER_OTLP_ENDPOINT',None)
with open(ROOT/'.private/recovered-api.log','wb') as log:
 process=subprocess.Popen([sys.executable,'-m','uvicorn','application.api:app','--host','127.0.0.1','--port','18084'],env=env,stdout=log,stderr=log)
 try:
  for attempt in range(30):
   try:
    with urllib.request.urlopen('http://127.0.0.1:18084/readyz',timeout=2) as r:
     if r.status==200:break
   except Exception:time.sleep(1)
  else:raise RuntimeError('Recovered application never became ready')
  req=urllib.request.Request('http://127.0.0.1:18084/checkout',data=b'',method='POST',headers={'Idempotency-Key':'veriqta-recovered-new-write'})
  with urllib.request.urlopen(req,timeout=10) as r:assert json.load(r)['status']=='accepted'
 finally:
  process.terminate();process.wait(timeout=20)
print(json.dumps({'local_exercise_seconds':round(time.monotonic()-started,2),'data':'frozen source records and object match','recovered_application':'new checkout accepted','note':'Restart gateway/checkout/worker deliberately after the drill.'}))
````

### [scripts/compose_smoke.py](scripts/compose_smoke.py)

````python
"""Exercise only the local Compose API. Exit nonzero on a broken application path."""
import json,time,urllib.request
from pathlib import Path
for attempt in range(60):
 try:
  with urllib.request.urlopen('http://127.0.0.1:18080/readyz',timeout=2) as r:
   if r.status==200:break
 except Exception:time.sleep(2)
else:raise SystemExit('Local API never became ready')
for i in range(5):
 req=urllib.request.Request('http://127.0.0.1:18080/checkout',data=b'',method='POST',headers={'Idempotency-Key':'veriqta-smoke-'+str(i)})
 with urllib.request.urlopen(req,timeout=10) as r:
  assert json.load(r)['status']=='accepted'
print('Local gateway -> checkout -> payment/inventory -> PostgreSQL path passed.')
````

### [scripts/cost_ingest.py](scripts/cost_ingest.py)

````python
"""Read-only Cost Explorer export. Requires an approved billing role; does not send notifications."""
import argparse,json
from pathlib import Path
import boto3
p=argparse.ArgumentParser();p.add_argument('start');p.add_argument('end');p.add_argument('--output',type=Path,required=True);a=p.parse_args()
client=boto3.client('ce',region_name='us-east-1');token=None;pages=[]
while True:
    request={'TimePeriod':{'Start':a.start,'End':a.end},'Granularity':'DAILY','Metrics':['UnblendedCost'],'GroupBy':[{'Type':'DIMENSION','Key':'SERVICE'},{'Type':'TAG','Key':'Owner'}]}
    if token:request['NextPageToken']=token
    response=client.get_cost_and_usage(**request);pages.append(response)
    token=response.get('NextPageToken')
    if not token:break
a.output.parent.mkdir(parents=True,exist_ok=True)
a.output.write_text(json.dumps(pages,default=str,indent=2))
print('Private billing export written; preserve currency, estimated flags, credits, account scope and exclusive end date when comparing.')
````

### [scripts/decision.py](scripts/decision.py)

````python
import argparse,json
from pathlib import Path
from engineering import recovery,release,finops
p=argparse.ArgumentParser();p.add_argument('kind',choices=['recovery','release','finops']);p.add_argument('input',type=Path);a=p.parse_args()
data=json.loads(a.input.read_text())
result=recovery.decide(data['state'],data['observed']) if a.kind=='recovery' else release.decision(data) if a.kind=='release' else [finops.assess(row) for row in data]
print(json.dumps(result,indent=2))
````

### [scripts/fault.py](scripts/fault.py)

````python
"""Bounded faults against the local Compose lab only."""
import argparse,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('kind',choices=['db-lock','db-loss','restore-db']);a=p.parse_args()
base=['docker','compose','--env-file',str(ROOT/'.private/lab.env'),'-f',str(ROOT/'compose.yaml')]
if a.kind=='db-lock':
    subprocess.run(base+['exec','-T','primary','psql','-U','veriqta','-d','veriqta','-v','ON_ERROR_STOP=1','-c',"BEGIN; SELECT * FROM inventory WHERE id=1 FOR UPDATE; SELECT pg_sleep(20); ROLLBACK;"],check=True)
elif a.kind=='db-loss':subprocess.run(base+['stop','primary'],check=True)
else:subprocess.run(base+['start','primary'],check=True)
````

### [scripts/governance.py](scripts/governance.py)

````python
import argparse,json,subprocess,re
from pathlib import Path
from engineering.governance import validate_exception
p=argparse.ArgumentParser();p.add_argument('plan',type=Path)
p.add_argument('--approval-repository',type=Path);p.add_argument('--approval-commit')
a=p.parse_args();plan=json.loads(a.plan.read_text())
result=subprocess.run(['opa','eval','--format=json','--data','policies/terraform.rego','--input',str(a.plan),'data.veriqta.terraform.violations'],capture_output=True,text=True,check=True)
findings=json.loads(result.stdout)['result'][0]['expressions'][0]['value']
if a.approval_repository:
    if not re.fullmatch('[a-f0-9]{40}',a.approval_commit or ''):raise SystemExit('Pin the trusted approval commit.')
    commit=subprocess.check_output(['git','-C',str(a.approval_repository),'rev-parse','HEAD'],text=True).strip()
    if commit!=a.approval_commit:raise SystemExit('Wrong approval checkout.')
    # Read committed objects, not a dirty working tree that untrusted code could have modified.
    def read(name):return json.loads(subprocess.check_output(['git','-C',str(a.approval_repository),'show',commit+':'+name],text=True))
    approvers=read('approvers.json');exceptions=read('approved.json')
    for e in exceptions:
        validate_exception(e,plan,approvers)
        findings=[f for f in findings if not (f['address']==e['resource'] and f['rule']==e['rule'])]
print(json.dumps(findings,indent=2));raise SystemExit(2 if findings else 0)
````

### [scripts/incident_api.py](scripts/incident_api.py)

````python
"""Local incident intake. Approval is a separate authenticated operator path, never an alert field."""
import os,secrets
from pathlib import Path
from fastapi import FastAPI,HTTPException,Header
from engineering.incident import IncidentStore
app=FastAPI(title='Veriqta incident intake')
store=IncidentStore(Path(os.getenv('INCIDENT_DB','.private/incidents.db')))
@app.post('/alerts')
def alert(event:dict,authorization:str=Header(default='')):
    token=os.environ.get('INCIDENT_API_TOKEN','')
    if not token or not secrets.compare_digest(authorization,'Bearer '+token):raise HTTPException(401,'authentication required')
    try:return {'incident_id':store.ingest(event)}
    except ValueError as error:raise HTTPException(400,str(error))
@app.get('/incidents/{incident}')
def report(incident:str,authorization:str=Header(default='')):
    token=os.environ.get('INCIDENT_API_TOKEN','')
    if not token or not secrets.compare_digest(authorization,'Bearer '+token):raise HTTPException(401,'authentication required')
    return store.report(incident)
````

### [scripts/incident_operator.py](scripts/incident_operator.py)

````python
import argparse,json,os
from pathlib import Path
from engineering.incident import IncidentStore
p=argparse.ArgumentParser();p.add_argument('action',choices=['claim','resolve','report']);p.add_argument('incident');p.add_argument('--runbook',default='diagnose-database');p.add_argument('--checks',type=Path);a=p.parse_args()
store=IncidentStore('.private/incidents.db')
if a.action=='claim':
    # This CLI must run in a protected operator environment. An arbitrary environment variable is not an identity provider.
    approved=os.environ.get('AUTHENTICATED_OPERATOR','')
    print('claimed' if store.claim(a.incident,a.runbook,approved) else 'already claimed; inspect execution before retrying')
elif a.action=='resolve':store.resolve(a.incident,json.loads(a.checks.read_text()))
else:print(json.dumps(store.report(a.incident),indent=2))
````

### [scripts/init_lab.py](scripts/init_lab.py)

````python
"""Create local secrets once. Existing secrets are never replaced."""
from pathlib import Path
import os,secrets
from cryptography.fernet import Fernet
root=Path(__file__).resolve().parents[1]
p=root/'.private';p.mkdir(mode=0o700,exist_ok=True)
for name,value in [('lab.env','PGPASSWORD='+secrets.token_hex(24)+'\nGRAFANA_PASSWORD='+secrets.token_hex(24)+'\n'),('backup.key',Fernet.generate_key().decode())]:
    path=p/name
    if not path.exists():
        fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
        with os.fdopen(fd,'w') as stream:stream.write(value)
print('Local secret files are ready in .private/. Keep the backup key separate from backup storage.')
````

### [scripts/lab.py](scripts/lab.py)

````python
"""Explicit local Docker Compose wrapper. No cloud profiles or Kubernetes contexts are used."""
from pathlib import Path
import subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
subprocess.run(['docker','compose','--env-file',str(ROOT/'.private/lab.env'),'-f',str(ROOT/'compose.yaml'),*sys.argv[1:]],cwd=ROOT,check=True)
````

### [scripts/preview_gc.py](scripts/preview_gc.py)

````python
"""Identify only rendered, expired preview requests. Print commands; never delete on a clock alone."""
import argparse,datetime as dt,json,shlex
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('directory',type=Path);a=p.parse_args()
for f in a.directory.glob('veriqta-*/request.json'):
    r=json.loads(f.read_text())
    if r.get('environment')!='preview':continue
    expiry=dt.datetime.fromisoformat(r['expires_at'])
    if expiry.tzinfo and expiry<dt.datetime.now(dt.timezone.utc):
        print('REVIEW expired preview:',r['name'],'owner:',r['owner'])
        print('kubectl --context YOUR-EXPLICIT-LAB-CONTEXT delete namespace '+shlex.quote(r['name']))
````

### [scripts/promote_gitops.py](scripts/promote_gitops.py)

````python
import argparse,re
from pathlib import Path
import yaml
p=argparse.ArgumentParser();p.add_argument('manifest',type=Path);p.add_argument('image');p.add_argument('commit');a=p.parse_args()
if not re.fullmatch(r'[^\s]+@sha256:[a-f0-9]{64}',a.image):raise SystemExit('Immutable image required.')
if not re.fullmatch('[a-f0-9]{40}',a.commit):raise SystemExit('Exact commit required.')
d=yaml.safe_load(a.manifest.read_text())
if d.get('kind')!='Deployment' or d.get('metadata',{}).get('name')!='checkout':raise SystemExit('Only the approved checkout Deployment may be changed.')
containers=d['spec']['template']['spec']['containers']
if len(containers)!=1 or containers[0]['name']!='checkout':raise SystemExit('Unexpected workload contract; review manually.')
containers[0]['image']=a.image
for e in containers[0].get('env',[]):
    if e['name']=='RELEASE':e.clear();e.update({'name':'RELEASE','value':a.commit})
a.manifest.write_text(yaml.safe_dump(d,sort_keys=False))
````

### [scripts/promote_writer.py](scripts/promote_writer.py)

````python
"""Promote only within the SAME authoritative PostgreSQL ledger. Never use this to authorize two independent databases."""
import argparse,os,psycopg
from application.ledger import promote
p=argparse.ArgumentParser();p.add_argument('--from-owner',required=True);p.add_argument('--from-epoch',type=int,required=True);p.add_argument('--to-owner',required=True);a=p.parse_args()
if not os.environ.get('DATABASE_URL'):raise SystemExit('Set the intended authoritative database connection explicitly.')
with psycopg.connect(os.environ['DATABASE_URL']) as c:epoch=promote(c,a.from_owner,a.from_epoch,a.to_owner)
print('New epoch:',epoch,'; update the approved writer configuration and verify old-writer rejection.')
````

### [scripts/release_namespace.py](scripts/release_namespace.py)

````python
import json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
v=json.loads((root/'.private/foundation.json').read_text())
(root/'.private/release-serviceaccount.json').write_text(json.dumps({'apiVersion':'v1','kind':'ServiceAccount','metadata':{'name':'veriqta-app','namespace':'veriqta-release'}}))
(root/'.private/release-config.json').write_text(json.dumps({'apiVersion':'v1','kind':'ConfigMap','metadata':{'name':'veriqta-config','namespace':'veriqta-release'},'data':{'DB_HOST':v['db_host'],'DB_SECRET_ARN':v['secret_arn']}}))
````

### [scripts/render_images.py](scripts/render_images.py)

````python
"""Render only local files. This script never contacts a Kubernetes API or registry."""
import argparse,copy,json,re
from pathlib import Path
import yaml
p=argparse.ArgumentParser();p.add_argument('--directory',type=Path,required=True);p.add_argument('--image',required=True);p.add_argument('--migration',action='store_true');a=p.parse_args()
if not re.fullmatch(r'[^\s]+@sha256:[a-f0-9]{64}',a.image):raise SystemExit('Supply the full reviewed image digest.')
checkout=None
for path in a.directory.glob('*.yaml'):
    data=yaml.safe_load(path.read_text())
    if not isinstance(data,dict) or data.get('kind') not in ('Deployment','Rollout'):continue
    for c in data['spec']['template']['spec']['containers']:c['image']=a.image
    if data['metadata']['name']=='checkout':checkout=copy.deepcopy(data['spec']['template'])
    path.write_text(yaml.safe_dump(data,sort_keys=False))
if a.migration:
    if checkout is None:raise SystemExit('Checkout template missing.')
    checkout['metadata']['labels']={'app':'veriqta-schema'}
    checkout['spec'].pop('topologySpreadConstraints',None)
    checkout['spec']['restartPolicy']='Never'
    c=checkout['spec']['containers'][0];c['command']=['python','-c','from application.db import initialize; initialize()']
    for field in ('readinessProbe','livenessProbe','ports'):c.pop(field,None)
    job={'apiVersion':'batch/v1','kind':'Job','metadata':{'name':'veriqta-schema','namespace':'veriqta'},'spec':{'backoffLimit':1,'template':checkout}}
    Path('.private').mkdir(exist_ok=True)
    Path('.private/migration-job.json').write_text(json.dumps(job,indent=2))
````

### [scripts/restore_metadata.py](scripts/restore_metadata.py)

````python
"""Prepare an RDS restore metadata candidate; review it before starting a restore."""
import argparse,json
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('response',type=Path);p.add_argument('--identifier',required=True);p.add_argument('--subnet-group',required=True);p.add_argument('--security-group',required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
m=json.loads(a.response.read_text())['RestoreMetadata']
m.update({'DBInstanceIdentifier':a.identifier,'DBSubnetGroupName':a.subnet_group,'VpcSecurityGroupIds':json.dumps([a.security_group]),'PubliclyAccessible':'false','MultiAZ':'true'})
a.output.write_text(json.dumps(m,indent=2));print('Candidate metadata written. Review engine, keys, option groups and every regional dependency before use.')
````

### [scripts/self_service.py](scripts/self_service.py)

````python
import argparse,json
from pathlib import Path
from engineering.platform import render
p=argparse.ArgumentParser();p.add_argument('request',type=Path);p.add_argument('--output',type=Path,default=Path('artifacts/generated'));a=p.parse_args()
print(render(json.loads(a.request.read_text()),a.output))
````

### [scripts/send_alerts.py](scripts/send_alerts.py)

````python
import argparse,json,os,urllib.request
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--url',default='http://127.0.0.1:18086');a=p.parse_args()
for event in json.loads((Path(__file__).resolve().parents[1]/'projects/10-incident-command/alerts.json').read_text()):
    req=urllib.request.Request(a.url.rstrip('/')+'/alerts',data=json.dumps(event).encode(),headers={'Content-Type':'application/json','Authorization':'Bearer '+os.environ['INCIDENT_API_TOKEN']},method='POST')
    with urllib.request.urlopen(req,timeout=5) as r:print(json.load(r))
````

### [scripts/ssm_operator.py](scripts/ssm_operator.py)

````python
"""Run in an authenticated operator environment. Every incident has one durable claim and deterministic SSM token."""
import argparse,os,boto3
from engineering.incident import IncidentStore
p=argparse.ArgumentParser();p.add_argument('incident');p.add_argument('--database',required=True);p.add_argument('--execution-role',required=True);a=p.parse_args()
operator=os.environ.get('AUTHENTICATED_OPERATOR','')
if not operator:raise SystemExit('A trusted operator environment must identify the approver.')
store=IncidentStore('.private/incidents.db')
claimed=store.claim(a.incident,'diagnose-database',operator)
report=store.report(a.incident)
actions=report['actions']
if not actions or actions[0][0]!='diagnose-database':raise SystemExit('Conflicting remediation claim; inspect the timeline.')
# Repeating an ambiguous request reuses the SAME parameters and token. Never switch runbooks on the retry.
response=boto3.client('ssm').start_automation_execution(DocumentName='veriqta-diagnose-database',
    ClientToken=a.incident,Parameters={'AutomationAssumeRole':[a.execution_role],'DatabaseIdentifier':[a.database]})
store.execution(a.incident,response['AutomationExecutionId'])
print(response['AutomationExecutionId'])
````

### [scripts/traffic.py](scripts/traffic.py)

````python
import argparse,concurrent.futures,json,time,uuid,urllib.request,math
p=argparse.ArgumentParser();p.add_argument('--url',default='http://127.0.0.1:18080/checkout');p.add_argument('--count',type=int,default=100);p.add_argument('--workers',type=int,default=4);a=p.parse_args()
if not 1<=a.count<=10000 or not 1<=a.workers<=32:raise SystemExit('Use at most 10000 requests and 32 workers.')
def request(_):
    start=time.monotonic();status=599
    try:
        req=urllib.request.Request(a.url,data=b'',headers={'Idempotency-Key':'veriqta-'+str(uuid.uuid4())},method='POST')
        with urllib.request.urlopen(req,timeout=10) as r:status=r.status
    except Exception:pass
    return status,time.monotonic()-start
with concurrent.futures.ThreadPoolExecutor(max_workers=a.workers) as e:r=list(e.map(request,range(a.count)))
lat=sorted(x[1] for x in r)
print(json.dumps({'requests':len(r),'errors':sum(x[0]>=500 for x in r),'p95_seconds':lat[math.ceil(.95*len(lat))-1],'age_seconds':0,'schema_backward_compatible':True},indent=2))
````

### [scripts/validate.py](scripts/validate.py)

````python
"""Run credential-free validation. Terraform mocks replace AWS providers in all .tftest.hcl files."""
import ast,json,os,subprocess,sys
from pathlib import Path
import yaml
ROOT=Path(__file__).resolve().parents[1]
os.chdir(ROOT)
for p in ROOT.rglob('*.py'):
 if not any(x in p.parts for x in ('.venv','.terraform','__pycache__','.private','artifacts')):ast.parse(p.read_text(),filename=str(p))
for p in [*ROOT.rglob('*.yaml'),*ROOT.rglob('*.yml')]:
 if not any(x in p.parts for x in ('.terraform','.private','artifacts')):list(yaml.safe_load_all(p.read_text()))
subprocess.run([sys.executable,'-m','unittest','discover','-s','tests','-v'],check=True)
cache=Path(os.environ.get('TF_PLUGIN_CACHE_DIR',str(Path.home()/'.cache/veriqta/terraform/providers')));cache.mkdir(parents=True,exist_ok=True)
os.environ['TF_PLUGIN_CACHE_DIR']=str(cache)
tf=os.environ.get('TERRAFORM','terraform')
subprocess.run([tf,'fmt','-recursive','-check','infrastructure'],check=True)
for root in sorted({p.parent for p in (ROOT/'infrastructure').rglob('*.tf') if '.terraform' not in p.parts}):
 for args in [['init','-backend=false','-input=false','-no-color'],['validate','-no-color']]:subprocess.run([tf,*args],cwd=root,check=True)
 if (root/'tests').exists():subprocess.run([tf,'test','-no-color'],cwd=root,check=True)
print('Credential-free checks passed. Cloud authorization, deployment and recovery still require the explicit live exercises.')
````

### [scripts/verify_recovery.py](scripts/verify_recovery.py)

````python
import argparse,json,time,os
import psycopg
p=argparse.ArgumentParser();p.add_argument('--marker',required=True);a=p.parse_args()
primary=os.environ['PRIMARY_DATABASE_URL'];recovery=os.environ['RECOVERY_DATABASE_URL']
def snapshot(dsn):
    with psycopg.connect(dsn) as c:
        return {'orders':c.execute('SELECT id,amount_cents FROM orders ORDER BY id').fetchall(),
                'marker':c.execute('SELECT id,created_at FROM orders WHERE id=%s',(a.marker,)).fetchone(),
                'ledger':c.execute('SELECT idempotency_key,amount_cents FROM ledger ORDER BY idempotency_key').fetchall()}
a1,a2=snapshot(primary),snapshot(recovery)
if a1!=a2:raise SystemExit('Data differs: inspect writes after the backup and the measured data-loss window.')
if not a2['marker']:raise SystemExit('Required marker missing.')
print('Exact ordered business records and required marker match. Run a new write/read in the recovered application next.')
````

### [tests/test_api.py](tests/test_api.py)

````python
import unittest
from unittest.mock import patch
from fastapi.testclient import TestClient
from application.api import app
class Api(unittest.TestCase):
 def test_process_health_does_not_depend_on_db(self):self.assertEqual(TestClient(app).get('/healthz').status_code,200)
 def test_readiness_fails_without_database(self):
  with patch('application.api.pool',side_effect=RuntimeError('private connection information')):
   r=TestClient(app).get('/readyz');self.assertEqual(r.status_code,503);self.assertNotIn('private',r.text)
 def test_checkout_requires_idempotency_key(self):self.assertEqual(TestClient(app).post('/checkout').status_code,400)
 def test_metrics_endpoint(self):self.assertEqual(TestClient(app).get('/metrics').status_code,200)
````

### [tests/test_decisions.py](tests/test_decisions.py)

````python
import datetime as dt,json,tempfile,threading,unittest
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from engineering.recovery import decide
from engineering.release import decision
from engineering.finops import assess
from engineering.incident import IncidentStore
from engineering.platform import render
from engineering.governance import validate_exception,drift_direction
ROOT=Path(__file__).resolve().parents[1]
class Decisions(unittest.TestCase):
 def test_dependency_does_not_restart(self):self.assertEqual(decide({}, {'dependency_healthy':False}), 'ESCALATE_DEPENDENCY')
 def test_insufficient_capacity(self):self.assertEqual(decide({}, {'dependency_healthy':True,'ready':1,'minimum_ready':2}), 'RESTORE_CAPACITY')
 def test_cooldown(self):self.assertEqual(decide({'attempts':1,'last_attempt':100},{'dependency_healthy':True,'ready':3,'crash_loop':True},150),'WAIT_COOLDOWN')
 def test_attempt_limit(self):self.assertEqual(decide({'attempts':3},{'dependency_healthy':True,'ready':3}), 'STOP_ATTEMPT_LIMIT')
 def test_bounded_restart(self):self.assertEqual(decide({}, {'dependency_healthy':True,'ready':3,'crash_loop':True},1000),'RESTART_ONE')
 def test_bad_canary(self):self.assertEqual(decision(json.loads((ROOT/'projects/07-progressive-delivery/bad.json').read_text())),'ABORT_TO_STABLE')
 def test_good_canary(self):self.assertEqual(decision(json.loads((ROOT/'projects/07-progressive-delivery/good.json').read_text())),'PROMOTE')
 def test_missing_metrics_pause(self):self.assertEqual(decision({'schema_backward_compatible':True}),'PAUSE_NO_EVIDENCE')
 def test_irreversible_schema(self):self.assertEqual(decision({'schema_backward_compatible':False}),'FORWARD_FIX_REQUIRED')
 def test_finops_keeps_standby(self):
  rows=json.loads((ROOT/'projects/06-finops/recommendations.json').read_text())
  self.assertEqual([assess(r)['decision'] for r in rows],['RECOMMEND_REVIEW','REJECT','REJECT'])
 def test_finops_stale(self):
  r=json.loads((ROOT/'projects/06-finops/recommendations.json').read_text())[0];r['telemetry_age_minutes']=120
  self.assertEqual(assess(r)['decision'],'REJECT')
 def test_approved_platform_idempotency(self):
  req=json.loads((ROOT/'projects/05-self-service/request.json').read_text())
  with tempfile.TemporaryDirectory() as d:self.assertEqual(render(req,d),render(req,d))
 def test_reject_privileged_platform_request(self):
  req=json.loads((ROOT/'projects/05-self-service/request.json').read_text());req['iam_policy']='*'
  with tempfile.TemporaryDirectory() as d:
   with self.assertRaises(ValueError):render(req,d)
 def test_reject_duplicate_different_inputs(self):
  req=json.loads((ROOT/'projects/05-self-service/request.json').read_text())
  with tempfile.TemporaryDirectory() as d:
   render(req,d);req['memory_mib']=512
   with self.assertRaises(ValueError):render(req,d)
 def test_incident_correlates_and_deduplicates(self):
  events=json.loads((ROOT/'projects/10-incident-command/alerts.json').read_text())
  with tempfile.TemporaryDirectory() as d:
   s=IncidentStore(Path(d)/'incidents.db');a=s.ingest(events[0]);self.assertEqual(a,s.ingest(events[0]));self.assertEqual(a,s.ingest(events[1]));self.assertEqual(len(s.report(a)['alerts']),2)
 def test_only_one_remediation_claim(self):
  event=json.loads((ROOT/'projects/10-incident-command/alerts.json').read_text())[0]
  with tempfile.TemporaryDirectory() as d:
   s=IncidentStore(Path(d)/'incidents.db');i=s.ingest(event)
   with ThreadPoolExecutor(max_workers=8) as pool:results=list(pool.map(lambda _:s.claim(i,'diagnose-database','veriqta-operator'),range(8)))
   self.assertEqual(sum(results),1)
 def test_recovery_requires_independent_signals(self):
  with tempfile.TemporaryDirectory() as d:
   with self.assertRaises(ValueError):IncidentStore(Path(d)/'incidents.db').resolve('id',{'checkout':True})
 def test_drift_preserves_security_restriction(self):self.assertEqual(drift_direction('10.0.0.0/16','0.0.0.0/0'),'widening')
 def test_exception_self_approval_rejected(self):
  now=dt.datetime.now(dt.timezone.utc)
  e={'issued_at':now.isoformat(),'expires_at':(now+dt.timedelta(hours=1)).isoformat(),'approver':'same','requester':'same'}
  with self.assertRaises(ValueError):validate_exception(e,{},['same'],now)
 def test_expired_exception_rejected(self):
  now=dt.datetime.now(dt.timezone.utc)
  with self.assertRaises(ValueError):validate_exception({'issued_at':(now-dt.timedelta(hours=2)).isoformat(),'expires_at':(now-dt.timedelta(hours=1)).isoformat()},{},[],now)
````

### [tests/test_postgres.py](tests/test_postgres.py)

````python
import os,unittest
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import psycopg
from application.ledger import write,promote,Fenced,Conflict
DSN=os.getenv('TEST_DATABASE_URL')
@unittest.skipUnless(DSN,'TEST_DATABASE_URL is required for real PostgreSQL integration tests')
class Database(unittest.TestCase):
 def setUp(self):
  with psycopg.connect(DSN) as c:
   c.execute((Path(__file__).resolve().parents[1]/'application/schema.sql').read_text())
   c.execute('TRUNCATE ledger,receipts,outbox,orders')
   c.execute("UPDATE write_authority SET owner='primary',epoch=1,expires_at=clock_timestamp()+interval '1 hour' WHERE id=1")
 def test_replay_is_not_duplicate_payment(self):
  with psycopg.connect(DSN) as c:self.assertTrue(write(c,'primary',1,'test-replay',100))
  with psycopg.connect(DSN) as c:self.assertFalse(write(c,'primary',1,'test-replay',100))
 def test_different_amount_rejected(self):
  with psycopg.connect(DSN) as c:write(c,'primary',1,'test-conflict',100)
  with self.assertRaises(Conflict):
   with psycopg.connect(DSN) as c:write(c,'primary',1,'test-conflict',200)
 def test_old_writer_fenced_after_promotion(self):
  with psycopg.connect(DSN) as c:self.assertEqual(promote(c,'primary',1,'recovery'),2)
  with self.assertRaises(Fenced):
   with psycopg.connect(DSN) as c:write(c,'primary',1,'stale',100)
  with psycopg.connect(DSN) as c:self.assertTrue(write(c,'recovery',2,'new',100))
 def test_expired_lease_fails_closed(self):
  with psycopg.connect(DSN) as c:c.execute("UPDATE write_authority SET expires_at=clock_timestamp()-interval '1 second'")
  with self.assertRaises(Fenced):
   with psycopg.connect(DSN) as c:write(c,'primary',1,'expired',100)
 def test_concurrent_duplicate_is_one_row(self):
  def once(_):
   with psycopg.connect(DSN) as c:return write(c,'primary',1,'concurrent',100)
  with ThreadPoolExecutor(max_workers=6) as e:self.assertEqual(sum(e.map(once,range(6))),1)
  with psycopg.connect(DSN) as c:self.assertEqual(c.execute('SELECT count(*) FROM ledger').fetchone()[0],1)
````

### [workflows/pr-validation.yml](workflows/pr-validation.yml)

````yaml
name: Veriqta untrusted contribution checks
on: [pull_request]
permissions: {contents: read}
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: {python-version: '3.12'}
      - run: pip install -r requirements.txt
      - run: python -m unittest discover -s tests -v
      # No id-token permission, cloud role, registry write token or production environment.
````

### [workflows/release.yml](workflows/release.yml)

````yaml
# Teaching workflow. Install only in a separate approved lab repository.
name: Veriqta signed release
on:
  workflow_dispatch:
permissions: {contents: read}
jobs:
  build:
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    permissions: {contents: read, id-token: write}
    outputs: {digest: '${{ steps.image.outputs.digest }}'}
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.BUILD_ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}
      - uses: aws-actions/amazon-ecr-login@v2
      - uses: docker/setup-buildx-action@v3
      - uses: docker/build-push-action@v6
        id: image
        with:
          context: .
          file: application/Dockerfile
          push: true
          tags: ${{ vars.ECR_REPOSITORY }}:${{ github.sha }}
          sbom: true
          provenance: mode=max
      - uses: anchore/scan-action@v6
        with:
          image: ${{ vars.ECR_REPOSITORY }}@${{ steps.image.outputs.digest }}
          fail-build: true
          severity-cutoff: high
      - uses: sigstore/cosign-installer@v3
      - name: Sign the scanned immutable artifact
        env:
          IMAGE: ${{ vars.ECR_REPOSITORY }}@${{ steps.image.outputs.digest }}
        run: cosign sign --yes "$IMAGE"
  verify:
    needs: build
    runs-on: ubuntu-latest
    permissions: {contents: read, id-token: write}
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.VERIFY_ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}
      - uses: aws-actions/amazon-ecr-login@v2
      - uses: sigstore/cosign-installer@v3
      - name: Verify exact workflow identity
        env:
          IMAGE: ${{ vars.ECR_REPOSITORY }}@${{ needs.build.outputs.digest }}
          IDENTITY: https://github.com/${{ github.repository }}/.github/workflows/release.yml@refs/heads/main
        run: cosign verify --certificate-identity "$IDENTITY" --certificate-oidc-issuer https://token.actions.githubusercontent.com "$IMAGE"
  promotion:
    needs: [build, verify]
    runs-on: ubuntu-latest
    environment: production-promotion
    permissions: {contents: read}
    steps:
      - uses: actions/checkout@v4
        with: {path: source}
      - uses: actions/create-github-app-token@v1
        id: gitops-token
        with:
          app-id: ${{ vars.GITOPS_APP_ID }}
          private-key: ${{ secrets.GITOPS_PRIVATE_KEY }}
          owner: ${{ vars.GITOPS_OWNER }}
          repositories: ${{ vars.GITOPS_REPOSITORY_NAME }}
      - uses: actions/checkout@v4
        with:
          repository: ${{ vars.GITOPS_OWNER }}/${{ vars.GITOPS_REPOSITORY_NAME }}
          ref: main
          path: gitops
          token: ${{ steps.gitops-token.outputs.token }}
          persist-credentials: false
      - uses: actions/setup-python@v5
        with: {python-version: '3.12'}
      - run: pip install PyYAML==6.0.2
      - name: Change only the approved checkout image and release label
        env:
          IMAGE: ${{ vars.ECR_REPOSITORY }}@${{ needs.build.outputs.digest }}
        run: python source/scripts/promote_gitops.py gitops/kubernetes/checkout-deployment.yaml "$IMAGE" "$GITHUB_SHA"
      - uses: peter-evans/create-pull-request@v7
        with:
          path: gitops
          token: ${{ steps.gitops-token.outputs.token }}
          base: main
          branch: veriqta/promote-${{ github.sha }}
          add-paths: kubernetes/checkout-deployment.yaml
          commit-message: Promote verified Veriqta checkout artifact
          title: Promote verified Veriqta checkout artifact
          body: Immutable artifact passed the trusted build and independent signature verification; deployment follows protected GitOps review.
````

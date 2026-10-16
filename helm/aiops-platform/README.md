# aiops-platform

Consolidated Helm chart for the ITGix AIOps (SRE) platform. It deploys the AIOps
agent, its supporting secrets, the Alertmanager receiver, and the MCP servers
that expose observability data to the platform.

## What this chart deploys

| Component | Resources | Toggle |
|---|---|---|
| AIOps agent | `itgix-client-go` subchart (Helm dependency) | always |
| Agent websocket config | `ExternalSecret` → `agent-websocket-security` | always |
| GitLab image pull secret | `ExternalSecret` → `gitlab-secret` | always |
| Vector credentials | `ExternalSecret` → `aiops-vector-secret` | always |
| Alertmanager receiver | `AlertmanagerConfig` `aiops-vector-basic-auth` | always |
| Loki MCP | Deployment, Service | `lokiMcp.enabled` |
| Prometheus MCP | Deployment, Service | `prometheusMcp.enabled` |
| Kubernetes MCP | Deployment, Service, SA, ClusterRole(Binding), ConfigMap | `kubernetesMcp.enabled` |
| Grafana MCP | Deployment, Service, `ExternalSecret` | `grafanaMcp.enabled` |
| MCP ingresses | one `Ingress` per enabled backend | `backends.<name>.enabled` |

All MCP ingresses share the `mcp-servers` ALB group, so they are served by a
single load balancer. For which namespace to deploy into, see
[Namespace](#namespace).

## Namespace

The chart itself is namespace-agnostic. Every template uses
`{{ .Release.Namespace }}`, which under ArgoCD comes from
`spec.destination.namespace` in `application-aiops-platform.yaml`. Nothing in
the chart hardcodes a namespace.

`monitoring` is the usual choice because that is where `kube-prometheus-stack`
installs, and several components have to be co-located with the things they talk
to. Clients whose observability stack lives elsewhere should set the
Application's `destination.namespace` accordingly — but mind the constraints
below.

### What must live where

| Resource | Constraint |
|---|---|
| `AlertmanagerConfig` | Must be in a namespace matched by Alertmanager's `alertmanagerConfigNamespaceSelector`. By default that is **Alertmanager's own namespace**. |
| MCP ingresses | An `Ingress` can only target a `Service` in its **own namespace**. |
| `backends.tempo` ingress | Points at a Tempo-owned Service, so it only works if this chart is deployed into **Tempo's namespace**. |
| Agent pod + its secrets | `agent-websocket-security` and `gitlab-secret` are mounted by the agent, so they must share **the agent's namespace** — the chart handles this, since all three come from the same release. |
| Grafana MCP token secret | Same namespace as the Grafana MCP Deployment — also handled within the release. |
| `ClusterRole` / `ClusterRoleBinding` | Cluster-scoped. The `ServiceAccount` subject namespace is templated, so no change needed. |
| MCP server → backend URLs | Not a namespace constraint. `lokiUrl`, `prometheusUrl`, and `grafanaUrl` are explicit FQDNs and can cross namespaces freely. |

The `AlertmanagerConfig` one is the quiet failure: if it lands in a namespace
Alertmanager's selector does not match, the Prometheus Operator ignores it
silently. No error, no event — alerts simply never reach the AIOps platform.
Verify the selector before deploying:

```bash
kubectl get alertmanager -A \
  -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,\
SELECTOR:.spec.alertmanagerConfigNamespaceSelector
```

An empty selector (`{}`) matches all namespaces. A `null` selector restricts to
Alertmanager's own namespace.

### If the client's stack is split across namespaces

If Alertmanager and Tempo are in different namespaces, a single release cannot
satisfy both. Options, in order of preference:

1. Widen `alertmanagerConfigNamespaceSelector` on the Alertmanager resource, and
   deploy this chart into Tempo's namespace.
2. Leave `backends.tempo.enabled: false` and keep the Tempo MCP ingress in the
   `tempo-distributed` chart, where it ships by default.
3. Run two releases of this chart with different components enabled. Workable
   but the agent would be duplicated, so avoid unless necessary.

### Changing the namespace

`destination.namespace` in `application-aiops-platform.yaml` is a literal by
default. To make it configurable per environment:

```yaml
  destination:
    namespace: {{ default "monitoring" (index .Values "infra-services" "aiops_platform_namespace") }}
```

Then set `aiops_platform_namespace` in that environment's `infra-facts.yaml`.
Note the Application uses `CreateNamespace=false`, so the namespace must already
exist or the sync fails.

## How it is deployed

The chart is not installed with `helm install`. It is deployed by ArgoCD through
the `infra-services` app-of-apps pattern:

1. `infra-services/templates/application-aiops-platform.yaml` defines an ArgoCD
   `Application` pointing at `helm/aiops-platform` in this repo.
2. It is gated by `app_enabled_aiops-platform` in
   `infra-services/values/<env>/<region>/infra-facts.yaml`.
3. Values are layered: `aiops-platform/values.yaml` (defaults, all components
   disabled) then `aiops-platform/values/<env>/<region>/values.yaml`
   (per-environment hosts, URLs, images, and secret keys).

To enable it for an environment, set the flag in that environment's
`infra-facts.yaml`:

```yaml
infra-services:
  app_enabled_aiops-platform: true
```

### Helm dependency

The agent comes from a private GitLab Helm registry, declared in `Chart.yaml`:

```yaml
dependencies:
- name: itgix-client-go
  version: 0.3.0
  repository: https://gitlab.itgix.com/api/v4/projects/683/packages/helm/stable
```

ArgoCD runs `helm dependency build` during manifest generation, so it needs
credentials for that registry registered as an ArgoCD repository. See
[ArgoCD repository credential](#argocd-repository-credential) below — without it
the Application fails to render with a 401.

For local rendering:

```bash
helm repo add itgix-stable \
  https://gitlab.itgix.com/api/v4/projects/683/packages/helm/stable \
  --username read-package-registry --password-stdin
helm dependency update helm/aiops-platform

helm template aiops-platform helm/aiops-platform \
  -f helm/aiops-platform/values.yaml \
  -f helm/aiops-platform/values/<env>/<region>/values.yaml \
  --namespace <namespace>
```

## Prerequisites

- External Secrets Operator running, with a `ClusterSecretStore` named
  `secretstore-aws` (override via `externalSecrets.secretStoreName`).
- AWS Load Balancer Controller, for the MCP ingresses.
- `kube-prometheus-stack`, for the `AlertmanagerConfig` CRD and as the
  Prometheus/Grafana/Alertmanager source.
- The target namespace must already exist — the Application sets
  `CreateNamespace=false`. See [Namespace](#namespace).
- Secrets created in AWS Secrets Manager for the target environment (below).

## ArgoCD repository credential

This one is **not** part of this chart, and it must exist before the chart can
be rendered. It lives in the `argo-cd` chart so that it is created in an earlier
sync wave — putting it in this chart would deadlock, since the credential is
needed to pull this chart's own dependency.

Add it to `helm/argo-cd/values/<env>/<region>/values.yaml` under `extraObjects`:

```yaml
extraObjects:
  - apiVersion: external-secrets.io/v1beta1
    kind: ExternalSecret
    metadata:
      name: <env>-aiops-agent-gitlab-repo
      namespace: "{{ .Release.Namespace }}"
      labels:
        app.kubernetes.io/part-of: argocd
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: secretstore-aws
        kind: ClusterSecretStore
      target:
        name: <env>-aiops-agent-gitlab-repo
        creationPolicy: Owner
        template:
          metadata:
            labels:
              # Required — without this label ArgoCD ignores the Secret
              # and cannot authenticate to the Helm registry.
              argocd.argoproj.io/secret-type: repository
              app.kubernetes.io/part-of: argocd
      dataFrom:
        - extract:
            key: <env>-aiops-agent-gitlab-repo
            metadataPolicy: None
            conversionStrategy: Default
            decodingStrategy: None
```

The `argocd.argoproj.io/secret-type: repository` label must be set via
`target.template.metadata.labels`. Labels on the `ExternalSecret` itself are not
copied to the generated `Secret`.

### Secret contents

`<env>-aiops-agent-gitlab-repo`, key/value in AWS Secrets Manager:

| Key | Value |
|---|---|
| `type` | `helm` |
| `name` | a name for the repo entry, e.g. `itgixclient` |
| `url` | `https://gitlab.itgix.com/api/v4/projects/683/packages/helm/stable` |
| `username` | `read-package-registry` |
| `password` | GitLab deploy token (`gldt-...`) |

> **Note on `project`:** if the secret includes a `project` key, it scopes the
> credential to that ArgoCD AppProject. The `aiops-platform` Application runs
> under project `infra`, so either omit `project` (global credential) or set it
> to `infra`. A mismatch means ArgoCD refuses to use the credential.

## AWS Secrets Manager secrets

Four secrets, three required. Names are arbitrary — the chart reads them from
values, so there is no naming convention to follow. Set each one under
`externalSecrets.*.remoteKey` in the environment's values file.

Create them in the **same AWS account and region as the target cluster**. Run
`aws sts get-caller-identity` first to confirm you are in the right account.

### 1. Websocket config (required)

The agent's own runtime configuration. **Request this from the ITGix platform
administrators — one per environment you are deploying to.** It is an opaque
blob generated on their side; do not construct it yourself.

Store it as a **plaintext** secret (not key/value). The whole secret value
becomes the `config.yaml` key in the Kubernetes Secret.

```bash
aws secretsmanager create-secret \
  --name <env>-aiops-agent-websocket-config \
  --description "AIOps agent websocket config for <env>" \
  --secret-string file:///tmp/websocket-config.yaml \
  --tags Key=Application,Value=aiops Key=Environment,Value=<env> Key=Project,Value=<project> Key=CostCenter,Value=n/a \
  --region <region>
```

Then, add it in the per-environment values files like this:

```yaml
externalSecrets:
  websocketConfig:
    remoteKey: <env>-aiops-agent-websocket-config
```

Consumed as: `Secret/agent-websocket-security`, key `config.yaml`, mounted by
the agent at startup.

### 2. GitLab registry token (required)

Docker credentials for pulling the agent image from the GitLab **container**
registry on port 5050. This is a different credential from the Helm repo one
above — container registry vs package registry.

Key/value secret with a single `.dockerconfigjson`-shaped entry:

```json
{
  "auths": {
    "gitlab.itgix.com:5050": {
      "username": "read-registry-token",
      "password": "gldt-...",
      "email": "<email>",
      "auth": "<base64 of username:password>"
    }
  }
}
```

The remote key must be `dockerconfigjson`. The chart renders it into a
`kubernetes.io/dockerconfigjson` Secret named `gitlab-secret`.

This token is typically shared across environments, so the same value can be
reused — but it still has to exist in each account's Secrets Manager.

```yaml
externalSecrets:
  gitlabToken:
    remoteKey: aiops-gitlab-secret
```

### 3. Vector credentials (required)

Basic-auth credentials used by the `AlertmanagerConfig` receiver to POST alerts
to `vector.itgix.com`. Obtain from the ITGix platform administrators.

Key/value secret with exactly these two keys:

| Key | Value |
|---|---|
| `client-id` | basic-auth username |
| `client-secret` | basic-auth password |

```bash
cat > /tmp/vector-secret.json <<'JSON'
{
  "client-id": "REPLACE_ME",
  "client-secret": "REPLACE_ME"
}
JSON

aws secretsmanager create-secret \
  --name <env>-aiops-vector-secret \
  --description "AIOps vector basic-auth credentials for <env>" \
  --secret-string file:///tmp/vector-secret.json \
  --tags Key=Application,Value=aiops Key=Environment,Value=<env> Key=Project,Value=<project> Key=CostCenter,Value=n/a \
  --region <region>
```

Then, add it in the per-environment values files like this:

```yaml
externalSecrets:
  vectorSecret:
    remoteKey: <env>-aiops-vector-secret
```

The key names matter: the `AlertmanagerConfig` references `client-id` and
`client-secret` directly.

### 4. Grafana MCP service account token (optional)

**Only needed if you enable the Grafana MCP server.** Skip this section
entirely if `grafanaMcp.enabled` stays `false`.

Create a service account in Grafana with Viewer (or higher, if you want the MCP
server to write), generate a token, then store it as a key/value secret with a
single key:

| Key | Value |
|---|---|
| `token` | Grafana service account token (`glsa_...`) |

```bash
cat > /tmp/grafana-mcp-token.json <<'JSON'
{
  "token": "REPLACE_ME"
}
JSON

aws secretsmanager create-secret \
  --name <env>-grafana-mcp-service-account-token \
  --description "Grafana MCP service account token for <env>" \
  --secret-string file:///tmp/grafana-mcp-token.json \
  --tags Key=Application,Value=aiops Key=Environment,Value=<env> Key=Project,Value=<project> Key=CostCenter,Value=n/a \
  --region <region>
```

Then, add it in the per-environment values files like this:

```yaml
externalSecrets:
  grafanaServiceAccountToken:
    remoteKey: <env>-grafana-mcp-service-account-token
    # Points at the `token` key inside the JSON. Leave empty only if the
    # secret value is the raw token rather than key/value.
    remoteProperty: token

grafanaMcp:
  enabled: true
  grafanaUrl: "http://kube-prometheus-stack-grafana.monitoring.svc:80"
  serviceAccountToken:
    secretName: grafana-mcp-service-account-token
    secretKey: token

backends:
  grafana:
    enabled: true
    host: grafana-mcp-<env>.<domain>
```

The token must be issued by the same Grafana instance that `grafanaUrl` points
at.

# Description

This is a template repository for the ITGix ADP (Application development platform) for ArgoCD gitops repo that is tailored towards AI workloads. 

- Sample RAG apps

- Vector databases

- Batch and scheduling systems that run on Kubernetes that allow complex bat


# AI profile services

Toggled from `helm/infra-services/values.yaml` (or, per environment, from the customer's
environment YAML which the installer forwards into `infra-facts.yaml`):

| Service | Chart | Toggle flag(s) |
|---|---|---|
| qdrant-vectordb | `helm/qdrant-vectordb` | `qdrant_vectordb` |
| rag-demo | `helm/rag-demo` | `ragdemo_enabled` |
| adp-devops-agent | `helm/adp-devops-agent` | `adp_devops_agent_enabled` |
| kubernetes-mcp-server | `helm/kubernetes-mcp-server` | `kubernetes_mcp_server_enabled`, `kubernetes_mcp_server_write_enabled` |

See each chart's own README for what it does and how to configure it.

## adp-devops-agent Bedrock model settings

The agent calls Bedrock through the Converse API. The `awsSettings` map in `helm/adp-devops-agent/values.yaml` holds the settings (`BEDROCK_MODEL_ID`, `BEDROCK_REGION`, `BEDROCK_EFFORT`, `BEDROCK_MAX_TOKENS`, `BEDROCK_TEMPERATURE`, `BEDROCK_READ_TIMEOUT_SECONDS`); empty optional values are not rendered.

The default model is Claude Opus 5.5 (`eu.anthropic.claude-opus-5-5`), the EU geo inference profile, which keeps requests inside EU regions. It only works when the Bedrock call region (`BEDROCK_REGION`, default `AWS_REGION`) is an EU region; for an environment outside the EU use `us.anthropic.claude-opus-5-5` (US regions) or `global.anthropic.claude-opus-5-5` (any region, no data residency). Override `awsSettings.BEDROCK_MODEL_ID` per environment in `helm/adp-devops-agent/values/<env>/<region>/values.yaml`. Alternatives:

- `global.anthropic.claude-opus-5-5`: Claude Opus 5.5, any region, no data residency.
- `global.anthropic.claude-sonnet-5-5`: Claude Sonnet 5.5, cheaper.
- `eu.anthropic.claude-opus-4-6-v1`: Claude Opus 4.6, EU profile, the previous default.
- `global.anthropic.claude-fable-5-1`: Claude Fable 5.1, an explicit per-environment choice; requires the data-retention mode below.

Fable models require the AWS account's Bedrock data-retention mode `aws_review` in the region the agent calls (`BEDROCK_REGION`, default `AWS_REGION`). With `aws_review`, prompts and completions of models that require it (Fable 5/5.1) are retained inside AWS for up to 30 days and may be reviewed by AWS; they are not shared with Anthropic. Models that allow zero retention are unaffected. Without it the call fails with `ValidationException: ... data retention mode 'default' is not available for this model`. The installer does not change this setting. See the [AWS documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/data-retention.html) and board issue #365.

```bash
eval "$(aws configure export-credentials --profile <profile> --format env)"
# check (expect "mode": "aws_review" or "provider_data_share")
curl -s --aws-sigv4 "aws:amz:<region>:bedrock" --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
  -H "x-amz-security-token: $AWS_SESSION_TOKEN" https://bedrock.<region>.amazonaws.com/data-retention
# opt in (account-wide in that region; needs bedrock:PutAccountDataRetention)
curl -s -X PUT --aws-sigv4 "aws:amz:<region>:bedrock" --user "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY" \
  -H "x-amz-security-token: $AWS_SESSION_TOKEN" -H "Content-Type: application/json" \
  -d '{"mode":"aws_review"}' https://bedrock.<region>.amazonaws.com/data-retention
```


# ArgoCD Installation
1. Install ArgoCD via HELM:

```
 cd helm/argo-cd
 helm upgrade --install argocd .  -n argocd -f values.yaml --create-namespace
```
2. Output initial Admin password. It is auto-generated and we need it to access the UI or via argo-cli

```
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
```

3. Register the initial GitLab repository using Kubernetes Manifest

```
cd manifests/argocd
kubectl apply -f gitlab-repo.yaml -n argocd
```

This will register the repository in ArgoCD. The username and password ( in this case GitLab Access token) need to be provided in the manifest. They are then stored in Kubernetes Secret.

4. Create initial Application that is actually ArgoCD itself

```
kubectl apply -f argocd-application.yaml
```
4.1. Deploy the `my-app` application that is used to monitor a specific path/source for changes and auto-create applicaitons or other resources from there.

This will create an Application that is actually ArgoCD, which we initially installed. The repository and values are configured in the manifest and can be further edited.

5. Auto addition of applications.
Creating CRD of kind Application inside `manifests/applications` will automatically be picked up by argocd and created.
To enable this we need to deploy the app of apps:
This is for applications that will be the same across all stages and regions
```
kubectl apply -f app-of-app.yaml
```

Then install application services for the specific stage and region:
```
kubectl apply -n argocd -f ./manifests/applications/infra-app-stages/stage/eu-west-1/infra-services.yaml
```

P.S. 

There is also a generic application.yaml that has all options for creating other applications. Can be used for reference.


# Kyverno policy engine (optional)

Three optional `infra-services` Applications are shipped, all disabled by default. Set the keys in the environment YAML (they reach `infra-facts.yaml`):

| Key | Default | Effect |
|---|---|---|
| `enable_kyverno` | `false` | Deploys Kyverno (`helm/kyverno`, chart 3.5.2) into the `kyverno` namespace. |
| `enable_default_policies` | `false` | Deploys the best-practices policies (`helm/kyverno-policies`, chart 0.2.0), `validationFailureAction: Audit`. Requires `enable_kyverno`. |
| `enable_policy_reporter` | `false` | Deploys Policy Reporter with its UI (`helm/policy-reporter`, chart 2.24.1) behind an ALB ingress. |
| `policy_reporter_ingress_annotations` | `{}` | Extra ingress annotations for Policy Reporter, merged over the built-in ALB annotations (this template is AWS only). |
| `policy_reporter_ingress_host` | `policies-<project>-<environment>-<region>.<dns_main_domain>` | Optional host override for the Policy Reporter ingress. |
| `kyverno_branch`, `default_policies_branch`, `policy_reporter_branch` | `HEAD` | Optional git revision of the destination GitOps repo each Application tracks. |

Per-environment overrides go in `helm/<kyverno|kyverno-policies|policy-reporter>/values/<environment>/<region>/values.yaml`.

# adp-devops-agent validation settings

The `helm/adp-devops-agent` chart renders these maps into the agent ConfigMap (UPPER_SNAKE keys, string values). Override them in `helm/adp-devops-agent/values/<environment>/<region>/values.yaml`.

The comma-separated `ENABLED_VALIDATORS` form needs an agent image with #328 MR 1 (adp-devops-agent!6); v1.2.1 and earlier fail at startup parsing it.

```yaml
validationSettings:
  ENABLED_VALIDATORS: "yamllint,k8s-schema"   # comma-separated validator names; new names arrive with later agent releases
  MAX_CORRECTION_ROUNDS: "2"                  # read by the agent once the correction loop ships
```

The `infra-services` Application also sets `infraContext` from infra-facts. Empty values are omitted from the ConfigMap:

| Env name | Source |
|---|---|
| `INFRA_GITOPS_REPO_URL` | `gitops_destination_repo` |
| `INFRA_GITOPS_REVISION` | `default_policies_branch`, default `HEAD` |
| `POLICY_ENVIRONMENT` | `environment` |
| `POLICY_REGION` | `region` |

The agent's GitOps repository (`GITOPS_REPO_URL`) and GitLab URL (`GITLAB_URL`, the `<scheme>://<host>` of that repository) come from `applications_destination_repo` in infra-facts, set by the `infra-services` Application. When the key is unset neither variable is rendered, and the agent (v1.2.1 and later) refuses to start because `GITOPS_REPO_URL` is required.

# kubernetes-mcp-server

Two cluster-internal instances of Red Hat's [Kubernetes MCP server](https://github.com/containers/kubernetes-mcp-server)
(chart `oci://ghcr.io/containers/charts/kubernetes-mcp-server` 0.1.0, image
`quay.io/containers/kubernetes_mcp_server:v0.0.66`), giving AI agents on the AI profile a
Model Context Protocol interface to the cluster. Both instances are `ClusterIP`-only: no
ingress, no OAuth, no in-cluster secret store — they are reached over HTTP inside the mesh.

## Instances

| Release / Service | Endpoint | RBAC | Server mode | Consumer |
|---|---|---|---|---|
| `kubernetes-mcp-server` | `http://kubernetes-mcp-server.kubernetes-mcp-server.svc.cluster.local:8080/mcp` | ClusterRole `view` | `read_only = true` | devops-agent diagnosis, AIOps troubleshooting |
| `kubernetes-mcp-server-write` | `http://kubernetes-mcp-server-write.kubernetes-mcp-server.svc.cluster.local:8080/mcp` | ClusterRole `view` **plus** a custom ClusterRole granting only `delete` on `pods` | `enabled_tools` allowlist (read tools + `pods_delete`) | AIOps remediation: restart only |

Both instances run in the `kubernetes-mcp-server` namespace and use their own ServiceAccount
token in-cluster (`cluster_provider_strategy = in-cluster`, `cluster_auth_mode = kubeconfig`,
`serviceAccount.automountToken: true`) — there is no OAuth passthrough and no per-user identity.

## Design boundary: restart-only, by ruling

> "AIOps should only be able to do things like restart of deployment, not changing state. The
> rest is done via the devops agent that makes MRs."

Kubernetes MCP server 0.1.0 / v0.0.66 has no dedicated rollout-restart tool in the `core`
toolset (checked against the `v0.0.66` tag: `pkg/toolsets/core/pods.go`). The only way to force a
managed workload (Deployment/ReplicaSet/StatefulSet) to recreate a Pod without changing its
spec is to delete the Pod and let the controller replace it. So:

- **Restart mechanism = `pods_delete`.** The write instance's RBAC grants `delete` on `pods` and
  nothing else mutating: no `patch`/`update`/`create` on any resource, no `scale`, no access to
  Secrets, RBAC objects or Nodes (the built-in `view` ClusterRole already excludes all three, so
  the write instance adds nothing on top of it).
- Any durable change (image bump, replica count, config, new manifests) goes through the
  devops-agent as a GitOps merge request, never through this server.

### Tool allowlists

Read-only instance (`kubernetes-mcp-server`): `read_only = true` — the server exposes only tools
annotated `readOnlyHint=true` from the `config` and `core` toolsets (`configuration_contexts_list`,
`targets_list`, `configuration_view`, `events_list`, `namespaces_list`, `projects_list`,
`nodes_log`, `nodes_stats_summary`, `nodes_top`, `pods_list`, `pods_list_in_namespace`,
`pods_get`, `pods_top`, `pods_log`, `resources_list`, `resources_get`). `denied_resources` also
blocks `v1/Secret` at the application layer, on top of the `view` ClusterRole already denying it
at the API layer.

Write instance (`kubernetes-mcp-server-write`): `read_only` is **not** set (it would also block
`pods_delete`, since that tool is `destructiveHint=true`, not `readOnlyHint=true`). Instead
`enabled_tools` is an explicit allowlist: every read tool listed above, plus `pods_delete`. It
does **not** include `resources_create_or_update`, `resources_delete`, `resources_scale`,
`pods_run`, `pods_exec`, or any `helm_*` tool (the `helm` toolset is not enabled on either
instance). `denied_resources` blocks `v1/Secret` here too, in addition to RBAC.

## Turning the write tier on

The write instance is **disabled by default**. A customer enables it with one scalar in their
environment YAML:

```yaml
kubernetes_mcp_server_write_enabled: true
```

The installer forwards every scalar config key into `infra-facts.yaml`, which becomes this
chart's (and the whole `infra-services` app-of-apps') values, so this flag reaches
`helm/infra-services/templates/application-kubernetes-mcp-server.yaml`, which passes it through
as `write.enabled` to this chart.

`kubernetes_mcp_server_enabled` (default `true`) gates the read-only instance and the ArgoCD
`Application` itself; setting it `false` removes both instances.

## NetworkPolicy (optional)

`networkPolicy.enabled` (default `false`) renders a `NetworkPolicy` per enabled instance,
admitting ingress on port 8080 only from the namespaces listed in
`networkPolicy.allowedNamespaces` (default `[adp-devops-agent]`). The Services are `ClusterIP`
regardless of this setting; the NetworkPolicy only narrows which in-cluster namespaces may reach
them, and its enforcement depends on the cluster's CNI supporting `NetworkPolicy` objects.

## Chart shape

`Chart.yaml` declares **two aliased dependencies** on the same upstream OCI chart
(`oci://ghcr.io/containers/charts` / `kubernetes-mcp-server` 0.1.0), aliased `readonly` and
`write`, gated by `readonly.enabled` / `write.enabled`. Verified with `helm dependency build` and
`helm template`: both aliases resolve to a single shared `charts/kubernetes-mcp-server-0.1.0.tgz`
and render as two independent Deployments/Services/ConfigMaps/ServiceAccounts. Each alias also
sets both `nameOverride` and `fullnameOverride` (not just `fullnameOverride`) — the upstream
chart's `app.kubernetes.io/name` label comes from `nameOverride`, and without overriding it too,
both instances would compute the identical Pod/Service selector labels (same chart name, same
shared `Release.Name`) and each Service would select both Deployments' Pods.

RBAC and server config are wired entirely through values the upstream chart already exposes,
with no bespoke RBAC/config templates in this wrapper: `rbac.extraClusterRoleBindings` (binds the
built-in `view` ClusterRole via `roleRef.external: true`) and `rbac.extraClusterRoles` +
`rbac.extraClusterRoleBindings` (the write instance's custom `pods-delete` ClusterRole), and
`config.*` (rendered into `config.toml` by the upstream chart's own `configmap.yaml`). Only the
`NetworkPolicy` template is bespoke to this wrapper chart, since the upstream chart has no
NetworkPolicy support.

## Upgrade note

The image tag (`v0.0.66`) and chart version (`0.1.0`) are pinned deliberately in
`values.yaml`/`Chart.yaml`. Bump them together and deliberately — re-check the tool list and
`denied_resources`/`enabled_tools` semantics against the new tag's `pkg/config/config.go` and
`pkg/toolsets/core/*.go` before rolling forward, in case a future release adds a dedicated
restart/rollout tool that should replace the `pods_delete` mechanism, or changes what `read_only`
covers.

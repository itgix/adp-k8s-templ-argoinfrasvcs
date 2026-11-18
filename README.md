# Description

This is a template repository for the ITGix ADP (Application development platform) for ArgoCD gitops repo that is tailored towards AI workloads. 

- Sample RAG apps

- Vector databases

- Batch and scheduling systems that run on Kubernetes that allow complex bat


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

# Optional infra services

## Shared GCP Gateway and Wildcard TLS

With matching Terraform and installer support, enable
`gcp_shared_gateway_enabled: true` in the GCP environment config. The default is
false. AWS and Azure ignore this setting and retain their existing rendering.

Terraform must supply these fields through `infra-services` in `infra-facts.yaml`:

```yaml
infra-services:
  cloud: gcp
  gcp_shared_gateway_enabled: true
  dns_main_domain: adp8d13.itgix.eu
  gcp_gateway_address_name: adp8d13-test-ew1-gateway
  gcp_gateway_certificate_map: adp8d13-test-ew1-gateway
```

The chart creates one `argocd/adp-shared` Gateway of class
`gke-l7-global-external-managed`, using the reserved address and Certificate
Manager map, and redirects HTTP to HTTPS. It creates HTTPS HTTPRoutes and explicit
HealthCheckPolicies for ArgoCD, plus enabled Backstage, Policy Reporter UI,
Grafana, Prometheus and Alertmanager. Prometheus and Alertmanager remain private
unless `prometheus_ingress_host` / `alertmanager_ingress_host` is explicitly set;
protect those endpoints with authentication/access controls before opting in.
Child chart ingresses are disabled and their
backends remain ClusterIP Services. Per-service GKE ManagedCertificates and
FrontendConfigs are not rendered in shared mode. Legacy GCP ingress mode is
unchanged when the setting is false.

The installer must also disable ArgoCD ingress and gRPC ingress, configure
`configs.params.server.insecure: true` (TLS terminates at the Gateway), and retain
the generated values in its self-management Application. ArgoCD CLI connections
through the HTTP route should use `--grpc-web`. No certificate/private key is
copied into Kubernetes namespaces; Certificate Manager renews the wildcard.

The public Cloud DNS zone must be delegated. Terraform owns the wildcard A record
and certificate-authorization CNAME, so external-dns is not needed for these
hostnames. Explicit DNS records from old ingresses override wildcard DNS: remove
or update those records before switching traffic.
Use a dedicated domain/subdomain per Gateway so multiple environments do not
compete for the same Terraform-owned wildcard A record.
Existing hostname overrides are accepted only for direct subdomains covered by
`*.dns_main_domain`; duplicate
hostnames and missing Terraform address/map outputs fail rendering.

Routes use standard release/service names (`argocd-server`, `backstage`,
`policy-reporter-ui`, `kube-prometheus-stack-grafana`,
`kube-prometheus-stack-prometheus`, `kube-prometheus-stack-alertmanager`). Custom
fullname/port overrides require matching `gcp_gateway_backends` settings. Keep
the Backstage image's readiness endpoint compatible with
`/.backstage/health/v1/readiness`. Service Applications are submitted before the
networking sync wave. Namespaces receive `Prune=false` to avoid deleting workloads
when service toggles change.

For additional apps, label the namespace `adp.itgix.com/shared-gateway: "true"`
and create an HTTPRoute with `parentRefs` pointing to Gateway `adp-shared`,
namespace `argocd`, `sectionName: https`. Reference the app's ClusterIP Service
in that same namespace. Give it a direct-subdomain hostname and an appropriate
GKE HealthCheckPolicy; do not create another GCE ingress or LoadBalancer Service.

This is a load-balancer replacement for existing deployments. Review Terraform
first, wait for certificate provisioning, remove old GCE ingresses, and then sync
the Gateway routes. GKE does not allow a Service to be used simultaneously by its
Ingress and Gateway controllers. Traffic may be interrupted during migration.

### Optional Per-Service Gateway Overrides

Only enabled services receive routes and health checks. No backend settings are
required for disabled services. In the installer YAML (or under `infra-services`
when using this chart directly), configure only what an enabled service needs:

```yaml
gcp_gateway_backends:
  grafana:
    service_name: custom-grafana
```

Omit the map entirely if enabled services use their standard chart settings.
This example changes only Grafana's backend reference; it does not enable Grafana
or any other service. ArgoCD remains the core route. `enable_prometheus_stack`
deploys the monitoring stack and exposes Grafana; Prometheus and Alertmanager
stay private unless their explicit ingress host settings are supplied. Routing
settings do not disable the monitoring stack's internal workloads.

Shared settings `gcp_gateway_name`, `gcp_gateway_namespace`, and
`gcp_gateway_class_name` are optional as well.
The Gateway, redirect route, allowed namespaces and all route parentRefs follow
the configured name/namespace. Partial backend overrides merge by application
key; omitted fields retain these defaults:

| Backend key | Namespace | Service | Service port | Health port | Health path |
|---|---|---|---|---|---|
| `argocd` | `argocd` | `argocd-server` | 80 | 8080 | `/healthz` |
| `backstage` | `backstage` | `backstage` | 7007 | 7007 | `/.backstage/health/v1/readiness` |
| `policy_reporter` | `kyverno` | `policy-reporter-ui` | 8080 | 8080 | `/` |
| `grafana` | `monitoring` | `kube-prometheus-stack-grafana` | 80 | 3000 | `/api/health` |
| `prometheus` | `monitoring` | `kube-prometheus-stack-prometheus` | 9090 | 9090 | `/-/healthy` |
| `alertmanager` | `monitoring` | `kube-prometheus-stack-alertmanager` | 9093 | 9093 | `/-/healthy` |

Backend fields are `namespace`, `service_name`, `service_port`,
`health_check_port`, and `health_check_path`. The Service and HealthCheckPolicy
references and their namespace change together. Overrides do not enable disabled
services, expose Prometheus/Alertmanager without their explicit hostname settings,
rename/move Helm releases, or change application listening ports. Align the
existing per-chart Helm overrides separately, or target another already-deployed
Service. ArgoCD itself still installs in `argocd`; the Gateway namespace is
independent. When adding custom routes, reference the configured Gateway rather
than the default `argocd/adp-shared`.

The installer must whitelist `gcp_gateway_backends` when emitting infra-facts.
Unknown keys, malformed names, non-integer/out-of-range ports and health paths
without a leading slash fail early in the installer and also during Helm rendering.
Class names must support a global NamedAddress, Certificate Manager map, HTTP
redirects, GKE HealthCheckPolicies and Service backends. Other built-in GKE
regional/classic/multi-cluster classes are rejected because this setup does not
provide their infrastructure or backend kinds. Custom classes must already exist
and implement the required capabilities; selecting a class does not install its
controller. HTTP/HTTPS listener ports remain 80/443. The HTTP redirect deliberately
omits the unsupported explicit redirect-port field.

The separate installer setting `gcp_gateway_dns_ttl` configures Terraform's
wildcard A and authorization CNAME TTL (default 300 seconds), not this chart.
Overrides are GCP shared-mode only; AWS, Azure, and legacy GCP rendering are unchanged.

## Kafka operator (Strimzi)

Set `enable_kafka_operator: true` in the environment config to deploy the Strimzi cluster
operator (`helm/kafka-operator`, a wrapper around the upstream `strimzi-kafka-operator` chart)
into the `strimzi-system` namespace. It installs the operator only, watching all namespaces
(`watchAnyNamespace: true`), so Kafka clusters are meant to be created by application repos in
their own namespace, not by this chart. A sample `Kafka` cluster manifest ships in a follow-up
PR. `kafka_operator_branch` overrides the targetRevision of the `helm/kafka-operator` path the
same way the other `<app>_branch` keys do.

## DevLake (deprecated here)

DevLake is no longer part of this template as of the next tag. It is installed as an optional
platform tool from the Backstage software catalog (`itgix/adp-backstage-scaffold`, template
"Apache DevLake") into the environment's applications GitOps repo. `enable_devlake`,
`devlake_ingress_annotations`, `devlake_ingress_host` and `devlake_branch` are no longer read.
Existing `helm/devlake/` and `application-devlake.yaml` files in a destination repo are not
removed by installer updates and keep working until deleted by hand.

## Backstage software catalog

`catalog.locations` in `helm/backstage/values.yaml` registers two kinds of entries from
`itgix/adp-backstage-scaffold`: the scaffolder forms (new application on GitHub, new application
on GitLab) one by one, and the optional platform applications (DevLake, ...) through the single
`Location` file `catalog-info.yaml`. A new optional application is added to that file in the
scaffold repo, not in this template; a new scaffolder form gets its own entry here.

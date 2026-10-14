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

## OpenCost (Kubernetes cost monitoring)

Set `opencost_enabled: true` in the environment config to deploy OpenCost (`helm/opencost`, a
wrapper around the upstream `opencost` chart) into the `opencost` namespace. It requires
`enable_prometheus_stack: true` and fails the render with a message naming that key otherwise:
OpenCost reads its cost data from the kube-prometheus-stack Prometheus
(`kube-prometheus-stack-prometheus.monitoring:9090`) and exposes its own metrics through a
ServiceMonitor. Costs are calculated from public list prices, so no cloud credentials or IAM
are needed. The OpenCost UI is disabled and there is no ingress; Grafana is the only surface,
through the upstream community dashboard "OpenCost / Cost reporter / Basic overview"
(`helm/opencost/dashboards/`, provisioned as a ConfigMap in `monitoring` with the
`grafana_dashboard` label). The cluster id comes from `eks_cluster_name` (aws, default),
`gke_cluster_name` (gcp) or `aks_cluster_name` (azure). `opencost_branch` overrides the
targetRevision of the `helm/opencost` path the same way the other `<app>_branch` keys do.

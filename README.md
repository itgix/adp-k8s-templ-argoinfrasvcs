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

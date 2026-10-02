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

Backstage imports its catalog from a single location,
`https://github.com/itgix/adp-backstage-scaffold/blob/main/catalog-info.yaml`
(`catalog.locations` in `helm/backstage/values.yaml`). New catalog items are added in that file
in the scaffold repo, not in this template.

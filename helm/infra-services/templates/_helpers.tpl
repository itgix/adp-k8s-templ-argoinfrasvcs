{/* vim: set filetype=mustache: */}}


{{/*
Create metadata.name variable
*/}}
{{- define "metadata.name" -}}
{{- $name := default .appName -}}
{{- printf "%s" $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}


{{/*
Create chart.name as version used by the chart label
*/}}
{{- define "metadata.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}


{{/*
Create metadata.labels
*/}}
{{- define "metadata.labels" -}}
helm.sh/chart: {{ include "metadata.chart" . }}
app.kubernetes.io/name: {{ include "metadata.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}


{{/*
Create metadata.selectorLabels
*/}}
{{- define "metadata.selectorLabels" -}}
{{ $parts := split "-" .appName }}
{{- if eq $parts._1 "svc" }}
app.kubernetes.io/name: {{ printf "%s" $parts._0 }}
{{- else if eq $parts._2 "svc" }}
app.kubernetes.io/name: {{ printf "%s-%s" $parts._0 $parts._1}}
{{- else }}
app.kubernetes.io/name: {{ include "metadata.name" . }}
{{- end }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}


{{/*
Resolve an ingress class while preserving AWS as the default. Overrides are
applied from broadest to most specific:
ingress_class_name, <cloud>_ingress_class_name, <app>_ingress_class_name.
*/}}
{{- define "infra-services.ingressClassName" -}}
{{- $infraServices := .infraServices -}}
{{- $cloud := default "aws" (index $infraServices "cloud") -}}
{{- $defaultClass := ternary "gce" "alb" (eq $cloud "gcp") -}}
{{- $className := default $defaultClass (index $infraServices "ingress_class_name") -}}
{{- $cloudClassKey := printf "%s_ingress_class_name" $cloud -}}
{{- $className = default $className (index $infraServices $cloudClassKey) -}}
{{- $appClassKey := printf "%s_ingress_class_name" .app -}}
{{- default $className (index $infraServices $appClassKey) -}}
{{- end -}}


{{/*
Build cloud-aware ingress annotations. User-supplied maps are merged in this
order: ingress_annotations, <cloud>_ingress_annotations,
<app>_ingress_annotations.
*/}}
{{- define "infra-services.ingressAnnotations" -}}
{{- $infraServices := .infraServices -}}
{{- $app := .app -}}
{{- $cloud := default "aws" (index $infraServices "cloud") -}}
{{- $ingressClassName := include "infra-services.ingressClassName" (dict "infraServices" $infraServices "app" $app) -}}
{{- $annotations := dict
      "external-dns.alpha.kubernetes.io/hostname" .host
-}}
{{- if eq $cloud "gcp" -}}
{{- $_ := set $annotations "kubernetes.io/ingress.class" $ingressClassName -}}
{{- $managedCertificatesEnabled := true -}}
{{- if hasKey $infraServices "gcp_ingress_managed_certificates_enabled" -}}
{{- $managedCertificatesEnabled = index $infraServices "gcp_ingress_managed_certificates_enabled" -}}
{{- end -}}
{{- if and $managedCertificatesEnabled .managedCertificateName -}}
{{- $_ := set $annotations "networking.gke.io/managed-certificates" .managedCertificateName -}}
{{- end -}}
{{- $httpsRedirectEnabled := true -}}
{{- if hasKey $infraServices "gcp_ingress_https_redirect_enabled" -}}
{{- $httpsRedirectEnabled = index $infraServices "gcp_ingress_https_redirect_enabled" -}}
{{- end -}}
{{- if and $httpsRedirectEnabled .frontendConfigName -}}
{{- $_ := set $annotations "networking.gke.io/v1beta1.FrontendConfig" .frontendConfigName -}}
{{- end -}}
{{- else -}}
{{- $_ := set $annotations "alb.ingress.kubernetes.io/listen-ports" "[{\"HTTP\": 80}, {\"HTTPS\": 443}]" -}}
{{- $_ := set $annotations "alb.ingress.kubernetes.io/scheme" "internet-facing" -}}
{{- if ne $app "policy_reporter" -}}
{{- $_ := set $annotations "alb.ingress.kubernetes.io/ssl-redirect" "443" -}}
{{- end -}}
{{- $_ := set $annotations "alb.ingress.kubernetes.io/target-type" "ip" -}}
{{- if eq $app "backstage" -}}
{{- $_ := set $annotations "alb.ingress.kubernetes.io/target-group-attributes" "stickiness.enabled=true,stickiness.lb_cookie.duration_seconds=86400" -}}
{{- end -}}
{{- $isMonitoringIngress := or (eq $app "grafana") (eq $app "alertmanager") (eq $app "prometheus") -}}
{{- if or (eq $app "policy_reporter") $isMonitoringIngress -}}
{{- $_ := set $annotations "alb.ingress.kubernetes.io/group.name" "public" -}}
{{- $_ := set $annotations "alb.ingress.kubernetes.io/healthcheck-path" "/" -}}
{{- $_ := set $annotations "alb.ingress.kubernetes.io/success-codes" "200-404" -}}
{{- end -}}
{{- if $isMonitoringIngress -}}
{{- $_ := set $annotations "kubernetes.io/ingress.class" $ingressClassName -}}
{{- $_ := set $annotations "alb.ingress.kubernetes.io/actions.response-503" "{\"type\":\"fixed-response\",\"fixedResponseConfig\":{\"contentType\":\"text/plain\",\"statusCode\":\"503\",\"messageBody\":\"503 Service Unavailable\"}}" -}}
{{- $groupNameKey := printf "%s_ingress_group_name" $app -}}
{{- $schemeKey := printf "%s_ingress_scheme" $app -}}
{{- $loadBalancerAttributesKey := printf "%s_load_balancer_attributes" $app -}}
{{- $_ := set $annotations "alb.ingress.kubernetes.io/group.name" (default "public" (index $infraServices $groupNameKey)) -}}
{{- $_ := set $annotations "alb.ingress.kubernetes.io/scheme" (default "internet-facing" (index $infraServices $schemeKey)) -}}
{{- if index $infraServices $loadBalancerAttributesKey -}}
{{- $_ := set $annotations "alb.ingress.kubernetes.io/load-balancer-attributes" (index $infraServices $loadBalancerAttributesKey) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- $commonAnnotations := default dict (index $infraServices "ingress_annotations") -}}
{{- $cloudAnnotationsKey := printf "%s_ingress_annotations" $cloud -}}
{{- $cloudAnnotations := default dict (index $infraServices $cloudAnnotationsKey) -}}
{{- $appAnnotationsKey := printf "%s_ingress_annotations" $app -}}
{{- $appAnnotations := default dict (index $infraServices $appAnnotationsKey) -}}
{{- $annotations = mergeOverwrite $annotations $commonAnnotations $cloudAnnotations $appAnnotations -}}
{{- toYaml $annotations -}}
{{- end -}}


{{/*
Merge service-account annotations from broadest to most specific:
service_account_annotations, <cloud>_service_account_annotations,
<app>_service_account_annotations.
*/}}
{{- define "infra-services.serviceAccountAnnotations" -}}
{{- $infraServices := .infraServices -}}
{{- $cloud := default "aws" (index $infraServices "cloud") -}}
{{- $annotations := deepCopy (default dict .defaultAnnotations) -}}
{{- $commonAnnotations := default dict (index $infraServices "service_account_annotations") -}}
{{- $cloudAnnotationsKey := printf "%s_service_account_annotations" $cloud -}}
{{- $cloudAnnotations := default dict (index $infraServices $cloudAnnotationsKey) -}}
{{- $appAnnotationsKey := printf "%s_service_account_annotations" .app -}}
{{- $appAnnotations := default dict (index $infraServices $appAnnotationsKey) -}}
{{- $annotations = mergeOverwrite $annotations $commonAnnotations $cloudAnnotations $appAnnotations -}}
{{- toYaml $annotations -}}
{{- end -}}

{{/* Validate overrides even when this chart is rendered without the installer. */}}
{{- define "infra-services.validateGatewayOverrides" -}}
{{- $label := "[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?" -}}
{{- $subdomain := printf "%s(\\.%s)*" $label $label -}}
{{- range $setting := list
    (dict "key" "gcp_gateway_name" "pattern" $subdomain "limit" 253)
    (dict "key" "gcp_gateway_namespace" "pattern" $label "limit" 63)
    (dict "key" "gcp_gateway_class_name" "pattern" $subdomain "limit" 253) -}}
{{- $value := index $ $setting.key -}}
{{- if not (kindIs "string" $value) -}}
{{- fail (printf "%s must be a Kubernetes name" $setting.key) -}}
{{- end -}}
{{- if or (gt (len $value) $setting.limit) (not (regexMatch (printf "^%s$" $setting.pattern) $value)) -}}
{{- fail (printf "%s must be a valid Kubernetes name (maximum %d characters)" $setting.key $setting.limit) -}}
{{- end -}}
{{- end -}}
{{- $class := index . "gcp_gateway_class_name" -}}
{{- if and (hasPrefix "gke-" $class) (ne $class "gke-l7-global-external-managed") -}}
{{- fail "gcp_gateway_class_name must support global certificate maps, HTTP redirects, and Service backends; other built-in GKE classes are incompatible" -}}
{{- end -}}
{{- $overrides := index . "gcp_gateway_backends" -}}
{{- if not (kindIs "map" $overrides) -}}
{{- fail "gcp_gateway_backends must be a mapping" -}}
{{- end -}}
{{- $apps := list "argocd" "backstage" "policy_reporter" "grafana" "prometheus" "alertmanager" -}}
{{- $fields := list "namespace" "service_name" "service_port" "health_check_port" "health_check_path" -}}
{{- range $app, $backend := $overrides -}}
{{- if or (not (has $app $apps)) (not (kindIs "map" $backend)) -}}
{{- fail (printf "gcp_gateway_backends.%s must be a mapping for a supported platform service" $app) -}}
{{- end -}}
{{- range $key, $value := $backend -}}
{{- $path := printf "gcp_gateway_backends.%s.%s" $app $key -}}
{{- if not (has $key $fields) -}}
{{- fail (printf "Unknown setting %s" $path) -}}
{{- end -}}
{{- if has $key (list "service_port" "health_check_port") -}}
{{- if not (or (kindIs "int" $value) (kindIs "int64" $value) (kindIs "float64" $value)) -}}
{{- fail (printf "%s must be an integer between 1 and 65535" $path) -}}
{{- end -}}
{{- if or (lt (float64 $value) 1.0) (gt (float64 $value) 65535.0) (ne (float64 $value) (floor (float64 $value))) -}}
{{- fail (printf "%s must be an integer between 1 and 65535" $path) -}}
{{- end -}}
{{- else if eq $key "health_check_path" -}}
{{- if not (kindIs "string" $value) -}}
{{- fail (printf "%s must start with '/'" $path) -}}
{{- end -}}
{{- if not (hasPrefix "/" $value) -}}
{{- fail (printf "%s must start with '/'" $path) -}}
{{- end -}}
{{- else -}}
{{- $pattern := ternary $label "[a-z]([-a-z0-9]*[a-z0-9])?" (eq $key "namespace") -}}
{{- if not (kindIs "string" $value) -}}
{{- fail (printf "%s must be a Kubernetes name" $path) -}}
{{- end -}}
{{- if or (gt (len $value) 63) (not (regexMatch (printf "^%s$" $pattern) $value)) -}}
{{- fail (printf "%s must be a valid Kubernetes name (maximum 63 characters)" $path) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Kubernetes MCP server — ServiceAccount name.
*/}}
{{- define "aiops-platform.kubernetesMcp.serviceAccountName" -}}
kubernetes-mcp-readonly-sa
{{- end -}}

{{/*
Kubernetes MCP server — ClusterRole name.
*/}}
{{- define "aiops-platform.kubernetesMcp.clusterRoleName" -}}
kubernetes-mcp-readonly
{{- end -}}

{{/*
Kubernetes MCP server — ConfigMap name.
*/}}
{{- define "aiops-platform.kubernetesMcp.configMapName" -}}
kubernetes-mcp-configmap
{{- end -}}

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
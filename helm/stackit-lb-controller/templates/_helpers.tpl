{{- define "albc.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "albc.fullname" -}}
{{- default (include "albc.name" .) .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "albc.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "albc.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "albc.labels" -}}
app.kubernetes.io/name: {{ include "albc.fullname" . }}
app.kubernetes.io/part-of: stackit-alb
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

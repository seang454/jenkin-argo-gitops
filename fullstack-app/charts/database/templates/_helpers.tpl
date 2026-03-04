{{- define "database.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "database.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "database.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "database.labels" -}}
helm.sh/chart: {{ include "database.chart" . }}
{{ include "database.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "database.selectorLabels" -}}
app.kubernetes.io/name: {{ include "database.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Return true if we should create a new secret, false if using existing
*/}}
{{- define "database.createSecret" -}}
{{- if .Values.auth.existingSecret -}}
  {{- false -}}
{{- else -}}
  {{- true -}}
{{- end -}}
{{- end }}

{{/*
Return the secret name
*/}}
{{- define "database.secretName" -}}
{{- if .Values.auth.existingSecret -}}
  {{- .Values.auth.existingSecret -}}
{{- else -}}
  {{- printf "%s-secret" (include "database.fullname" .) -}}
{{- end -}}
{{- end }}

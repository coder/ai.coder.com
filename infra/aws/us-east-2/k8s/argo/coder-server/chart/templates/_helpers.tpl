{{/*
Expand the name of the chart.
*/}}
{{- define "coder.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name. Truncated to 63 chars (K8s label limit).
*/}}
{{- define "coder.fullname" -}}
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

{{/*
Common labels for wrapper-managed resources.
*/}}
{{- define "coder.labels" -}}
app.kubernetes.io/name: {{ include "coder.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.coder.coder.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels matching the upstream coder chart's pod labels.
The upstream chart uses:
  app.kubernetes.io/name: coder
  app.kubernetes.io/instance: <release>
*/}}
{{- define "coder.upstreamSelectorLabels" -}}
app.kubernetes.io/name: coder
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Namespace helper.
*/}}
{{- define "coder.namespace" -}}
{{- .Values.namespace | default .Release.Namespace }}
{{- end }}

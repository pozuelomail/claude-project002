{{/*
_helpers.tpl — Funciones de ayuda reutilizables para el chart
*/}}

{{/* Nombre del chart */}}
{{- define "wordpress-iso27001.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Nombre completo del release */}}
{{- define "wordpress-iso27001.fullname" -}}
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

{{/* Versión del chart */}}
{{- define "wordpress-iso27001.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Labels comunes */}}
{{- define "wordpress-iso27001.labels" -}}
helm.sh/chart: {{ include "wordpress-iso27001.chart" . }}
{{ include "wordpress-iso27001.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/environment: {{ .Values.global.environment }}
{{- end }}

{{/* Selector labels WordPress */}}
{{- define "wordpress-iso27001.selectorLabels" -}}
app.kubernetes.io/name: {{ include "wordpress-iso27001.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Selector labels MariaDB */}}
{{- define "wordpress-iso27001.mariadb.selectorLabels" -}}
app.kubernetes.io/name: {{ include "wordpress-iso27001.name" . }}-mariadb
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Nombre del ServiceAccount */}}
{{- define "wordpress-iso27001.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "wordpress-iso27001.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* Nombre del Secret de MariaDB */}}
{{- define "wordpress-iso27001.mariadb.secretName" -}}
{{- printf "%s-mariadb" (include "wordpress-iso27001.fullname" .) }}
{{- end }}

{{/* Nombre del Secret de WordPress */}}
{{- define "wordpress-iso27001.wordpress.secretName" -}}
{{- printf "%s-wordpress" (include "wordpress-iso27001.fullname" .) }}
{{- end }}

{{/* Nombre del servicio MariaDB */}}
{{- define "wordpress-iso27001.mariadb.serviceName" -}}
{{- printf "%s-mariadb" (include "wordpress-iso27001.fullname" .) }}
{{- end }}

{{/* Nombre del secreto TLS */}}
{{- define "wordpress-iso27001.tls.secretName" -}}
{{- if .Values.tls.secretName }}
{{- .Values.tls.secretName }}
{{- else }}
{{- printf "%s-tls" (include "wordpress-iso27001.fullname" .) }}
{{- end }}
{{- end }}

{{/* URL completa del sitio */}}
{{- define "wordpress-iso27001.siteUrl" -}}
{{- if .Values.tls.enabled }}
{{- printf "https://%s" .Values.site.url }}
{{- else }}
{{- printf "http://%s" .Values.site.url }}
{{- end }}
{{- end }}

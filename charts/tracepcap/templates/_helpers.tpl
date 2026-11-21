{{/* Chart name, truncated to the 63-char DNS label limit. */}}
{{- define "tracepcap.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Release-qualified name. */}}
{{- define "tracepcap.fullname" -}}
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

{{- define "tracepcap.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "tracepcap.labels" -}}
helm.sh/chart: {{ include "tracepcap.chart" . }}
{{ include "tracepcap.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: tracepcap
{{- end }}

{{- define "tracepcap.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tracepcap.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Labels for one component: (dict "ctx" $ "component" "backend") */}}
{{- define "tracepcap.componentLabels" -}}
{{ include "tracepcap.labels" .ctx }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "tracepcap.componentSelectorLabels" -}}
{{ include "tracepcap.selectorLabels" .ctx }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/* Image reference: (dict "ctx" $ "image" .Values.backend.image) */}}
{{- define "tracepcap.image" -}}
{{- $registry := .ctx.Values.global.imageRegistry | default .image.registry -}}
{{- $ref := printf "%s/%s" $registry .image.repository | trimPrefix "/" -}}
{{- if .image.digest -}}
{{- printf "%s@%s" $ref .image.digest -}}
{{- else -}}
{{- printf "%s:%s" $ref (.image.tag | default .ctx.Chart.AppVersion) -}}
{{- end -}}
{{- end }}

{{- define "tracepcap.imagePullSecrets" -}}
{{- with .Values.global.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{- define "tracepcap.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "tracepcap.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "tracepcap.storageClass" -}}
{{- $sc := .persistence.storageClass | default .ctx.Values.global.storageClass -}}
{{- if $sc }}
storageClassName: {{ if eq $sc "-" }}""{{ else }}{{ $sc | quote }}{{ end }}
{{- end }}
{{- end }}

{{/*
A generated secret value that survives upgrades: reuse what the live Secret already holds,
else generate. (dict "ctx" $ "secret" <name> "key" <key> "value" <explicit value or "">)
*/}}
{{- define "tracepcap.secretValue" -}}
{{- if .value -}}
{{- .value -}}
{{- else -}}
{{- $existing := lookup "v1" "Secret" .ctx.Release.Namespace .secret -}}
{{- if and $existing (index $existing.data .key) -}}
{{- index $existing.data .key | b64dec -}}
{{- else -}}
{{- randAlphaNum 32 -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/* ---------- Database ---------- */}}
{{- define "tracepcap.postgresql.fullname" -}}
{{- printf "%s-postgresql" (include "tracepcap.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "tracepcap.database.host" -}}
{{- if .Values.postgresql.enabled -}}
{{- include "tracepcap.postgresql.fullname" . -}}
{{- else -}}
{{- required "externalDatabase.host is required when postgresql.enabled=false" .Values.externalDatabase.host -}}
{{- end -}}
{{- end }}

{{- define "tracepcap.database.port" -}}
{{- if .Values.postgresql.enabled }}5432{{ else }}{{ .Values.externalDatabase.port }}{{ end -}}
{{- end }}

{{- define "tracepcap.database.name" -}}
{{- if .Values.postgresql.enabled }}{{ .Values.postgresql.auth.database }}{{ else }}{{ .Values.externalDatabase.database }}{{ end -}}
{{- end }}

{{/* Secret + keys the backend reads the DB credentials from. */}}
{{- define "tracepcap.database.secretName" -}}
{{- if .Values.postgresql.enabled -}}
{{- .Values.postgresql.auth.existingSecret | default (include "tracepcap.postgresql.fullname" .) -}}
{{- else -}}
{{- .Values.externalDatabase.existingSecret | default (printf "%s-external-db" (include "tracepcap.fullname" .)) -}}
{{- end -}}
{{- end }}

{{- define "tracepcap.database.passwordKey" -}}
{{- if .Values.postgresql.enabled }}password{{ else }}{{ .Values.externalDatabase.existingSecretPasswordKey }}{{ end -}}
{{- end }}

{{/* ---------- Object storage ---------- */}}
{{- define "tracepcap.minio.fullname" -}}
{{- printf "%s-minio" (include "tracepcap.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "tracepcap.s3.endpoint" -}}
{{- if .Values.minio.enabled -}}
{{- printf "http://%s:9000" (include "tracepcap.minio.fullname" .) -}}
{{- else -}}
{{- required "externalS3.endpoint is required when minio.enabled=false" .Values.externalS3.endpoint -}}
{{- end -}}
{{- end }}

{{- define "tracepcap.s3.bucket" -}}
{{- if .Values.minio.enabled }}{{ .Values.minio.bucket }}{{ else }}{{ .Values.externalS3.bucket }}{{ end -}}
{{- end }}

{{/* Secret + keys for the S3 credentials, as (list secretName accessKeyKey secretKeyKey). */}}
{{- define "tracepcap.s3.secretName" -}}
{{- if .Values.minio.enabled -}}
{{- .Values.minio.auth.existingSecret | default (include "tracepcap.minio.fullname" .) -}}
{{- else -}}
{{- .Values.externalS3.existingSecret | default (printf "%s-external-s3" (include "tracepcap.fullname" .)) -}}
{{- end -}}
{{- end }}

{{- define "tracepcap.s3.accessKeyKey" -}}
{{- if .Values.minio.enabled }}root-user{{ else }}access-key{{ end -}}
{{- end }}

{{- define "tracepcap.s3.secretKeyKey" -}}
{{- if .Values.minio.enabled }}root-password{{ else }}secret-key{{ end -}}
{{- end }}

{{- define "tracepcap.backend.fullname" -}}
{{- printf "%s-backend" (include "tracepcap.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "tracepcap.frontend.fullname" -}}
{{- printf "%s-frontend" (include "tracepcap.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "tracepcap.llm.secretName" -}}
{{- .Values.backend.llm.existingSecret | default (printf "%s-llm" (include "tracepcap.fullname" .)) -}}
{{- end }}

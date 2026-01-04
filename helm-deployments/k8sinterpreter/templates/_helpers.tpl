{{/*
Expand the name of the chart.
*/}}
{{- define "k8sinterpreter.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "k8sinterpreter.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "k8sinterpreter.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "k8sinterpreter.labels" -}}
helm.sh/chart: {{ include "k8sinterpreter.chart" . }}
{{ include "k8sinterpreter.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "k8sinterpreter.selectorLabels" -}}
app.kubernetes.io/name: {{ include "k8sinterpreter.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use for API
*/}}
{{- define "k8sinterpreter.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "k8sinterpreter.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the executor service account
*/}}
{{- define "k8sinterpreter.executorServiceAccountName" -}}
{{- if .Values.execution.serviceAccount.create }}
{{- default (printf "%s-executor" (include "k8sinterpreter.fullname" .)) .Values.execution.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.execution.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Execution namespace
*/}}
{{- define "k8sinterpreter.executionNamespace" -}}
{{- default .Release.Namespace .Values.execution.namespace }}
{{- end }}

{{/*
Redis URL
*/}}
{{- define "k8sinterpreter.redisUrl" -}}
{{- if .Values.redis.url }}
{{- .Values.redis.url }}
{{- else if .Values.redis.host }}
{{- if .Values.redis.password }}
{{- printf "redis://:%s@%s:%d/%d" .Values.redis.password .Values.redis.host (int .Values.redis.port) (int .Values.redis.db) }}
{{- else }}
{{- printf "redis://%s:%d/%d" .Values.redis.host (int .Values.redis.port) (int .Values.redis.db) }}
{{- end }}
{{- else }}
{{- "redis://redis:6379/0" }}
{{- end }}
{{- end }}

{{/*
Check if Helm-managed secret is needed
Returns true if any of the following conditions are met:
- api.existingSecret is not set (API_KEY will be auto-generated)
- redis.existingSecret is not set (REDIS_URL needs to be generated)
- minio.existingSecret is not set AND minio.useIAM is false (S3 credentials needed)
*/}}
{{- define "k8sinterpreter.needsHelmSecret" -}}
{{- if or (not .Values.api.existingSecret) (not .Values.redis.existingSecret) (and (not .Values.minio.existingSecret) (not .Values.minio.useIAM)) }}
{{- true }}
{{- end }}
{{- end }}

{{/*
Validate MinIO/S3 configuration
When not using existingSecret or IAM, accessKey and secretKey should be provided.
This is a warning helper - it doesn't fail the template but can be used for documentation.
*/}}
{{- define "k8sinterpreter.validateMinioConfig" -}}
{{- if and (not .Values.minio.existingSecret) (not .Values.minio.useIAM) }}
{{- if or (not .Values.minio.accessKey) (not .Values.minio.secretKey) }}
{{- /* S3 credentials not fully configured - application may fail at runtime */ -}}
{{- end }}
{{- end }}
{{- end }}

{{/*
Get the list of all secret names that should be referenced in envFrom.
This helps ensure consistent secret references across templates.
*/}}
{{- define "k8sinterpreter.secretRefs" -}}
{{- $secrets := list }}
{{- if not .Values.secretsStore.enabled }}
{{- if include "k8sinterpreter.needsHelmSecret" . }}
{{- $secrets = append $secrets (printf "%s-secrets" (include "k8sinterpreter.fullname" .)) }}
{{- end }}
{{- if .Values.api.existingSecret }}
{{- $secrets = append $secrets .Values.api.existingSecret }}
{{- end }}
{{- if .Values.redis.existingSecret }}
{{- $secrets = append $secrets .Values.redis.existingSecret }}
{{- end }}
{{- if .Values.minio.existingSecret }}
{{- $secrets = append $secrets .Values.minio.existingSecret }}
{{- end }}
{{- else }}
{{- $secrets = append $secrets (printf "%s-aws-secrets" (include "k8sinterpreter.fullname" .)) }}
{{- end }}
{{- toJson $secrets }}
{{- end }}

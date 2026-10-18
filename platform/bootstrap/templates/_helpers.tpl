{{/*
Standard Argo CD Application for a Helm chart, with values coming from Git:
  platform/values/<component>/common.yaml   (all clouds)
  platform/values/<component>/<cloud>.yaml  (cloud overlay, optional)
plus inline values rendered from cluster facts.

Usage:
  include "platform.helmApp" (dict "root" $ "name" "kyverno" "namespace" "kyverno"
    "wave" "0" "chart" .Values.charts.kyverno "inline" (dict ...))
*/}}
{{- define "platform.helmApp" -}}
{{- $r := .root -}}
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {{ .name }}
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: {{ .wave | quote }}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: platform
  sources:
    - repoURL: {{ .chart.repo }}
      chart: {{ .chart.chart }}
      targetRevision: {{ .chart.version }}
      helm:
        releaseName: {{ .name }}
        ignoreMissingValueFiles: true
        valueFiles:
          - $values/platform/values/{{ .name }}/common.yaml
          - $values/platform/values/{{ .name }}/{{ $r.Values.cloud }}.yaml
        {{- with .inline }}
        valuesObject:
          {{- toYaml . | nindent 10 }}
        {{- end }}
    - repoURL: {{ $r.Values.repoURL }}
      targetRevision: {{ $r.Values.targetRevision }}
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: {{ .namespace }}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
    {{- with .managedNamespaceMetadata }}
    managedNamespaceMetadata:
      {{- toYaml . | nindent 6 }}
    {{- end }}
{{- end -}}


{{/*
Cluster-specific kube-prometheus-stack values: external labels, storage size
and retention, and (AWS) Alertmanager -> SNS routing.
*/}}
{{- define "platform.kpsInline" -}}
{{- $v := .Values -}}
prometheus:
  prometheusSpec:
    externalLabels:
      cluster: {{ $v.clusterName | quote }}
    retention: {{ $v.monitoring.retention | quote }}
    storageSpec:
      volumeClaimTemplate:
        spec:
          resources:
            requests:
              storage: {{ $v.monitoring.storageSize | quote }}
{{- if and (eq $v.cloud "eks") $v.monitoring.alertsTopicArn }}
alertmanager:
  config:
    route:
      receiver: sns
      group_by: [alertname, namespace]
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      routes:
        - receiver: "null"
          matchers: ['alertname = "Watchdog"']
        - receiver: "null"
          matchers: ['alertname = "InfoInhibitor"']
    receivers:
      - name: "null"
      - name: sns
        sns_configs:
          - topic_arn: {{ $v.monitoring.alertsTopicArn | quote }}
            send_resolved: true
            sigv4:
              region: {{ $v.region | quote }}
            subject: {{ printf "[%s] {{ .Status | toUpper }} {{ .CommonLabels.alertname }}" $v.clusterName | quote }}
{{- end }}
{{- end -}}


{{/* Metrics wiring per chart, only when the monitoring stack is enabled. */}}
{{- define "platform.values.certManager" -}}
{{- if .Values.monitoring.enabled }}
prometheus:
  enabled: true
  servicemonitor:
    enabled: true
{{- end }}
{{- end -}}

{{- define "platform.values.externalSecrets" -}}
{{- if .Values.monitoring.enabled }}
metrics:
  service:
    enabled: true
serviceMonitor:
  enabled: true
{{- end }}
{{- end -}}

{{- define "platform.values.kyverno" -}}
{{- if .Values.monitoring.enabled }}
admissionController:
  serviceMonitor: { enabled: true }
backgroundController:
  serviceMonitor: { enabled: true }
cleanupController:
  serviceMonitor: { enabled: true }
reportsController:
  serviceMonitor: { enabled: true }
grafana:
  enabled: true
{{- end }}
{{- end -}}

{{- define "platform.values.falco" -}}
{{- $v := .Values -}}
{{- if $v.monitoring.enabled }}
serviceMonitor:
  create: true
grafana:
  dashboards:
    enabled: true
{{- end }}
{{- if and (eq $v.cloud "eks") $v.alerts.snsTopicArn }}
falcosidekick:
  config:
    aws:
      region: {{ $v.region | quote }}
      sns:
        topicarn: {{ $v.alerts.snsTopicArn | quote }}
        minimumpriority: error
{{- end }}
{{- end -}}

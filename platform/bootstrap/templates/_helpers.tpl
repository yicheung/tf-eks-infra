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

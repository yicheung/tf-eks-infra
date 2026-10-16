{{/* Match Pods (and, via autogen, their controllers) outside system namespaces. */}}
{{- define "policies.podMatch" -}}
matchConstraints:
  namespaceSelector:
    matchExpressions:
      - key: kubernetes.io/metadata.name
        operator: NotIn
        values:
          {{- toYaml .Values.systemNamespaces | nindent 10 }}
  resourceRules:
    - apiGroups: [""]
      apiVersions: [v1]
      operations: [CREATE, UPDATE]
      resources: [pods]
{{- end -}}

{{/* All containers of a Pod, including init and ephemeral. */}}
{{- define "policies.allContainersVar" -}}
- name: containers
  expression: >-
    object.spec.containers
    + object.spec.?initContainers.orValue([])
    + object.spec.?ephemeralContainers.orValue([])
{{- end -}}

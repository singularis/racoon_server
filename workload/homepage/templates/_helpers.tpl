{{- define "homepage.labels" -}}
app.kubernetes.io/name: homepage
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "homepage.selectorLabels" -}}
app.kubernetes.io/name: homepage
{{- end -}}

{{- define "homepage.serviceAccountName" -}}
{{ .Values.serviceAccount.name | default "homepage" }}
{{- end -}}


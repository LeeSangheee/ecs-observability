extensions:
  health_check:
    endpoint: 0.0.0.0:13133
  sigv4auth:
    region: ${region}
    service: aps

receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

  # ECS Task CPU/메모리 메트릭 자동 수집
  awsecscontainermetrics:
    collection_interval: 20s

processors:
  memory_limiter:
    check_interval: 1s
    limit_mib: 200
    spike_limit_mib: 50

  batch:
    timeout: 5s
    send_batch_size: 512

  resource:
    attributes:
      - key: service.name
        value: ${service_name}
        action: upsert
      - key: deployment.environment
        value: ${environment}
        action: upsert

exporters:
  prometheusremotewrite:
    endpoint: ${amp_remote_write_endpoint}
    auth:
      authenticator: sigv4auth

  awsxray:
    region: ${region}

  awscloudwatchlogs:
    log_group_name: ${app_log_group}
    log_stream_name: otel-logs
    region: ${region}

service:
  extensions: [health_check, sigv4auth]
  pipelines:
    metrics:
      receivers: [otlp, awsecscontainermetrics]
      processors: [memory_limiter, batch, resource]
      exporters: [prometheusremotewrite]
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch, resource]
      exporters: [awsxray]
    logs:
      receivers: [otlp]
      processors: [memory_limiter, batch, resource]
      exporters: [awscloudwatchlogs]

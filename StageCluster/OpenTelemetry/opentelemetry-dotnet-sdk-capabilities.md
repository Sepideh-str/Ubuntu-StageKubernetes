# OpenTelemetry .NET SDK --- Application Instrumentation Capabilities

## 1. Overview

The OpenTelemetry SDK enables .NET applications to generate, collect,
and export telemetry about their internal behavior and interactions with
other services.

It provides application-level observability through three primary
telemetry signals:

-   **Traces:** Individual request journeys and operation execution.
-   **Metrics:** Numerical measurements of application behavior over
    time.
-   **Logs:** Application events, diagnostic information, and errors.

Instrumentation allows operators and developers to understand
application performance, investigate failures, identify bottlenecks, and
follow requests across distributed services.

## 2. Distributed Tracing

Distributed tracing records the execution of a request through an
application and across multiple services.

### 2.1 HTTP Request Tracing

ASP.NET Core instrumentation can automatically record incoming requests,
including:

-   HTTP method
-   Route
-   Response status
-   Request duration
-   Trace ID
-   Span ID
-   Error status

Example:

``` text
Service: crouseserviceloan-develop
Operation: GET /api/Loan/PriorityInfo
Duration: 184 ms
Status: 200
TraceId: 9d71bc2e75a0480c
SpanId: a81f02c4
```

This allows endpoints to be analyzed for response times, failures, and
performance bottlenecks without manually adding timing logic to every
controller.

### 2.2 Distributed Tracing Across Applications

OpenTelemetry supports tracing across multiple instrumented services
through trace context propagation.

Example request flow:

``` text
Client
  |
APISIX Gateway
  |
CrouseServiceLoan
  |
CrouseServiceCustomer
  |
Database
```

When participating applications are instrumented and propagate context
correctly, their operations can be connected into a distributed trace.

This enables:

-   Following requests across multiple services.
-   Identifying which service caused delays.
-   Measuring individual service execution time.
-   Identifying failing dependencies.
-   Understanding request relationships.
-   Investigating errors across service boundaries.

## 3. Dependency Instrumentation

OpenTelemetry supports instrumentation for supported dependencies.

### 3.1 HTTP Client Instrumentation

Outgoing HTTP calls can be instrumented to capture:

-   Destination service.
-   HTTP method.
-   Request duration.
-   Response status.
-   Errors and timeouts.
-   Trace context propagation.

This helps identify slow or failing remote services.

Example:

``` text
Parent Span:
GET /api/Loan/PriorityInfo

Child Span:
HTTP GET Customer API

Duration: 320 ms
Status: 200
```

### 3.2 Database Instrumentation

Supported database clients can be instrumented to record database
operations.

Depending on the integration, telemetry may include:

-   Database system.
-   Operation type.
-   Operation duration.
-   Error information.
-   Trace relationships with the originating request.

Example:

``` text
GET /api/Loan/PriorityInfo
    └── Database Operation
          ├── Operation: SELECT
          ├── Duration: 1,850 ms
          └── Status: Completed
```

This can help identify database operations contributing to API response
times.

Database instrumentation capabilities and captured query information
depend on the database client, instrumentation package, configuration,
and data-protection settings.

## 4. Custom Application Tracing

Automatic instrumentation captures common operations, but it does not
understand application-specific business logic.

OpenTelemetry allows developers to create custom spans around important
operations.

Example business workflow:

``` text
PriorityInfo
    ├── ValidateLoan
    ├── LoadCustomer
    ├── CheckEligibility
    ├── CalculatePriority
    └── GenerateResponse
```

Custom spans can record:

-   Operation start and completion.
-   Execution duration.
-   Operation relationships.
-   Status and error conditions.
-   Selected attributes describing the operation.

Example trace:

``` text
PriorityInfo                      450 ms
│
├── ValidateLoan                   12 ms
├── LoadCustomer                   85 ms
├── CheckEligibility              280 ms
├── CalculatePriority              25 ms
└── GenerateResponse               18 ms
```

Custom tracing is useful for complex calculations, validation pipelines,
workflows, data transformations, authentication and authorization,
background jobs, and scheduled tasks.

## 5. Application Metrics

Metrics are numerical measurements collected over time. Unlike traces,
which describe individual requests, metrics provide an overview of
application behavior and performance over a period.

OpenTelemetry SDK supports the creation and export of application
metrics.

### 5.1 ASP.NET Core Metrics

ASP.NET Core instrumentation can provide measurements related to
incoming HTTP requests, depending on the instrumentation version and
configuration, including:

-   Request count.
-   Request duration.
-   HTTP response status distribution.
-   Request activity and performance.

These metrics allow monitoring of application traffic and response
performance.

### 5.2 .NET Runtime Metrics

OpenTelemetry can collect metrics from the .NET runtime, including:

  -----------------------------------------------------------------------
  Metric Category                     Purpose
  ----------------------------------- -----------------------------------
  Garbage collection                  Monitor GC activity

  Heap memory                         Monitor managed memory usage

  Allocation                          Monitor memory allocation behavior

  ThreadPool                          Monitor thread activity

  Exceptions                          Observe exception-related
                                      measurements

  Runtime activity                    Understand runtime performance and
                                      resource behavior
  -----------------------------------------------------------------------

These metrics help identify memory pressure, excessive allocations,
runtime bottlenecks, and application resource issues.

### 5.3 Custom Application Metrics

Applications can define their own metrics using OpenTelemetry
instruments.

  -----------------------------------------------------------------------
  Instrument              Purpose                 Example
  ----------------------- ----------------------- -----------------------
  Counter                 Counts events that      Number of loans
                          increase over time      processed

  UpDownCounter           Tracks values that      Active loan processing
                          increase or decrease    jobs

  Histogram               Measures distributions  Loan processing
                                                  duration

  Gauge                   Measures current values Current active workload
  -----------------------------------------------------------------------

Example business metrics:

``` text
loan.requests.total
loan.processing.duration
loan.active.processing
loan.calculation.errors
loan.approval.count
```

These metrics can monitor business activity and application-specific
performance, not only technical behavior.

## 6. Application Logging

OpenTelemetry can integrate with .NET logging and Serilog to support a
unified observability pipeline.

Existing Serilog logging can continue to be used. OpenTelemetry can
complement it with trace context, log correlation, and telemetry export
capabilities.

### 6.1 Structured Logging

Logs can contain structured fields rather than only plain text.

Example:

``` json
{
  "Timestamp": "2026-11-21T10:30:00Z",
  "Level": "Information",
  "Message": "Loan priority calculated",
  "LoanId": 1524,
  "CustomerId": 3001,
  "TraceId": "9d71bc2e75a0480c",
  "SpanId": "a81f02c4"
}
```

Structured logging makes logs easier to filter, search, aggregate, and
analyze.

### 6.2 Trace-Correlated Logs

When logs are generated during an instrumented operation, trace context
can be associated with those logs.

This provides the ability to move between a trace and its related log
events.

Example:

``` text
TraceId: 9d71bc2e75a0480c

Trace
 ├── GET /api/Loan/PriorityInfo
 ├── HTTP Customer API
 └── SQL Query

Related Logs
 ├── Loan request received
 ├── Customer information loaded
 ├── Priority calculated
 └── Loan completed
```

This correlation reduces investigation time and helps understand request
execution.

### 6.3 Logging Levels and Events

Application logs can continue to use standard logging levels:

-   Trace
-   Debug
-   Information
-   Warning
-   Error
-   Critical

OpenTelemetry provides a standardized telemetry model for log records,
allowing logs to be processed and exported through the observability
pipeline.

Serilog can remain the application logging framework while OpenTelemetry
handles interoperability and telemetry export.

## 7. Trace and Log Correlation

OpenTelemetry uses trace context to connect logs, traces, and individual
operations.

  Identifier       Description
  ---------------- -----------------------------------------------------
  Trace ID         Identifies the complete distributed request
  Span ID          Identifies an individual operation within the trace
  Parent Span ID   Identifies the parent operation where applicable

Example:

``` text
Trace ID: 9d71bc2e75a0480c

Loan API
  Span ID: 1001
  ├── Customer API
  │     Span ID: 1002
  └── SQL Operation
        Span ID: 1003
```

Logs generated during these operations can carry the corresponding Trace
ID and Span ID.

Benefits:

-   Find logs related to a specific request.
-   Investigate failures from a trace.
-   Connect log events to the operation that generated them.
-   Understand which service or dependency was responsible.
-   Avoid relying only on timestamps to correlate activity.

## 8. Context Propagation

Context propagation allows tracing information to travel between
applications through supported communication mechanisms.

For HTTP communication, OpenTelemetry commonly uses the W3C Trace
Context standard.

Example:

``` http
traceparent: 00-4a8f92c1a5d738af123456789012abcd-8e72f102a3456789-01
```

When an instrumented service receives the request, it can extract the
trace context and continue the existing trace.

Example:

``` text
Loan API
   Trace ID: 4a8f92c1
        |
        | HTTP request + trace context
        v
Customer API
   Trace ID: 4a8f92c1
        |
        | HTTP request + trace context
        v
Payment API
   Trace ID: 4a8f92c1
```

Context propagation supports:

-   Distributed traces.
-   Parent-child span relationships.
-   Cross-service request correlation.
-   Trace-linked logs.
-   Dependency analysis.

Trace continuity requires compatible instrumentation and propagation
across the communication path. Uninstrumented services or unsupported
protocols may interrupt trace visibility.

## 9. Exception and Error Visibility

OpenTelemetry instrumentation helps capture errors that occur during
application operations.

Depending on the instrumentation, errors can be represented through:

-   Span status.
-   Exception events.
-   HTTP error status.
-   Database operation errors.
-   Failed dependency calls.
-   Application logs associated with the trace.

Example:

``` text
Trace: 9d71bc

GET /api/Loan/PriorityInfo
│
├── Loan API                 OK
├── Customer API             OK
└── SQL Query                ERROR
      ├── Duration: 2.4 sec
      ├── Exception: TimeoutException
      └── Span Status: Error
```

This helps identify whether an error originated from application logic,
an HTTP dependency, a database operation, a timeout, or a downstream
service.

## 10. Background Operations and Scheduled Jobs

Instrumentation is not limited to HTTP requests.

OpenTelemetry can also instrument operations outside the
request-response cycle, including:

-   Background workers.
-   Hosted services.
-   Queue consumers.
-   Scheduled tasks.
-   Batch jobs.
-   Data processing jobs.

Custom spans can measure execution time, record errors, and track
operation relationships.

Example:

``` text
Loan Background Worker
│
├── FetchPendingLoans       120 ms
├── ProcessLoan             450 ms
├── UpdateDatabase          180 ms
└── PublishResult            60 ms

Total: 810 ms
```

This provides visibility into workloads that would not necessarily
appear as incoming HTTP request traces.

## 11. Application Identity and Resource Attributes

OpenTelemetry telemetry includes resource attributes that describe the
entity producing the telemetry.

This is important in Kubernetes because the same application may have
multiple pods, replicas, environments, and versions.

Example:

``` text
service.name: crouseserviceloan-develop
service.namespace: crouseserviceloan-develop
service.version: V1.0.26-beta
deployment.environment.name: develop
```

These attributes help identify which application and environment
generated the telemetry.

With additional Kubernetes enrichment from the Agent, telemetry may also
contain:

``` text
k8s.namespace.name: crouseserviceloan-develop
k8s.pod.name: crouseserviceloan-77bfdf9b66-mh7mk
k8s.deployment.name: crouseserviceloan
k8s.node.name: stage-workerb2
container.name: crouseserviceloan
```

Telemetry can then be filtered by service, environment, application
version, namespace, pod, deployment, node, or container.

Application identity attributes are configured through SDK resource
settings. Kubernetes-specific attributes can be obtained through SDK
configuration or Collector/Agent enrichment, depending on the
architecture.

## 12. Sampling and Telemetry Control

Instrumentation can produce a large volume of telemetry, particularly in
applications receiving high request volumes.

OpenTelemetry supports sampling mechanisms to control how many traces
are recorded and exported.

Sampling can help:

-   Reduce telemetry volume.
-   Reduce storage consumption.
-   Control network bandwidth.
-   Reduce Collector processing load.
-   Preserve useful traces for troubleshooting.

Sampling must be configured carefully. If trace context is not
propagated consistently, or sampling decisions are made independently
across services, distributed traces may be incomplete.

## 13. Telemetry Export Through OTLP

OpenTelemetry supports exporting telemetry through the OpenTelemetry
Protocol (OTLP).

OTLP provides standardized transport for:

-   Traces.
-   Metrics.
-   Logs.

The application can export telemetry to an OpenTelemetry Collector,
which processes and forwards it to supported observability backends.

Example:

``` text
.NET Application
│
├── Traces
├── Metrics
└── Logs
       │
       ▼
      OTLP
       │
       ▼
OpenTelemetry Collector
       │
├── Processing
├── Batching
├── Filtering
└── Export
       │
       ▼
Observability Backend
```

This separates application instrumentation from telemetry processing and
storage.

The application does not need to know the details of the final backend;
it sends telemetry to the configured OTLP endpoint.

## 14. What the SDK Does Not Provide

The OpenTelemetry SDK primarily observes the application in which it is
installed. It is not a replacement for Kubernetes infrastructure
monitoring.

  Capability                                  SDK Alone
  ------------------------------------------- -------------------------------------
  Application request tracing                 Yes
  Application metrics                         Yes
  Application logs                            Yes, when integrated and configured
  HTTP dependency tracing                     Yes, for supported instrumentation
  Database tracing                            Yes, for supported instrumentation
  Custom business tracing                     Yes
  Trace context propagation                   Yes, with supported integrations
  Kubernetes node CPU                         No
  Kubernetes node memory                      No
  Other pods' logs                            No
  Container logs for unrelated applications   No
  Kubernetes events                           No, not by itself
  Cilium network flows                        No
  Cluster-wide pod monitoring                 No

These infrastructure capabilities should be handled by the OTel Agent,
other Collectors, Prometheus, kube-state-metrics, cAdvisor, Hubble, or
other appropriate monitoring systems.

## 15. Capabilities Summary

  -----------------------------------------------------------------------
  Capability                          Description
  ----------------------------------- -----------------------------------
  Tracing                             Request execution, span
                                      relationships, durations, failures,
                                      and distributed request journeys

  Metrics                             Application traffic, runtime
                                      behavior, measurements, and
                                      business metrics

  Logs                                Structured events, trace
                                      correlation, exceptions, and log
                                      export

  Context propagation                 Trace continuity across
                                      applications and supported
                                      dependencies

  Dependency instrumentation          Visibility into HTTP calls and
                                      supported database operations

  Custom instrumentation              Business-operation tracing and
                                      application-specific measurements

  Runtime instrumentation             .NET runtime metrics such as GC and
                                      memory behavior

  OTLP export                         Standardized telemetry delivery to
                                      Collectors and backends
  -----------------------------------------------------------------------

## 16. Conclusion

OpenTelemetry SDK instrumentation provides deeper visibility into the
internal behavior of .NET applications.

It enables applications to generate telemetry that explains how requests
are processed, how dependencies behave, how much time individual
operations consume, and where failures occur.

For a Kubernetes platform, this adds a layer of observability that
infrastructure monitoring and container log collection alone cannot
provide.

The SDK allows application telemetry to be connected with the existing
Kubernetes observability infrastructure, creating a more complete view
of the environment.

**The SDK turns your application from a source of logs into an
instrumented, observable service.**

from prometheus_client import Counter, Gauge, Histogram

REQUEST_COUNT = Counter(
    "synthetic_api_requests_total",
    "Total HTTP requests by path and status.",
    ["path", "status"],
)

REQUEST_LATENCY = Histogram(
    "synthetic_api_request_latency_seconds",
    "HTTP request latency by path.",
    ["path"],
)

CPU_WORK_COUNT = Counter(
    "synthetic_api_cpu_work_total",
    "Synthetic CPU work invocations.",
)

MEMORY_ALLOCATION_COUNT = Counter(
    "synthetic_api_memory_allocations_total",
    "Synthetic memory allocation invocations.",
)

LEAKED_MEMORY_MB = Gauge(
    "synthetic_api_leaked_memory_mb",
    "Current intentionally retained memory in MB.",
)


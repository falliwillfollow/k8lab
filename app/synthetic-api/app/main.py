import json
import os
import random
import socket
import time
from typing import Callable

from fastapi import FastAPI, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest

from .load import allocate_memory, burn_cpu
from .metrics import (
    CPU_WORK_COUNT,
    LEAKED_MEMORY_MB,
    MEMORY_ALLOCATION_COUNT,
    REQUEST_COUNT,
    REQUEST_LATENCY,
)

app = FastAPI(title="Synthetic API", version="local")
START_TIME = time.time()
POD_NAME = os.getenv("POD_NAME", socket.gethostname())
READY_FAIL_RATE = float(os.getenv("READY_FAIL_RATE", "0.0"))
READY_STARTUP_DELAY_SECONDS = int(os.getenv("READY_STARTUP_DELAY_SECONDS", "0"))
MAX_MEMORY_ALLOCATION_MB = int(os.getenv("MAX_MEMORY_ALLOCATION_MB", "512"))
MAX_LEAK_MEMORY_MB = int(os.getenv("MAX_LEAK_MEMORY_MB", "1024"))
MAX_CPU_BURN_SECONDS = int(os.getenv("MAX_CPU_BURN_SECONDS", "30"))
LEAK_STORE: list[bytearray] = []


def clamp_int(value: int, low: int, high: int) -> int:
    return max(low, min(value, high))


@app.middleware("http")
async def metrics_and_logs(request: Request, call_next: Callable) -> Response:
    started = time.perf_counter()
    status = 500
    try:
        response = await call_next(request)
        status = response.status_code
        return response
    finally:
        elapsed = time.perf_counter() - started
        path = request.url.path
        REQUEST_COUNT.labels(path=path, status=str(status)).inc()
        REQUEST_LATENCY.labels(path=path).observe(elapsed)
        print(
            json.dumps(
                {
                    "pod": POD_NAME,
                    "path": path,
                    "status": status,
                    "latency_ms": round(elapsed * 1000, 2),
                }
            ),
            flush=True,
        )


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/readyz")
def readyz(response: Response) -> dict[str, str]:
    if time.time() - START_TIME < READY_STARTUP_DELAY_SECONDS:
        response.status_code = 503
        return {"status": "starting"}
    if READY_FAIL_RATE > 0 and random.random() < READY_FAIL_RATE:
        response.status_code = 503
        return {"status": "intermittent_failure"}
    return {"status": "ready"}


@app.get("/work")
def work(
    response: Response,
    cpu_ms: int = 0,
    memory_mb: int = 0,
    sleep_ms: int = 0,
    status: int = 200,
) -> dict[str, int | str]:
    cpu_seconds = clamp_int(cpu_ms, 0, MAX_CPU_BURN_SECONDS * 1000) / 1000
    memory_mb = clamp_int(memory_mb, 0, MAX_MEMORY_ALLOCATION_MB)
    sleep_seconds = clamp_int(sleep_ms, 0, 60000) / 1000

    if cpu_seconds:
        CPU_WORK_COUNT.inc()
        burn_cpu(cpu_seconds)
    blob = allocate_memory(memory_mb) if memory_mb else None
    if blob is not None:
        MEMORY_ALLOCATION_COUNT.inc()
    if sleep_seconds:
        time.sleep(sleep_seconds)

    response.status_code = clamp_int(status, 100, 599)
    return {
        "status": "ok",
        "cpu_ms": int(cpu_seconds * 1000),
        "memory_mb": memory_mb,
        "sleep_ms": int(sleep_seconds * 1000),
    }


@app.get("/cpu")
def cpu(seconds: int = 1) -> dict[str, int]:
    seconds = clamp_int(seconds, 0, MAX_CPU_BURN_SECONDS)
    CPU_WORK_COUNT.inc()
    burn_cpu(seconds)
    return {"seconds": seconds}


@app.get("/memory")
def memory(mb: int = 64, hold_seconds: int = 5) -> dict[str, int]:
    mb = clamp_int(mb, 0, MAX_MEMORY_ALLOCATION_MB)
    hold_seconds = clamp_int(hold_seconds, 0, 60)
    blob = allocate_memory(mb)
    MEMORY_ALLOCATION_COUNT.inc()
    time.sleep(hold_seconds)
    return {"mb": mb, "hold_seconds": hold_seconds, "allocated": len(blob)}


@app.get("/leak")
def leak(mb: int = 10) -> dict[str, int]:
    current = sum(len(item) for item in LEAK_STORE) // 1024 // 1024
    remaining = max(MAX_LEAK_MEMORY_MB - current, 0)
    mb = clamp_int(mb, 0, remaining)
    if mb:
        LEAK_STORE.append(allocate_memory(mb))
    current = sum(len(item) for item in LEAK_STORE) // 1024 // 1024
    LEAKED_MEMORY_MB.set(current)
    return {"added_mb": mb, "leaked_memory_mb": current}


@app.get("/metrics")
def metrics() -> Response:
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


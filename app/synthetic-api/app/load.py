import math
import time


def burn_cpu(seconds: float) -> None:
    deadline = time.perf_counter() + max(seconds, 0)
    value = 0.0001
    while time.perf_counter() < deadline:
        value = math.sqrt(value + 1.2345)


def allocate_memory(mb: int) -> bytearray:
    return bytearray(max(mb, 0) * 1024 * 1024)


import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 20,
  duration: '90s',
};

const BASE_URL = __ENV.BASE_URL || 'http://127.0.0.1:8080';

export default function () {
  const res = http.get(`${BASE_URL}/work?cpu_ms=5&memory_mb=1&sleep_ms=900`, { timeout: '10s' });
  check(res, { 'status is 200': (r) => r.status === 200 });
  sleep(0.1);
}


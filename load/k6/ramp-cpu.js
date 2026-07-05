import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 4 },
    { duration: '60s', target: 16 },
    { duration: '60s', target: 24 },
    { duration: '30s', target: 0 },
  ],
};

const BASE_URL = __ENV.BASE_URL || 'http://127.0.0.1:8080';

export default function () {
  const res = http.get(`${BASE_URL}/work?cpu_ms=250&memory_mb=1&sleep_ms=0`, { timeout: '10s' });
  check(res, { 'request completed': (r) => r.status < 500 });
  sleep(0.2);
}


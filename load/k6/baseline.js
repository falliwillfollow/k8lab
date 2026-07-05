import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 4,
  duration: '45s',
  thresholds: {
    http_req_failed: ['rate<0.02'],
    http_req_duration: ['p(95)<500'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://127.0.0.1:8080';

export default function () {
  const res = http.get(`${BASE_URL}/work?cpu_ms=20&memory_mb=2&sleep_ms=20`);
  check(res, { 'status is 200': (r) => r.status === 200 });
  sleep(1);
}


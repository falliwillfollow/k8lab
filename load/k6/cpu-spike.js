import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 12,
  duration: '90s',
};

const BASE_URL = __ENV.BASE_URL || 'http://127.0.0.1:8080';

export default function () {
  const res = http.get(`${BASE_URL}/work?cpu_ms=300&memory_mb=1&sleep_ms=0`);
  check(res, { 'request completed': (r) => r.status < 500 });
  sleep(0.2);
}


import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 6,
  duration: '60s',
};

const BASE_URL = __ENV.BASE_URL || 'http://127.0.0.1:8080';

export default function () {
  const res = http.get(`${BASE_URL}/memory?mb=120&hold_seconds=4`, { timeout: '20s' });
  check(res, { 'request completed': (r) => r.status < 500 });
  sleep(0.5);
}


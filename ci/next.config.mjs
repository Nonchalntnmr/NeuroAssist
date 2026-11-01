/** @type {import('next').NextConfig} */
const securityHeaders = [
  { key: 'X-Content-Type-Options', value: 'nosniff' },
  { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
  { key: 'X-Frame-Options', value: 'DENY' },
  { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=()' },
];
const nextConfig = {
  reactStrictMode: true,
  poweredByHeader: false,
  async headers() { return [{ source: '/(.*)', headers: securityHeaders }]; },
  // The collective runs in a Python function (api/index.py). Locally: uvicorn on :8000.
  async rewrites() {
    return [{ source: '/api/py/:path*', destination: process.env.NODE_ENV === 'development' || process.env.PY_LOCAL ?'http://127.0.0.1:8000/api/py/:path*' : '/api/' }];
  },
};
export default nextConfig;

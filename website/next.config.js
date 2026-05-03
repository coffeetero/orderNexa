// next.config.js
/** @type {import('next').NextConfig} */

// const dns = require('dns');
// dns.setDefaultResultOrder('ipv4first');

const nextConfig = {
  eslint: {
    ignoreDuringBuilds: true,
  },
  images: { unoptimized: true },
  async redirects() {
    return [
      { source: '/customer', destination: '/account', permanent: true },
      { source: '/customer/:path*', destination: '/account/:path*', permanent: true },
    ];
  },
};

module.exports = nextConfig;

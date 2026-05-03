// next.config.js
/** @type {import('next').NextConfig} */

// const dns = require('dns');
// dns.setDefaultResultOrder('ipv4first');

const nextConfig = {
  eslint: {
    ignoreDuringBuilds: true,
  },
  images: { unoptimized: true },
};

module.exports = nextConfig;

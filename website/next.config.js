/** @type {import('next').NextConfig} */
const nextConfig = {
  eslint: {
    ignoreDuringBuilds: true,
  },
  images: { unoptimized: true },
  async redirects() {
    return [
      { source: '/tenant', destination: '/account', permanent: true },
      { source: '/tenant/:path*', destination: '/account/:path*', permanent: true },
    ];
  },
};

module.exports = nextConfig;

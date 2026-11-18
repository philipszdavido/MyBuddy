// Applies migrations to the dedicated test database before the integration suite runs.
const { execSync } = require('node:child_process');

module.exports = async () => {
  process.env.DATABASE_URL = process.env.TEST_DATABASE_URL || 'postgresql://mybuddy:mybuddy@localhost:5433/mybuddy_test?schema=public';
  execSync('npx prisma migrate deploy', { stdio: ['ignore', 'inherit', 'inherit'], env: process.env });
};

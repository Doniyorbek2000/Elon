/** Server URL for e2e databases (a local/CI PostgreSQL with PostGIS). */
const SERVER = process.env.E2E_POSTGRES_URL ?? 'postgresql://bozor:bozor_dev_password@localhost:5432';

export const adminUrl = () => `${SERVER}/postgres`;
export const databaseUrl = (name: string) => `${SERVER}/${name}?schema=public`;

import 'reflect-metadata';

import { env } from './config/env';
import { createApp } from './bootstrap';
import { flushMonitoring, initMonitoring, reportError } from './infra/monitoring';

async function main(): Promise<void> {
  const config = env(); // fail fast on invalid configuration
  initMonitoring('api');
  const app = await createApp();
  await app.listen(config.PORT, '0.0.0.0');
}

main().catch((error: unknown) => {
  process.stderr.write(`Fatal startup error: ${error instanceof Error ? error.message : String(error)}\n`);
  reportError(error, { phase: 'startup' });
  void flushMonitoring().finally(() => process.exit(1));
});

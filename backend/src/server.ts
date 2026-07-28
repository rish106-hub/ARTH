import { buildApp } from './app.js';
import { env } from './config.js';
import { startPaydayReminderScheduler } from './pushNotifications.js';

const app = await buildApp();

try {
  await app.listen({
    port: env.PORT,
    host: env.HOST,
  });
  startPaydayReminderScheduler();
} catch (error) {
  app.log.error(error);
  process.exit(1);
}

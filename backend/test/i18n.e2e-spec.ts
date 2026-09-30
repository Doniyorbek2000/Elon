import { NotificationType } from '@prisma/client';

import { PrismaService } from '../src/infra/prisma.service';
import { msg } from '../src/common/i18n';
import { NotificationsService } from '../src/modules/notifications/notifications.service';
import { as, signIn, startTestApp, stopTestApp, TestContext, TestUser } from './helpers';

describe('Notifications follow the user’s language', () => {
  let ctx: TestContext;
  let user: TestUser;

  beforeAll(async () => {
    ctx = await startTestApp();
    user = await signIn(ctx.http);
  });

  afterAll(async () => {
    await stopTestApp(ctx);
  });

  const notify = () =>
    ctx.app.get(NotificationsService).notify(user.userId, {
      type: NotificationType.SUBSCRIPTION,
      title: 'Tarif faollashtirildi',
      body: msg('Amal qilish muddati: {date} gacha.', { date: '2026-12-31' }),
      route: '/account/plans',
    });

  const latest = async () =>
    await ctx.app.get(PrismaService).notification.findFirstOrThrow({
      where: { userId: user.userId },
      orderBy: { createdAt: 'desc' },
    });

  it('defaults to Uzbek and exposes the setting', async () => {
    const me = await as(ctx.http, user).get('/me').expect(200);
    expect(me.body.data.settings.language).toBe('uz');
    await notify();
    expect(await latest()).toMatchObject({
      title: 'Tarif faollashtirildi',
      body: 'Amal qilish muddati: 2026-12-31 gacha.',
    });
  });

  it('renders Russian after the user switches language, and rejects unknown ones', async () => {
    await as(ctx.http, user).patch('/me', { language: 'de' }).expect(422);
    const me = await as(ctx.http, user).patch('/me', { language: 'ru' }).expect(200);
    expect(me.body.data.settings.language).toBe('ru');
    await notify();
    expect(await latest()).toMatchObject({
      title: 'Тариф активирован',
      body: 'Срок действия: до 2026-12-31.',
    });
  });
});

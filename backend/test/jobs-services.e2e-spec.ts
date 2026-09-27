import request from 'supertest';

import { as, NAMANGAN_CHUST, signIn, startTestApp, stopTestApp, TestContext, TestUser } from './helpers';

describe('Jobs, applications, resumes, services, reviews', () => {
  let ctx: TestContext;
  let employer: TestUser;
  let candidate: TestUser;
  let provider: TestUser;
  let customer: TestUser;
  let outsider: TestUser;
  let jobId: string;
  let applicationId: string;
  let providerId: string;

  beforeAll(async () => {
    ctx = await startTestApp();
    [employer, candidate, provider, customer, outsider] = await Promise.all([
      signIn(ctx.http),
      signIn(ctx.http),
      signIn(ctx.http),
      signIn(ctx.http),
      signIn(ctx.http),
    ]);
  });

  afterAll(async () => {
    await stopTestApp(ctx);
  });

  const vacancy = {
    title: 'Sotuvchi-konsultant',
    companyName: 'Chust Savdo MCHJ',
    description: 'Do‘konimizga tajribali sotuvchi kerak. Mijozlar bilan ishlash, kassa.',
    requirements: ['Muloqot ko‘nikmasi', 'Kompyuter savodxonligi'],
    responsibilities: ['Mijozlarga maslahat berish'],
    salaryMin: 4000000,
    salaryMax: 6000000,
    salaryCurrency: 'uzs',
    employmentType: 'fullTime',
    workFormat: 'onSite',
    experience: 'upTo1',
    workSchedule: '09:00–18:00',
    applicationMode: 'both',
    place: NAMANGAN_CHUST,
  };

  it('flow 6a: employer posts a vacancy that candidates can find', async () => {
    const created = await as(ctx.http, employer).post('/jobs', vacancy).expect(201);
    jobId = created.body.data.id;
    expect(created.body.data.status).toBe('active');
    expect(created.body.data.company.verification).not.toBe('business'); // never self-declared

    const search = await request(ctx.http)
      .get('/api/v1/jobs?region=namangan&types=fullTime&q=sotuvchi')
      .expect(200);
    expect(search.body.data.map((j: { id: string }) => j.id)).toContain(jobId);
    const filtered = await request(ctx.http).get('/api/v1/jobs?region=namangan&types=partTime').expect(200);
    expect(filtered.body.data.map((j: { id: string }) => j.id)).not.toContain(jobId);

    const invalid = await as(ctx.http, employer)
      .post('/jobs', { ...vacancy, salaryMin: 9000000, salaryMax: 1000000 })
      .expect(422);
    expect(invalid.body.error.code).toBe('VALIDATION_FAILED');
  });

  it('candidate keeps a CV with visibility control', async () => {
    const resume = await as(ctx.http, candidate)
      .put('/me/resume', {
        title: 'Sotuvchi',
        about: 'Savdo sohasida 2 yillik tajriba.',
        experienceYears: 2,
        skills: ['Savdo', '1C'],
        employmentTypes: ['fullTime'],
        preferredRegionId: 'namangan',
        visibility: 'applicationsOnly',
        experiences: [{ company: 'Korzinka', position: 'Kassir', startYear: 2022, endYear: 2024 }],
      })
      .expect(200);
    const resumeId = resume.body.data.id;
    // Not public: outsiders cannot see it, and it is not listed.
    await as(ctx.http, outsider).get(`/candidates/${resumeId}`).expect(404);
    const list = await as(ctx.http, outsider).get('/candidates?region=namangan').expect(200);
    expect(list.body.data.map((r: { id: string }) => r.id)).not.toContain(resumeId);
  });

  it('flow 6b: candidate applies → employer sees applicant → status update notifies candidate', async () => {
    const applied = await as(ctx.http, candidate)
      .post(`/jobs/${jobId}/applications`, { coverLetter: 'Men bu ishga qiziqaman.' })
      .expect(201);
    applicationId = applied.body.data.id;
    expect(applied.body.data.status).toBe('submitted');
    await as(ctx.http, candidate).post(`/jobs/${jobId}/applications`, {}).expect(409);
    await as(ctx.http, employer).post(`/jobs/${jobId}/applications`, {}).expect(422);

    const employerInbox = await as(ctx.http, employer).get('/notifications').expect(200);
    expect(employerInbox.body.data[0]).toEqual(expect.objectContaining({ type: 'applicationReceived' }));

    // Only the owner of the vacancy can list applicants.
    await as(ctx.http, outsider).get(`/jobs/${jobId}/applications`).expect(404);
    const applicants = await as(ctx.http, employer).get(`/jobs/${jobId}/applications`).expect(200);
    expect(applicants.body.data).toHaveLength(1);
    expect(applicants.body.data[0].applicant.id).toBe(candidate.userId);
    expect(applicants.body.data[0].resume.desiredPosition).toBe('Sotuvchi'); // applicationsOnly → visible to this employer

    await as(ctx.http, outsider)
      .patch(`/applications/${applicationId}/status`, { status: 'accepted' })
      .expect(404);
    await as(ctx.http, employer)
      .patch(`/applications/${applicationId}/status`, { status: 'shortlisted' })
      .expect(200);

    const candidateInbox = await as(ctx.http, candidate).get('/notifications').expect(200);
    const statusNote = candidateInbox.body.data.find((n: { type: string }) => n.type === 'applicationStatus');
    expect(statusNote).toBeTruthy();
    expect(statusNote.deepLink).toBe('/account/applications');
    const unread = await as(ctx.http, candidate).get('/notifications/unread-count').expect(200);
    expect(unread.body.data.count).toBeGreaterThan(0);
    await as(ctx.http, candidate).post('/notifications/read-all').expect(200);
    const after = await as(ctx.http, candidate).get('/notifications/unread-count').expect(200);
    expect(after.body.data.count).toBe(0);

    const mine = await as(ctx.http, candidate).get('/me/applications').expect(200);
    expect(mine.body.data[0]).toEqual(expect.objectContaining({ id: applicationId, status: 'shortlisted' }));

    // Employer can message the applicant about this vacancy.
    const chat = await as(ctx.http, employer)
      .post('/conversations', {
        contextType: 'candidate',
        contextId:
          applied.body.data.resumeId ?? (await as(ctx.http, candidate).get('/me/resume')).body.data.id,
      })
      .expect(200);
    expect(chat.body.data.peer.id).toBe(candidate.userId);
  });

  it('employer controls vacancy status; others cannot', async () => {
    await as(ctx.http, outsider).post(`/jobs/${jobId}/status`, { status: 'filled' }).expect(404);
    await as(ctx.http, outsider).put(`/jobs/${jobId}`, vacancy).expect(404);
    await as(ctx.http, employer).post(`/jobs/${jobId}/status`, { status: 'paused' }).expect(200);
    const search = await request(ctx.http).get('/api/v1/jobs?region=namangan').expect(200);
    expect(search.body.data.map((j: { id: string }) => j.id)).not.toContain(jobId);
    await as(ctx.http, candidate).post(`/jobs/${jobId}/applications`, {}).expect(404);
    await as(ctx.http, employer).post(`/jobs/${jobId}/status`, { status: 'active' }).expect(200);
  });

  it('saved jobs persist server-side', async () => {
    await as(ctx.http, candidate).put(`/favorites/jobs/${jobId}`).expect(200);
    const saved = await as(ctx.http, candidate).get('/favorites/jobs').expect(200);
    expect(saved.body.data.map((j: { id: string }) => j.id)).toEqual([jobId]);
  });

  it('flow 7: provider publishes profile + service → customer discovers → opens chat', async () => {
    const categories = await request(ctx.http).get('/api/v1/service-categories').expect(200);
    expect(categories.body.data.map((c: { id: string }) => c.id)).toContain('plumber');

    const profile = await as(ctx.http, provider)
      .put('/me/provider', {
        displayName: 'Anvar Usta',
        profession: 'Santexnik',
        description: 'Quvurlar, kranlar, isitish tizimlari o‘rnatish va ta’mirlash.',
        experienceYears: 8,
        categoryIds: ['plumber'],
        place: NAMANGAN_CHUST,
        areas: [
          { regionId: 'namangan', districtId: 'chust' },
          { regionId: 'namangan', districtId: 'pop' },
        ],
        availability: 'available',
      })
      .expect(200);
    providerId = profile.body.data.id;
    expect(profile.body.data.profile.rating).toBeNull(); // no fabricated rating
    await as(ctx.http, provider)
      .post('/me/provider/offerings', {
        categoryId: 'plumber',
        title: 'Kran almashtirish',
        pricingType: 'from',
        priceFrom: 100000,
        currency: 'uzs',
      })
      .expect(201);

    const found = await as(ctx.http, customer).get('/providers?category=plumber&region=namangan').expect(200);
    const card = found.body.data.find((p: { id: string }) => p.id === providerId);
    expect(card).toBeTruthy();
    expect(card.priceFrom).toEqual({ amount: 100000, currency: 'uzs' });

    const detail = await as(ctx.http, customer).get(`/providers/${providerId}`).expect(200);
    expect(detail.body.data.offerings).toHaveLength(1);

    const chat = await as(ctx.http, customer)
      .post('/conversations', { contextType: 'service', contextId: providerId })
      .expect(200);
    expect(chat.body.data.peer.id).toBe(provider.userId);
    expect(chat.body.data.context.subject).toBe('service');
  });

  it('reviews require a real two-way conversation and update aggregates', async () => {
    // Customer has only opened the chat: not eligible yet.
    const early = await as(ctx.http, customer)
      .put(`/providers/${providerId}/reviews/mine`, { rating: 5, text: 'Zo‘r' })
      .expect(403);
    expect(early.body.error.code).toBe('NOT_ELIGIBLE');
    await as(ctx.http, outsider).put(`/providers/${providerId}/reviews/mine`, { rating: 1 }).expect(403);
    const self = await as(ctx.http, provider).put(`/providers/${providerId}/reviews/mine`, { rating: 5 });
    expect([403, 422]).toContain(self.status); // no self-review

    const chat = await as(ctx.http, customer)
      .post('/conversations', { contextType: 'service', contextId: providerId })
      .expect(200);
    await as(ctx.http, customer)
      .post(`/conversations/${chat.body.data.id}/messages`, { type: 'text', text: 'Ertaga kela olasizmi?' })
      .expect(201);
    await as(ctx.http, provider)
      .post(`/conversations/${chat.body.data.id}/messages`, { type: 'text', text: 'Ha, soat 10 da.' })
      .expect(201);

    await as(ctx.http, customer)
      .put(`/providers/${providerId}/reviews/mine`, { rating: 4, text: 'Tez va sifatli' })
      .expect(200);
    await as(ctx.http, customer)
      .put(`/providers/${providerId}/reviews/mine`, { rating: 5, text: 'Yana murojaat qildim' })
      .expect(200); // edits, no duplicates
    const detail = await as(ctx.http, customer).get(`/providers/${providerId}`).expect(200);
    expect(detail.body.data.profile.rating).toBe(5);
    expect(detail.body.data.profile.reviewCount).toBe(1);
    await as(ctx.http, customer).put(`/providers/${providerId}/reviews/mine`, { rating: 6 }).expect(422);
  });

  it('provider data can only be edited by its owner', async () => {
    const offerings = await as(ctx.http, provider).get('/me/provider').expect(200);
    const offeringId = offerings.body.data.offerings[0].id;
    await as(ctx.http, outsider)
      .patch(`/me/provider/offerings/${offeringId}`, {
        categoryId: 'plumber',
        title: 'Hacked',
        pricingType: 'fixed',
      })
      .expect(404);
    await as(ctx.http, outsider).delete(`/me/provider/offerings/${offeringId}`).expect(404);
  });
});

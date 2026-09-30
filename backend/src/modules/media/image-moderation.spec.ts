import { interpretSightengine } from './image-moderation';

const ok = (extra: object) => ({ status: 'success', ...extra });

describe('Sightengine verdicts', () => {
  it('passes ordinary photos', () => {
    const result = interpretSightengine(
      ok({
        nudity: { sexual_activity: 0.01, sexual_display: 0.01, erotica: 0.02, very_suggestive: 0.03 },
        gore: { prob: 0.01 },
        offensive: { prob: 0.02 },
      }),
    );
    expect(result).toMatchObject({ verdict: 'clean', labels: [] });
  });

  it('blocks explicit content and gore at high confidence', () => {
    expect(interpretSightengine(ok({ nudity: { sexual_activity: 0.95 } }))).toMatchObject({
      verdict: 'block',
      labels: ['sexual_activity'],
    });
    expect(interpretSightengine(ok({ gore: { prob: 0.92 } }))).toMatchObject({
      verdict: 'block',
      labels: ['gore'],
    });
  });

  it('sends borderline content to review', () => {
    expect(interpretSightengine(ok({ nudity: { sexual_display: 0.6 } }))).toMatchObject({
      verdict: 'review',
      labels: ['sexual_display'],
    });
    expect(interpretSightengine(ok({ nudity: { erotica: 0.75 } })).verdict).toBe('review');
    expect(interpretSightengine(ok({ offensive: { prob: 0.85 } })).verdict).toBe('review');
    expect(interpretSightengine(ok({ nudity: { erotica: 0.4 }, offensive: { prob: 0.3 } })).verdict).toBe(
      'clean',
    );
  });

  it('treats provider errors as errors, never as clean', () => {
    expect(() => interpretSightengine({ status: 'failure', error: { message: 'bad key' } })).toThrow(
      /bad key/,
    );
    expect(() => interpretSightengine({})).toThrow();
  });
});

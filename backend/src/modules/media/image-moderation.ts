import { env } from '../../config/env';

export type ModerationVerdict = 'clean' | 'review' | 'block';

export interface ImageModerationResult {
  verdict: ModerationVerdict;
  /** Highest risk score (0–1) that drove the verdict. */
  score: number;
  labels: string[];
}

export interface ImageModerationProvider {
  readonly name: string;
  /** False for the no-op provider: uploads are then not marked as checked. */
  readonly enabled: boolean;
  classify(image: Buffer): Promise<ImageModerationResult>;
}

export const IMAGE_MODERATION = Symbol('IMAGE_MODERATION');

export class NoImageModeration implements ImageModerationProvider {
  readonly name = 'none';
  readonly enabled = false;

  async classify(): Promise<ImageModerationResult> {
    return { verdict: 'clean', score: 0, labels: [] };
  }
}

/** Thresholds: at or above BLOCK the image is rejected, at or above REVIEW a moderator decides. */
const BLOCK = 0.9;
const REVIEW = 0.5;

interface SightengineResponse {
  status?: string;
  error?: { message?: string };
  nudity?: {
    sexual_activity?: number;
    sexual_display?: number;
    erotica?: number;
    very_suggestive?: number;
  };
  gore?: { prob?: number };
  offensive?: { prob?: number };
}

/**
 * Maps a Sightengine `nudity-2.1` + `gore-2.0` + `offensive` response to a verdict.
 * Explicit sexual content and gore are blocked at high confidence; borderline
 * scores and "erotica"/"very suggestive" go to human review.
 */
export function interpretSightengine(response: SightengineResponse): ImageModerationResult {
  if (response.status !== 'success') {
    throw new Error(`Sightengine error: ${response.error?.message ?? response.status ?? 'unknown'}`);
  }
  const explicit: Array<[string, number]> = [
    ['sexual_activity', response.nudity?.sexual_activity ?? 0],
    ['sexual_display', response.nudity?.sexual_display ?? 0],
    ['gore', response.gore?.prob ?? 0],
  ];
  const borderline: Array<[string, number]> = [
    ['erotica', (response.nudity?.erotica ?? 0) * (0.5 / 0.7)],
    ['very_suggestive', (response.nudity?.very_suggestive ?? 0) * (0.5 / 0.7)],
    ['offensive', (response.offensive?.prob ?? 0) * (0.5 / 0.8)],
  ];
  const all = [...explicit, ...borderline];
  const [topLabel, topScore] = all.reduce((best, item) => (item[1] > best[1] ? item : best), ['none', 0]);
  const labels = all.filter(([, score]) => score >= REVIEW).map(([label]) => label);
  if (explicit.some(([, score]) => score >= BLOCK)) return { verdict: 'block', score: topScore, labels };
  if (topScore >= REVIEW)
    return { verdict: 'review', score: topScore, labels: labels.length ? labels : [topLabel] };
  return { verdict: 'clean', score: topScore, labels: [] };
}

export class SightengineModeration implements ImageModerationProvider {
  readonly name = 'sightengine';
  readonly enabled = true;

  async classify(image: Buffer): Promise<ImageModerationResult> {
    const config = env();
    const form = new FormData();
    form.append('media', new Blob([new Uint8Array(image)], { type: 'image/jpeg' }), 'photo.jpg');
    form.append('models', 'nudity-2.1,gore-2.0,offensive');
    form.append('api_user', config.SIGHTENGINE_USER ?? '');
    form.append('api_secret', config.SIGHTENGINE_SECRET ?? '');
    const response = await fetch(config.SIGHTENGINE_URL, {
      method: 'POST',
      body: form,
      signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) throw new Error(`Sightengine HTTP ${response.status}`);
    return interpretSightengine((await response.json()) as SightengineResponse);
  }
}

export function createImageModeration(): ImageModerationProvider {
  return env().IMAGE_MODERATION_PROVIDER === 'sightengine'
    ? new SightengineModeration()
    : new NoImageModeration();
}

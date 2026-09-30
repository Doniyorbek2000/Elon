import { AccountType, Prisma, VerificationLevel } from '@prisma/client';

import { presentPlace, presentUser, publicUserSelect } from '../../common/presenters';
import { apiEnum } from '../../common/text';

export const jobCardSelect = {
  id: true,
  employerId: true,
  companyName: true,
  title: true,
  salaryMin: true,
  salaryMax: true,
  salaryCurrency: true,
  salaryNegotiable: true,
  employmentType: true,
  workFormat: true,
  experience: true,
  workSchedule: true,
  applicationMode: true,
  status: true,
  publishedAt: true,
  createdAt: true,
  viewCount: true,
  regionId: true,
  districtId: true,
  lat: true,
  lng: true,
  region: { select: { name: true } },
  district: { select: { name: true } },
  employer: { select: publicUserSelect },
} satisfies Prisma.JobSelect;

export const jobDetailSelect = {
  ...jobCardSelect,
  description: true,
  requirements: true,
  responsibilities: true,
  expiresAt: true,
  _count: { select: { applications: true } },
} satisfies Prisma.JobSelect;

type CardRow = Prisma.JobGetPayload<{ select: typeof jobCardSelect }>;
type DetailRow = Prisma.JobGetPayload<{ select: typeof jobDetailSelect }>;

const TONES = ['blue', 'green', 'orange', 'purple', 'teal', 'amber', 'indigo', 'red'];

function company(row: CardRow) {
  const profile = row.employer.profile;
  // Company is shown as verified only for server-verified business accounts.
  const verified =
    profile?.accountType === AccountType.BUSINESS && profile.verification === VerificationLevel.BUSINESS;
  const hash = [...row.companyName].reduce((h, c) => (h * 31 + c.charCodeAt(0)) >>> 0, 7);
  return {
    id: row.employerId,
    name: row.companyName,
    iconKey: 'work',
    tone: TONES[hash % TONES.length],
    verification: verified ? 'business' : 'none',
  };
}

export function presentJobCard(
  row: CardRow,
  options: { isFavorite?: boolean; distanceKm?: number | null } = {},
) {
  return {
    id: row.id,
    title: row.title,
    company: company(row),
    place: presentPlace(row),
    publishedAt: row.publishedAt ?? row.createdAt,
    employmentType: apiEnum(row.employmentType),
    workFormat: apiEnum(row.workFormat),
    experience: apiEnum(row.experience),
    workingHours: row.workSchedule ?? '',
    applicationMode: apiEnum(row.applicationMode),
    salaryMin: row.salaryMin,
    salaryMax: row.salaryMax,
    currency: apiEnum(row.salaryCurrency),
    salaryNegotiable: row.salaryNegotiable,
    status: apiEnum(row.status),
    views: row.viewCount,
    employer: presentUser(row.employer),
    description: '',
    requirements: [] as string[],
    responsibilities: [] as string[],
    isFavorite: options.isFavorite ?? false,
    distanceKm: options.distanceKm ?? null,
  };
}

export function presentJobDetail(
  row: DetailRow,
  webBaseUrl: string,
  options: { isFavorite?: boolean; isOwner?: boolean; myApplication?: unknown } = {},
) {
  return {
    ...presentJobCard(row, options),
    description: row.description,
    requirements: row.requirements,
    responsibilities: row.responsibilities,
    expiresAt: row.expiresAt,
    shareUrl: `${webBaseUrl}/job/${row.id}`,
    myApplication: options.myApplication ?? null,
    ...(options.isOwner ? { applicationCount: row._count.applications } : {}),
  };
}

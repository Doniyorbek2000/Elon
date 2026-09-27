import { Prisma } from '@prisma/client';

import { PublicUserRow, presentMoney, presentUser } from '../../common/presenters';
import { apiEnum } from '../../common/text';

export const resumeInclude = {
  experiences: { orderBy: { sortOrder: 'asc' } },
  educations: { orderBy: { sortOrder: 'asc' } },
} satisfies Prisma.ResumeInclude;

type ResumeRow = Prisma.ResumeGetPayload<{ include: typeof resumeInclude }>;

export function presentResume(
  resume: ResumeRow,
  user: PublicUserRow,
  place?: { regionName: string | null; districtName: string | null },
) {
  return {
    id: resume.id,
    profile: presentUser(user),
    desiredPosition: resume.title,
    about: resume.about ?? '',
    experienceYears: resume.experienceYears,
    skills: resume.skills,
    employmentTypes: resume.employmentTypes.map((t) => apiEnum(t)),
    expectedSalary: presentMoney(resume.salaryExpectation, resume.salaryCurrency),
    visibility: apiEnum(resume.visibility),
    place: {
      regionId: resume.preferredRegionId,
      regionName: place?.regionName ?? null,
      districtId: resume.preferredDistrictId,
      districtName: place?.districtName ?? null,
    },
    experiences: resume.experiences.map((e) => ({
      company: e.company,
      position: e.position,
      startYear: e.startYear,
      endYear: e.endYear,
      description: e.description,
    })),
    educations: resume.educations.map((e) => ({ institution: e.institution, degree: e.degree, endYear: e.endYear })),
    updatedAt: resume.updatedAt,
  };
}

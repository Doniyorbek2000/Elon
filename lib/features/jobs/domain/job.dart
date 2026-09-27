import 'package:flutter/foundation.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/domain/media_image.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/place.dart';
import '../../../core/domain/promotion.dart';
import '../../../core/domain/public_profile.dart';

/// "Masofaviy" is a work format on the server (`workFormat=remote`); it is
/// kept here as a filter chip because users search for it like a job type.
enum EmploymentType {
  fullTime('To‘liq stavka', 'fullTime'),
  partTime('Yarim stavka', 'partTime'),
  remote('Masofaviy', 'fullTime'),
  temporary('Vaqtinchalik', 'temporary'),
  internship('Amaliyot', 'internship');

  const EmploymentType(this.label, this.apiValue);

  final String label;

  /// Server `employmentType`.
  final String apiValue;

  static EmploymentType fromApi(Object? employmentType, Object? workFormat) {
    if (workFormat == 'remote') return EmploymentType.remote;
    return values.firstWhere(
      (t) => t != remote && t.apiValue == employmentType,
      orElse: () => fullTime,
    );
  }
}

enum ExperienceLevel {
  none('Tajribasiz', 'none'),
  upToOne('1 yilgacha', 'upTo1'),
  oneToThree('1–3 yil', 'oneTo3'),
  threePlus('3 yildan ortiq', 'threePlus');

  const ExperienceLevel(this.label, this.apiValue);

  final String label;
  final String apiValue;

  static ExperienceLevel fromApi(Object? value) => values.firstWhere(
    (level) => level.apiValue == value,
    orElse: () => ExperienceLevel.none,
  );
}

/// Vacancy lifecycle on the server.
enum JobStatus {
  draft('Qoralama'),
  active('Faol'),
  paused('To‘xtatilgan'),
  filled('Yopilgan'),
  expired('Muddati tugagan'),
  rejected('Rad etilgan'),
  archived('Arxivda');

  const JobStatus(this.label);

  final String label;

  static JobStatus parse(Object? value) =>
      values.firstWhere((s) => s.name == value, orElse: () => JobStatus.active);
}

@immutable
class Company {
  const Company({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.tone,
    this.logo,
    this.verification = VerificationLevel.none,
    this.about,
  });

  final String id;
  final String name;
  final String iconKey;
  final AccentTone tone;
  final MediaImage? logo;
  final VerificationLevel verification;
  final String? about;
}

@immutable
class Job {
  const Job({
    required this.id,
    required this.title,
    required this.company,
    required this.place,
    required this.publishedAt,
    required this.employmentType,
    required this.experience,
    required this.description,
    required this.requirements,
    required this.workingHours,
    required this.employer,
    this.salaryMin,
    this.salaryMax,
    this.currency = Currency.uzs,
    this.responsibilities = const [],
    this.promotion,
    this.views = 0,
    this.status = JobStatus.active,
    this.applicationCount,
    this.shareUrl,
  });

  final String id;
  final String title;
  final Company company;
  final Place place;
  final DateTime publishedAt;
  final EmploymentType employmentType;
  final ExperienceLevel experience;
  final String description;
  final List<String> requirements;
  final List<String> responsibilities;
  final String workingHours;

  /// Person to contact on the employer side.
  final PublicProfile employer;
  final int? salaryMin;
  final int? salaryMax;
  final Currency currency;
  final Promotion? promotion;
  final int views;
  final JobStatus status;

  /// Number of applicants; only present for the vacancy owner.
  final int? applicationCount;
  final String? shareUrl;

  /// Best comparable salary for sorting.
  int get salarySortKey => salaryMax ?? salaryMin ?? 0;

  bool isNew(DateTime now) => now.difference(publishedAt).inHours < 24;
}

/// "Ishchi qidiraman" side: a public candidate résumé.
@immutable
class CandidateProfile {
  const CandidateProfile({
    required this.id,
    required this.profile,
    required this.desiredPosition,
    required this.experienceYears,
    required this.place,
    required this.skills,
    required this.about,
    required this.updatedAt,
    required this.employmentTypes,
    this.expectedSalary,
    this.visibility = ResumeVisibility.public,
  });

  final String id;
  final PublicProfile profile;
  final String desiredPosition;
  final int experienceYears;
  final Place place;
  final List<String> skills;
  final String about;
  final DateTime updatedAt;
  final Set<EmploymentType> employmentTypes;
  final Money? expectedSalary;
  final ResumeVisibility visibility;
}

/// Server application lifecycle. Employers move submitted → viewed →
/// shortlisted → accepted/rejected; applicants may withdraw while open.
enum ApplicationStatus {
  submitted('Yuborildi'),
  viewed('Ko‘rildi'),
  shortlisted('Suhbatga taklif'),
  accepted('Qabul qilindi'),
  rejected('Rad etildi'),
  withdrawn('Qaytarib olindi');

  const ApplicationStatus(this.label);

  final String label;

  bool get isOpen => this == submitted || this == viewed || this == shortlisted;

  static ApplicationStatus parse(Object? value) => values.firstWhere(
    (s) => s.name == value,
    orElse: () => ApplicationStatus.submitted,
  );
}

@immutable
class JobApplication {
  const JobApplication({
    required this.id,
    required this.job,
    required this.appliedAt,
    required this.status,
    this.message,
  });

  final String id;
  final Job job;
  final DateTime appliedAt;
  final ApplicationStatus status;
  final String? message;
}

/// An application as the employer sees it (with contact data and CV).
@immutable
class Applicant {
  const Applicant({
    required this.applicationId,
    required this.profile,
    required this.status,
    required this.appliedAt,
    this.message,
    this.phone,
    this.resume,
  });

  final String applicationId;
  final PublicProfile profile;
  final ApplicationStatus status;
  final DateTime appliedAt;
  final String? message;

  /// Shared with the employer because the candidate applied.
  final String? phone;

  /// Null when the candidate hid their CV.
  final CandidateProfile? resume;
}

enum ResumeVisibility {
  public('Hammaga ko‘rinadi'),
  applicationsOnly('Faqat ariza yuborgan ish beruvchilarga'),
  hidden('Yashirin');

  const ResumeVisibility(this.label);

  final String label;
}

/// Editable CV of the signed-in user ("Ish qidiraman").
@immutable
class ResumeDraft {
  const ResumeDraft({
    required this.title,
    this.about = '',
    this.experienceYears = 0,
    this.skills = const [],
    this.employmentTypes = const {},
    this.regionId,
    this.districtId,
    this.salaryExpectation,
    this.visibility = ResumeVisibility.public,
  });

  final String title;
  final String about;
  final int experienceYears;
  final List<String> skills;
  final Set<EmploymentType> employmentTypes;
  final String? regionId;
  final String? districtId;
  final int? salaryExpectation;
  final ResumeVisibility visibility;

  Map<String, dynamic> toJson() => {
    'title': title,
    'about': about,
    'experienceYears': experienceYears,
    'skills': skills,
    'employmentTypes': {for (final type in employmentTypes) type.apiValue}
        .toList(),
    'preferredRegionId': regionId,
    'preferredDistrictId': districtId,
    'salaryExpectation': salaryExpectation,
    'salaryCurrency': 'uzs',
    'visibility': visibility.name,
  };
}

@immutable
class JobQuery {
  const JobQuery({
    this.text = '',
    this.types = const {},
    this.experience,
    this.minSalary,
    this.regionId,
    this.districtId,
    this.sortBySalary = false,
  });

  final String text;
  final Set<EmploymentType> types;
  final ExperienceLevel? experience;
  final int? minSalary;
  final String? regionId;
  final String? districtId;
  final bool sortBySalary;

  int get activeFilterCount => [
    types.isNotEmpty,
    experience != null,
    minSalary != null,
    sortBySalary,
  ].where((a) => a).length;

  JobQuery copyWith({
    String? text,
    Set<EmploymentType>? types,
    ExperienceLevel? Function()? experience,
    int? Function()? minSalary,
    String? Function()? regionId,
    String? Function()? districtId,
    bool? sortBySalary,
  }) => JobQuery(
    text: text ?? this.text,
    types: types ?? this.types,
    experience: experience != null ? experience() : this.experience,
    minSalary: minSalary != null ? minSalary() : this.minSalary,
    regionId: regionId != null ? regionId() : this.regionId,
    districtId: districtId != null ? districtId() : this.districtId,
    sortBySalary: sortBySalary ?? this.sortBySalary,
  );

  @override
  bool operator ==(Object other) =>
      other is JobQuery &&
      other.text == text &&
      setEquals(other.types, types) &&
      other.experience == experience &&
      other.minSalary == minSalary &&
      other.regionId == regionId &&
      other.districtId == districtId &&
      other.sortBySalary == sortBySalary;

  @override
  int get hashCode => Object.hash(
    text,
    Object.hashAllUnordered(types),
    experience,
    minSalary,
    regionId,
    districtId,
    sortBySalary,
  );
}

/// Vacancy posted by an employer through the create flow.
@immutable
class NewVacancy {
  const NewVacancy({
    required this.title,
    required this.companyName,
    required this.place,
    required this.employmentType,
    required this.experience,
    required this.description,
    required this.workingHours,
    this.salaryMin,
    this.salaryMax,
  });

  final String title;
  final String companyName;
  final Place place;
  final EmploymentType employmentType;
  final ExperienceLevel experience;
  final String description;
  final String workingHours;
  final int? salaryMin;
  final int? salaryMax;

  /// Body for `POST /jobs` / `PUT /jobs/:id`.
  Map<String, dynamic> toJson() => {
    'title': title,
    'companyName': companyName,
    'description': description,
    'place': {
      'regionId': place.regionId,
      'districtId': ?place.districtId,
      'lat': ?place.latitude,
      'lng': ?place.longitude,
    },
    'employmentType': employmentType.apiValue,
    'workFormat': employmentType == EmploymentType.remote ? 'remote' : 'onSite',
    'experience': experience.apiValue,
    if (workingHours.trim().isNotEmpty) 'workSchedule': workingHours.trim(),
    'salaryMin': ?salaryMin,
    'salaryMax': ?salaryMax,
    'salaryCurrency': 'uzs',
    'applicationMode': 'both',
  };
}

abstract interface class JobRepository {
  Future<Job> postVacancy(
    NewVacancy vacancy, {
    required PublicProfile employer,
  });
  Future<List<Job>> searchJobs(JobQuery query);
  Future<Job> getJob(String id);
  Future<List<CandidateProfile>> searchCandidates(JobQuery query);
  Future<CandidateProfile> getCandidate(String id);
  Future<JobApplication> apply({
    required String jobId,
    required String applicantId,
    String? message,
  });
  Future<List<JobApplication>> myApplications(String applicantId);
  Future<void> withdrawApplication(String applicationId);

  /// Employer side: own vacancies (all statuses), applicants, decisions.
  Future<List<Job>> myJobs();
  Future<void> setJobStatus(String jobId, JobStatus status);
  Future<List<Applicant>> applicants(String jobId);
  Future<void> setApplicationStatus(
    String applicationId,
    ApplicationStatus status,
  );

  /// Signed-in user's CV; null when none was created yet.
  Future<CandidateProfile?> myResume();
  Future<CandidateProfile> saveResume(ResumeDraft draft);

  /// Phone numbers are released on explicit action (rate-limited server-side).
  Future<String> revealJobPhone(String jobId);
  Future<String> revealCandidatePhone(String candidateId);
}

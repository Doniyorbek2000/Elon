import 'package:flutter/foundation.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/domain/media_image.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/place.dart';
import '../../../core/domain/promotion.dart';
import '../../../core/domain/public_profile.dart';

enum EmploymentType {
  fullTime('To‘liq stavka'),
  partTime('Yarim stavka'),
  remote('Masofaviy'),
  temporary('Vaqtinchalik');

  const EmploymentType(this.label);

  final String label;
}

enum ExperienceLevel {
  none('Tajribasiz'),
  upToOne('1 yilgacha'),
  oneToThree('1–3 yil'),
  threePlus('3 yildan ortiq');

  const ExperienceLevel(this.label);

  final String label;
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
}

enum ApplicationStatus {
  sent('Yuborildi'),
  viewed('Ko‘rildi'),
  invited('Suhbatga taklif'),
  rejected('Rad etildi');

  const ApplicationStatus(this.label);

  final String label;
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

  int get activeFilterCount =>
      [types.isNotEmpty, experience != null, minSalary != null, sortBySalary].where((a) => a).length;

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
  int get hashCode =>
      Object.hash(text, Object.hashAllUnordered(types), experience, minSalary, regionId, districtId, sortBySalary);
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

  Map<String, dynamic> toJson() => {
    'title': title,
    'companyName': companyName,
    'place': place.toJson(),
    'employmentType': employmentType.name,
    'experience': experience.name,
    'description': description,
    'workingHours': workingHours,
    'salaryMin': ?salaryMin,
    'salaryMax': ?salaryMax,
  };
}

abstract interface class JobRepository {
  Future<Job> postVacancy(NewVacancy vacancy, {required PublicProfile employer});
  Future<List<Job>> searchJobs(JobQuery query);
  Future<Job> getJob(String id);
  Future<List<CandidateProfile>> searchCandidates(JobQuery query);
  Future<CandidateProfile> getCandidate(String id);
  Future<JobApplication> apply({required String jobId, required String applicantId, String? message});
  Future<List<JobApplication>> myApplications(String applicantId);
  Future<String> revealPhone(String userId);
}

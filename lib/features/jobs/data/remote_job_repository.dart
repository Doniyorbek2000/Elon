import '../../../core/design/app_colors.dart';
import '../../../core/domain/media_image.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/place.dart';
import '../../../core/domain/promotion.dart';
import '../../../core/domain/public_profile.dart';
import '../../../core/network/api_client.dart';
import '../domain/job.dart';

/// REST implementation of [JobRepository] (see docs/backend-contract.md).
class RemoteJobRepository implements JobRepository {
  RemoteJobRepository(this._api);

  final ApiClient _api;

  static T _enum<T extends Enum>(List<T> values, Object? name, T fallback) =>
      values.where((v) => v.name == name).firstOrNull ?? fallback;

  static Company _company(JsonMap json) => Company(
    id: json['id'] as String,
    name: json['name'] as String,
    iconKey: json['iconKey'] as String? ?? 'work',
    tone: _enum(AccentTone.values, json['tone'], AccentTone.blue),
    logo: json['logo'] == null ? null : MediaImage.fromJson(json['logo'] as JsonMap),
    verification: VerificationLevel.parse(json['verification']),
    about: json['about'] as String?,
  );

  static Job jobFromJson(JsonMap json) => Job(
    id: json['id'] as String,
    title: json['title'] as String,
    company: _company(json['company'] as JsonMap),
    place: Place.fromJson(json['place'] as JsonMap),
    publishedAt: DateTime.parse(json['publishedAt'] as String),
    employmentType: _enum(EmploymentType.values, json['employmentType'], EmploymentType.fullTime),
    experience: _enum(ExperienceLevel.values, json['experience'], ExperienceLevel.none),
    description: json['description'] as String? ?? '',
    requirements: [for (final r in json['requirements'] as List<dynamic>? ?? const []) '$r'],
    responsibilities: [for (final r in json['responsibilities'] as List<dynamic>? ?? const []) '$r'],
    workingHours: json['workingHours'] as String? ?? '',
    employer: PublicProfile.fromJson(json['employer'] as JsonMap),
    salaryMin: json['salaryMin'] as int?,
    salaryMax: json['salaryMax'] as int?,
    currency: Currency.parse(json['currency']),
    promotion: switch (PromotionType.parse(json['promotion'])) {
      final PromotionType type => Promotion(type),
      null => null,
    },
    views: json['views'] as int? ?? 0,
  );

  static CandidateProfile candidateFromJson(JsonMap json) => CandidateProfile(
    id: json['id'] as String,
    profile: PublicProfile.fromJson(json['profile'] as JsonMap),
    desiredPosition: json['desiredPosition'] as String,
    experienceYears: json['experienceYears'] as int? ?? 0,
    place: Place.fromJson(json['place'] as JsonMap),
    skills: [for (final s in json['skills'] as List<dynamic>? ?? const []) '$s'],
    about: json['about'] as String? ?? '',
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    employmentTypes: {
      for (final t in json['employmentTypes'] as List<dynamic>? ?? const [])
        _enum(EmploymentType.values, t, EmploymentType.fullTime),
    },
    expectedSalary: json['expectedSalary'] == null ? null : Money.fromJson(json['expectedSalary'] as JsonMap),
  );

  static JobApplication applicationFromJson(JsonMap json) => JobApplication(
    id: json['id'] as String,
    job: jobFromJson(json['job'] as JsonMap),
    appliedAt: DateTime.parse(json['appliedAt'] as String),
    status: _enum(ApplicationStatus.values, json['status'], ApplicationStatus.sent),
    message: json['message'] as String?,
  );

  Map<String, Object?> _query(JobQuery query) => {
    'q': query.text,
    'types': query.types.map((t) => t.name).join(','),
    'experience': query.experience?.name,
    'salaryMin': query.minSalary,
    'region': query.regionId,
    'district': query.districtId,
    'sort': query.sortBySalary ? 'salary' : 'newest',
  };

  @override
  Future<List<Job>> searchJobs(JobQuery query) async => [
    for (final item in (await _api.getJson('/jobs', query: _query(query)))['items'] as List<dynamic>)
      jobFromJson(item as JsonMap),
  ];

  @override
  Future<Job> postVacancy(NewVacancy vacancy, {required PublicProfile employer}) async =>
      jobFromJson(await _api.postJson('/jobs', body: vacancy.toJson()));

  @override
  Future<Job> getJob(String id) async => jobFromJson(await _api.getJson('/jobs/$id'));

  @override
  Future<List<CandidateProfile>> searchCandidates(JobQuery query) async => [
    for (final item in (await _api.getJson('/candidates', query: _query(query)))['items'] as List<dynamic>)
      candidateFromJson(item as JsonMap),
  ];

  @override
  Future<CandidateProfile> getCandidate(String id) async => candidateFromJson(await _api.getJson('/candidates/$id'));

  @override
  Future<JobApplication> apply({required String jobId, required String applicantId, String? message}) async =>
      applicationFromJson(await _api.postJson('/jobs/$jobId/applications', body: {'message': message}));

  @override
  Future<List<JobApplication>> myApplications(String applicantId) async => [
    for (final item in (await _api.getJson('/me/applications'))['items'] as List<dynamic>)
      applicationFromJson(item as JsonMap),
  ];

  @override
  Future<String> revealPhone(String userId) async => (await _api.postJson('/users/$userId/phone'))['phone'] as String;
}

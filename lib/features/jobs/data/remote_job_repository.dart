import '../../../core/design/app_colors.dart';
import '../../../core/domain/media_image.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/place.dart';
import '../../../core/domain/promotion.dart';
import '../../../core/domain/public_profile.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/network/api_client.dart';
import '../domain/job.dart';

/// `/jobs`, `/candidates`, `/applications`, `/me/resume` REST implementation.
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
    employmentType: EmploymentType.fromApi(json['employmentType'], json['workFormat']),
    experience: ExperienceLevel.fromApi(json['experience']),
    description: json['description'] as String? ?? '',
    requirements: [for (final r in json['requirements'] as List<dynamic>? ?? const []) '$r'],
    responsibilities: [for (final r in json['responsibilities'] as List<dynamic>? ?? const []) '$r'],
    workingHours: json['workingHours'] as String? ?? '',
    employer: PublicProfile.fromJson(json['employer'] as JsonMap),
    salaryMin: (json['salaryMin'] as num?)?.toInt(),
    salaryMax: (json['salaryMax'] as num?)?.toInt(),
    currency: Currency.parse(json['currency']),
    promotion: switch (PromotionType.parse(json['promotion'])) {
      final PromotionType type => Promotion(type),
      null => null,
    },
    views: (json['views'] as num?)?.toInt() ?? 0,
    status: JobStatus.parse(json['status']),
    applicationCount: (json['applicationCount'] as num?)?.toInt(),
    shareUrl: json['shareUrl'] as String?,
  );

  /// Résumé places may have no preferred region yet.
  static Place _resumePlace(JsonMap? json) {
    final regionId = json?['regionId'] as String?;
    if (regionId == null) return const Place(regionId: '', regionName: 'Hudud ko‘rsatilmagan');
    return Place(
      regionId: regionId,
      regionName: json?['regionName'] as String? ?? '',
      districtId: json?['districtId'] as String?,
      districtName: json?['districtName'] as String?,
    );
  }

  static CandidateProfile candidateFromJson(JsonMap json) => CandidateProfile(
    id: json['id'] as String,
    profile: PublicProfile.fromJson(json['profile'] as JsonMap),
    desiredPosition: json['desiredPosition'] as String,
    experienceYears: (json['experienceYears'] as num?)?.toInt() ?? 0,
    place: _resumePlace(json['place'] as JsonMap?),
    skills: [for (final s in json['skills'] as List<dynamic>? ?? const []) '$s'],
    about: json['about'] as String? ?? '',
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    employmentTypes: {
      for (final t in json['employmentTypes'] as List<dynamic>? ?? const []) EmploymentType.fromApi(t, null),
    },
    expectedSalary: json['expectedSalary'] == null ? null : Money.fromJson(json['expectedSalary'] as JsonMap),
    visibility: _enum(ResumeVisibility.values, json['visibility'], ResumeVisibility.public),
  );

  static JobApplication applicationFromJson(JsonMap json) => JobApplication(
    id: json['id'] as String,
    job: jobFromJson(json['job'] as JsonMap),
    appliedAt: DateTime.parse(json['appliedAt'] as String),
    status: ApplicationStatus.parse(json['status']),
    message: json['message'] as String?,
  );

  static Applicant applicantFromJson(JsonMap json) => Applicant(
    applicationId: json['id'] as String,
    profile: PublicProfile.fromJson(json['applicant'] as JsonMap),
    status: ApplicationStatus.parse(json['status']),
    appliedAt: DateTime.parse(json['appliedAt'] as String),
    message: json['message'] as String?,
    phone: json['phone'] as String?,
    resume: json['resume'] == null ? null : candidateFromJson(json['resume'] as JsonMap),
  );

  Map<String, Object?> _query(JobQuery query) {
    final remote = query.types.contains(EmploymentType.remote);
    final types = {
      for (final t in query.types)
        if (t != EmploymentType.remote) t.apiValue,
    };
    return {
      'q': query.text.trim(),
      'types': types.join(','),
      'workFormat': remote ? 'remote' : null,
      'experience': query.experience?.apiValue,
      'salaryMin': query.minSalary,
      'region': query.regionId,
      'district': query.districtId,
      'sort': query.sortBySalary ? 'salary' : 'newest',
      'limit': 50,
    };
  }

  @override
  Future<List<Job>> searchJobs(JobQuery query) async =>
      (await _api.getPage('/jobs', jobFromJson, query: _query(query))).items;

  @override
  Future<Job> postVacancy(NewVacancy vacancy, {required PublicProfile employer}) async =>
      jobFromJson(await _api.post<JsonMap>('/jobs', body: vacancy.toJson()));

  @override
  Future<Job> getJob(String id) async => jobFromJson(await _api.get<JsonMap>('/jobs/$id'));

  @override
  Future<List<CandidateProfile>> searchCandidates(JobQuery query) async {
    final params = _query(query)
      ..removeWhere((key, _) => const {'experience', 'salaryMin', 'sort', 'workFormat'}.contains(key));
    return (await _api.getPage('/candidates', candidateFromJson, query: params)).items;
  }

  @override
  Future<CandidateProfile> getCandidate(String id) async =>
      candidateFromJson(await _api.get<JsonMap>('/candidates/$id'));

  @override
  Future<JobApplication> apply({required String jobId, required String applicantId, String? message}) async {
    final created = await _api.post<JsonMap>(
      '/jobs/$jobId/applications',
      body: {if (message != null && message.trim().isNotEmpty) 'coverLetter': message.trim()},
    );
    // The apply response carries only a job summary; return the full card.
    return JobApplication(
      id: created['id'] as String,
      job: await getJob(jobId),
      appliedAt: DateTime.parse(created['appliedAt'] as String),
      status: ApplicationStatus.parse(created['status']),
      message: created['message'] as String?,
    );
  }

  @override
  Future<List<JobApplication>> myApplications(String applicantId) async =>
      (await _api.getPage('/me/applications', applicationFromJson, query: {'limit': 50})).items;

  @override
  Future<void> withdrawApplication(String applicationId) async {
    await _api.post<Object?>('/applications/$applicationId/withdraw');
  }

  @override
  Future<List<Job>> myJobs() async => (await _api.getPage('/me/jobs', jobFromJson, query: {'limit': 50})).items;

  @override
  Future<void> setJobStatus(String jobId, JobStatus status) async {
    await _api.post<Object?>('/jobs/$jobId/status', body: {'status': status.name});
  }

  @override
  Future<List<Applicant>> applicants(String jobId) async =>
      (await _api.getPage('/jobs/$jobId/applications', applicantFromJson, query: {'limit': 50})).items;

  @override
  Future<void> setApplicationStatus(String applicationId, ApplicationStatus status) async {
    await _api.patch<Object?>('/applications/$applicationId/status', body: {'status': status.name});
  }

  @override
  Future<CandidateProfile?> myResume() async {
    try {
      final json = await _api.get<Object?>('/me/resume');
      return json is JsonMap ? candidateFromJson(json) : null;
    } on NotFoundFailure {
      return null;
    }
  }

  @override
  Future<CandidateProfile> saveResume(ResumeDraft draft) async =>
      candidateFromJson(await _api.put<JsonMap>('/me/resume', body: draft.toJson()));

  @override
  Future<String> revealJobPhone(String jobId) async =>
      (await _api.post<JsonMap>('/jobs/$jobId/contact'))['phone'] as String;

  @override
  Future<String> revealCandidatePhone(String candidateId) async =>
      (await _api.post<JsonMap>('/candidates/$candidateId/contact'))['phone'] as String;
}

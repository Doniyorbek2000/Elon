import '../../../core/design/app_colors.dart';
import '../../../core/domain/place.dart';
import '../../../core/domain/public_profile.dart';
import '../../../core/errors/app_failure.dart';
import '../../../data/demo/demo_database.dart';
import '../../search/domain/search_normalizer.dart';
import '../domain/job.dart';

class DemoJobRepository implements JobRepository {
  DemoJobRepository(this._db, {required this._clock});

  final DemoDatabase _db;
  final DateTime Function() _clock;

  bool _inArea(String regionId, String? districtId, JobQuery query) {
    if (query.regionId != null && regionId != query.regionId) return false;
    if (query.districtId != null && districtId != query.districtId)
      return false;
    return true;
  }

  @override
  Future<List<Job>> searchJobs(JobQuery query) async {
    await _db.roundTrip();
    final tokens = SearchNormalizer.tokens(query.text);
    final now = _clock();
    final results = _db.jobs.where((job) {
      if (query.types.isNotEmpty && !query.types.contains(job.employmentType))
        return false;
      if (query.experience != null && job.experience != query.experience)
        return false;
      if (query.minSalary != null && job.salarySortKey < query.minSalary!)
        return false;
      if (!_inArea(job.place.regionId, job.place.districtId, query))
        return false;
      return SearchNormalizer.matches(
        tokens,
        '${job.title} ${job.company.name} ${job.description}',
      );
    }).toList();
    int promoted(Job j) => j.promotion?.isActive(now) ?? false ? 1 : 0;
    results.sort((a, b) {
      if (query.sortBySalary) return b.salarySortKey.compareTo(a.salarySortKey);
      final byPromotion = promoted(b).compareTo(promoted(a));
      return byPromotion != 0
          ? byPromotion
          : b.publishedAt.compareTo(a.publishedAt);
    });
    return results;
  }

  @override
  Future<Job> postVacancy(
    NewVacancy vacancy, {
    required PublicProfile employer,
  }) async {
    await _db.roundTrip(2);
    final job = Job(
      id: _db.nextId('j'),
      title: vacancy.title,
      company: Company(
        id: _db.nextId('c'),
        name: vacancy.companyName,
        iconKey: 'work',
        tone: AccentTone.teal,
      ),
      place: vacancy.place,
      publishedAt: _clock(),
      employmentType: vacancy.employmentType,
      experience: vacancy.experience,
      description: vacancy.description,
      requirements: const [],
      workingHours: vacancy.workingHours,
      employer: employer,
      salaryMin: vacancy.salaryMin,
      salaryMax: vacancy.salaryMax,
    );
    _db.jobs.insert(0, job);
    return job;
  }

  @override
  Future<Job> getJob(String id) async {
    await _db.roundTrip(0.6);
    return _db.jobs.where((j) => j.id == id).firstOrNull ??
        (throw const NotFoundFailure('Vakansiya topilmadi'));
  }

  @override
  Future<List<CandidateProfile>> searchCandidates(JobQuery query) async {
    await _db.roundTrip();
    final tokens = SearchNormalizer.tokens(query.text);
    return _db.candidates.where((candidate) {
      if (query.types.isNotEmpty &&
          candidate.employmentTypes.intersection(query.types).isEmpty)
        return false;
      if (!_inArea(candidate.place.regionId, candidate.place.districtId, query))
        return false;
      return SearchNormalizer.matches(
        tokens,
        '${candidate.desiredPosition} ${candidate.skills.join(' ')}',
      );
    }).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  @override
  Future<CandidateProfile> getCandidate(String id) async {
    await _db.roundTrip(0.6);
    return _db.candidates.where((c) => c.id == id).firstOrNull ??
        (throw const NotFoundFailure('Rezyume topilmadi'));
  }

  @override
  Future<JobApplication> apply({
    required String jobId,
    required String applicantId,
    String? message,
  }) async {
    await _db.roundTrip(1.5);
    if (_db.applications.any((a) => a.job.id == jobId)) {
      throw const ValidationFailure(
        'Siz bu vakansiyaga allaqachon ariza topshirgansiz',
      );
    }
    final application = JobApplication(
      id: _db.nextId('app'),
      job: await getJob(jobId),
      appliedAt: _clock(),
      status: ApplicationStatus.submitted,
      message: message,
    );
    _db.applications.insert(0, application);
    return application;
  }

  @override
  Future<List<JobApplication>> myApplications(String applicantId) async {
    await _db.roundTrip(0.6);
    return List.unmodifiable(_db.applications);
  }

  Future<String> _phoneOf(String userId) async {
    await _db.roundTrip(0.4);
    return _db.seed.phoneBook[userId] ??
        (throw const NotFoundFailure('Raqam yashirilgan. Chat orqali yozing.'));
  }

  @override
  Future<String> revealJobPhone(String jobId) async =>
      _phoneOf((await getJob(jobId)).employer.id);

  @override
  Future<String> revealCandidatePhone(String candidateId) async =>
      _phoneOf((await getCandidate(candidateId)).profile.id);

  @override
  Future<void> withdrawApplication(String applicationId) async {
    await _db.roundTrip(0.6);
    final index = _db.applications.indexWhere((a) => a.id == applicationId);
    if (index < 0) throw const NotFoundFailure();
    final current = _db.applications[index];
    _db.applications[index] = JobApplication(
      id: current.id,
      job: current.job,
      appliedAt: current.appliedAt,
      status: ApplicationStatus.withdrawn,
      message: current.message,
    );
  }

  @override
  Future<List<Job>> myJobs() async {
    await _db.roundTrip(0.6);
    final user = _db.currentUser;
    if (user == null) throw const UnauthorizedFailure();
    return _db.jobs.where((j) => j.employer.id == user.id).toList();
  }

  @override
  Future<void> setJobStatus(String jobId, JobStatus status) async {
    await _db.roundTrip(0.6);
    final user = _db.currentUser;
    final index = _db.jobs.indexWhere(
      (j) => j.id == jobId && j.employer.id == user?.id,
    );
    if (index < 0) throw const NotFoundFailure('Vakansiya topilmadi');
    final job = _db.jobs[index];
    _db.jobs[index] = Job(
      id: job.id,
      title: job.title,
      company: job.company,
      place: job.place,
      publishedAt: job.publishedAt,
      employmentType: job.employmentType,
      experience: job.experience,
      description: job.description,
      requirements: job.requirements,
      responsibilities: job.responsibilities,
      workingHours: job.workingHours,
      employer: job.employer,
      salaryMin: job.salaryMin,
      salaryMax: job.salaryMax,
      currency: job.currency,
      promotion: job.promotion,
      views: job.views,
      status: status,
    );
  }

  /// Demo data has no third-party applicants to the user's own vacancies.
  @override
  Future<List<Applicant>> applicants(String jobId) async {
    await _db.roundTrip(0.6);
    return const [];
  }

  @override
  Future<void> setApplicationStatus(
    String applicationId,
    ApplicationStatus status,
  ) async {
    await _db.roundTrip(0.4);
    throw const NotFoundFailure('Ariza topilmadi');
  }

  CandidateProfile? _resume;

  @override
  Future<CandidateProfile?> myResume() async {
    await _db.roundTrip(0.4);
    return _resume;
  }

  @override
  Future<CandidateProfile> saveResume(ResumeDraft draft) async {
    await _db.roundTrip();
    final user = _db.currentUser;
    if (user == null) throw const UnauthorizedFailure();
    final resume = CandidateProfile(
      id: _resume?.id ?? _db.nextId('cv'),
      profile: user.toPublic(),
      desiredPosition: draft.title,
      experienceYears: draft.experienceYears,
      place: const Place(regionId: 'namangan', regionName: 'Namangan viloyati'),
      skills: draft.skills,
      about: draft.about,
      updatedAt: _clock(),
      employmentTypes: draft.employmentTypes,
      visibility: draft.visibility,
    );
    _resume = resume;
    return resume;
  }
}

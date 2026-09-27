/// Every navigable location in one place. Content paths (`/listing/:id`,
/// `/job/:id`, `/provider/:id`, `/seller/:id`) double as public deep links.
abstract final class AppRoutes {
  static const welcome = '/welcome';
  static const home = '/';
  static const search = '/search';
  static const chats = '/chats';
  static const profile = '/profile';
  static const create = '/create';
  static const categories = '/categories';
  static const listings = '/listings';
  static const jobs = '/jobs';
  static const services = '/services';
  static const location = '/location';
  static const notifications = '/notifications';
  static const verifyPhone = '/verify-phone';
  static const myListings = '/account/listings';
  static const saved = '/account/saved';
  static const applications = '/account/applications';
  static const settings = '/account/settings';
  static const blockedUsers = '/account/settings/blocked';
  static const help = '/account/help';
  static const plans = '/account/plans';
  static const editProfile = '/account/edit';
  static const resume = '/account/resume';
  static const providerEditor = '/account/provider';
  static const employerJobs = '/employer/jobs';

  static String listing(String id) => '/listing/$id';
  static String job(String id) => '/job/$id';
  static String candidate(String id) => '/candidate/$id';
  static String provider(String id) => '/provider/$id';
  static String seller(String id) => '/seller/$id';
  static String chat(String id) => '/chat/$id';
  static String serviceCategory(String id) => '/services/category/$id';
  static String applicants(String jobId) => '/employer/jobs/$jobId/applicants';

  static String listingsFor({String? categoryId, String? sort, String? text}) =>
      Uri(path: listings, queryParameters: {'category': ?categoryId, 'sort': ?sort, 'q': ?text}).toString();

  static String searchFor(String query) => Uri(path: search, queryParameters: {'q': query}).toString();

  static String createIn(String categoryId) => Uri(path: create, queryParameters: {'category': categoryId}).toString();

  static String verifyThen(String next) => Uri(path: verifyPhone, queryParameters: {'next': next}).toString();

  static String locationPicker({bool onboarding = false}) =>
      onboarding ? Uri(path: location, queryParameters: {'onboarding': '1'}).toString() : location;

  static String jobsFor({bool hiring = false}) =>
      hiring ? Uri(path: jobs, queryParameters: {'mode': 'hire'}).toString() : jobs;

  /// Routes that require a signed-in account.
  static const protectedPrefixes = [
    create,
    myListings,
    applications,
    editProfile,
    resume,
    providerEditor,
    '/employer/',
    '/chat/',
  ];
}

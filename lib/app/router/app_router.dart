import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/state_views.dart';
import '../../features/auth/application/session_controller.dart';
import '../../features/auth/presentation/phone_verification_screen.dart';
import '../../features/catalog/presentation/categories_screen.dart';
import '../../features/chat/presentation/chat_list_screen.dart';
import '../../features/chat/presentation/conversation_screen.dart';
import '../../features/create_listing/presentation/create_listing_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/jobs/presentation/candidate_detail_screen.dart';
import '../../features/jobs/presentation/job_detail_screen.dart';
import '../../features/jobs/presentation/jobs_screen.dart';
import '../../features/listings/domain/listing_query.dart';
import '../../features/listings/presentation/listing_detail_screen.dart';
import '../../features/listings/presentation/listings_screen.dart';
import '../../features/location/presentation/location_picker_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/profile/presentation/account_screens.dart';
import '../../features/profile/presentation/my_listings_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/saved_screen.dart';
import '../../features/profile/presentation/seller_profile_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/services/presentation/provider_profile_screen.dart';
import '../../features/services/presentation/services_screen.dart';
import '../../features/settings/application/settings_controller.dart';
import '../shell/app_shell.dart';
import 'routes.dart';

/// Router is created once; auth/onboarding changes trigger `refresh`
/// instead of rebuilding the router (which would reset navigation).
final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref
    ..listen(onboardingCompletedProvider, (_, _) => refresh.value++)
    ..listen(sessionProvider, (_, _) => refresh.value++)
    ..onDispose(refresh.dispose);

  final router = GoRouter(
    navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'root'),
    initialLocation: AppRoutes.home,
    refreshListenable: refresh,
    redirect: (context, state) {
      final path = state.uri.path;
      final onboarded = ref.read(onboardingCompletedProvider);
      // Only the landing route is gated: a shared deep link opens its content
      // immediately even on first launch.
      if (!onboarded && path == AppRoutes.home) return AppRoutes.welcome;
      if (onboarded && path == AppRoutes.welcome) return AppRoutes.home;

      final signedIn = ref.read(sessionProvider) != null;
      final needsAuth = AppRoutes.protectedPrefixes.any(path.startsWith);
      if (needsAuth && !signedIn)
        return AppRoutes.verifyThen(state.uri.toString());
      return null;
    },
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(),
      body: EmptyState(
        icon: Icons.link_off_rounded,
        title: 'Sahifa topilmadi',
        message: 'Havola eskirgan yoki noto‘g‘ri bo‘lishi mumkin.',
        actionLabel: 'Bosh sahifaga',
        onAction: () => context.go(AppRoutes.home),
      ),
    ),
    routes: [
      GoRoute(
        path: AppRoutes.welcome,
        builder: (_, _) => const OnboardingScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (_, _) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.search,
                builder: (_, state) =>
                    SearchScreen(initialQuery: state.uri.queryParameters['q']),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.chats,
                builder: (_, _) => const ChatListScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                builder: (_, _) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.create,
        pageBuilder: (_, state) => MaterialPage(
          fullscreenDialog: true,
          child: CreateListingScreen(
            initialCategoryId: state.uri.queryParameters['category'],
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.categories,
        builder: (_, _) => const CategoriesScreen(),
      ),
      GoRoute(
        path: AppRoutes.listings,
        builder: (_, state) {
          final params = state.uri.queryParameters;
          return ListingsScreen(
            categoryId: params['category'],
            initialText: params['q'] ?? '',
            initialSort:
                ListingSort.values
                    .where((s) => s.name == params['sort'])
                    .firstOrNull ??
                ListingSort.newest,
          );
        },
      ),
      GoRoute(
        path: '/listing/:id',
        builder: (_, state) => ListingDetailScreen(
          listingId: state.pathParameters['id']!,
          heroPrefix: state.extra is String ? state.extra! as String : null,
        ),
      ),
      GoRoute(
        path: AppRoutes.jobs,
        builder: (_, state) => JobsScreen(
          initialHiring: state.uri.queryParameters['mode'] == 'hire',
        ),
      ),
      GoRoute(
        path: '/job/:id',
        builder: (_, state) =>
            JobDetailScreen(jobId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/candidate/:id',
        builder: (_, state) =>
            CandidateDetailScreen(candidateId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.services,
        builder: (_, _) => const ServicesScreen(),
        routes: [
          GoRoute(
            path: 'category/:id',
            builder: (_, state) =>
                ServiceCategoryScreen(categoryId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: '/provider/:id',
        builder: (_, state) =>
            ProviderProfileScreen(providerId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/seller/:id',
        builder: (_, state) =>
            SellerProfileScreen(userId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/chat/:id',
        builder: (_, state) =>
            ConversationScreen(conversationId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.location,
        builder: (_, state) => LocationPickerScreen(
          onboarding: state.uri.queryParameters['onboarding'] == '1',
          pickOnly: state.uri.queryParameters['pick'] == '1',
        ),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (_, _) => const NotificationsScreen(),
      ),
      GoRoute(
        path: AppRoutes.verifyPhone,
        builder: (_, state) =>
            PhoneVerificationScreen(next: state.uri.queryParameters['next']),
      ),
      GoRoute(
        path: AppRoutes.myListings,
        builder: (_, _) => const MyListingsScreen(),
      ),
      GoRoute(path: AppRoutes.saved, builder: (_, _) => const SavedScreen()),
      GoRoute(
        path: AppRoutes.applications,
        builder: (_, _) => const MyApplicationsScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, _) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.blockedUsers,
        builder: (_, _) => const BlockedUsersScreen(),
      ),
      GoRoute(path: AppRoutes.help, builder: (_, _) => const HelpScreen()),
      GoRoute(path: AppRoutes.plans, builder: (_, _) => const PlansScreen()),
      GoRoute(
        path: AppRoutes.editProfile,
        builder: (_, _) => const EditProfileScreen(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

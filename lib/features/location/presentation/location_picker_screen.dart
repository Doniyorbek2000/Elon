import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/widgets/app_search_field.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/state_views.dart';
import '../../listings/domain/listing_query.dart';
import '../../search/domain/search_normalizer.dart';
import '../application/location_controller.dart';
import '../domain/location.dart';

/// Region → district → locality picker with GPS shortcut and radius.
///
/// Modes: default (sets the app-wide location and pops), [onboarding]
/// (continues to home, skippable) and [pickOnly] (returns a selection
/// without changing the app-wide location — used by the create flow).
class LocationPickerScreen extends ConsumerStatefulWidget {
  const LocationPickerScreen({super.key, this.onboarding = false, this.pickOnly = false});

  final bool onboarding;
  final bool pickOnly;

  @override
  ConsumerState<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

enum _GpsState { idle, locating, failed }

class _LocationPickerScreenState extends ConsumerState<LocationPickerScreen> {
  final _search = TextEditingController();
  String _query = '';
  Region? _region;
  District? _district;
  _GpsState _gps = _GpsState.idle;
  AppFailure? _gpsError;
  late int? _radius = ref.read(locationProvider).radiusKm;

  @override
  void initState() {
    super.initState();
    final current = ref.read(locationProvider);
    final tree = ref.read(locationTreeProvider);
    _region = tree.region(current.regionId);
    _district = null;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _finish(LocationSelection selection) async {
    unawaited(HapticFeedback.selectionClick());
    final withRadius = widget.pickOnly ? selection : selection.withRadius(_radius);
    if (widget.pickOnly) {
      context.pop(withRadius);
      return;
    }
    await ref.read(locationProvider.notifier).select(withRadius);
    if (!mounted) return;
    if (widget.onboarding) {
      context.go(AppRoutes.home);
    } else {
      context.pop();
    }
  }

  Future<void> _useGps() async {
    setState(() {
      _gps = _GpsState.locating;
      _gpsError = null;
    });
    try {
      final controller = ref.read(locationProvider.notifier);
      if (widget.pickOnly) {
        final point = await ref.read(deviceLocationServiceProvider).currentPosition();
        final nearest = ref.read(locationTreeProvider).nearestDistrict(point);
        if (nearest == null) throw const PermissionFailure('Hudud aniqlanmadi');
        await _finish(
          LocationSelection(
            regionId: nearest.region.id,
            regionName: nearest.region.name,
            districtId: nearest.district.id,
            districtName: nearest.district.name,
            point: point,
            fromDevice: true,
          ),
        );
        return;
      }
      final selection = await controller.useDeviceLocation();
      if (_radius != selection.radiusKm) await controller.setRadius(_radius);
      if (!mounted) return;
      showAppSnack(context, 'Joylashuv: ${selection.label}', icon: Icons.my_location_rounded);
      if (widget.onboarding) {
        context.go(AppRoutes.home);
      } else {
        context.pop();
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _gps = _GpsState.failed;
        _gpsError = error is AppFailure ? error : const PermissionFailure('Joylashuvni aniqlab bo‘lmadi');
      });
    }
  }

  LocationSelection _selection(Region region, [District? district, Locality? locality]) => LocationSelection(
    regionId: region.id,
    regionName: region.name,
    districtId: district?.id,
    districtName: district?.name,
    localityId: locality?.id,
    localityName: locality?.name,
  );

  @override
  Widget build(BuildContext context) {
    final tree = ref.watch(locationTreeProvider);
    final current = ref.watch(locationProvider);
    final palette = context.palette;
    final text = Theme.of(context).textTheme;

    return PopScope(
      canPop: _district == null || _query.isNotEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _district = null);
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.onboarding,
          title: Text(widget.onboarding ? 'Hududingizni tanlang' : 'Manzil tanlash'),
          actions: [
            if (widget.onboarding)
              TextButton(onPressed: () => context.go(AppRoutes.home), child: const Text('O‘tkazib yuborish')),
          ],
        ),
        body: ContentWidth(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
                child: AppSearchField(
                  controller: _search,
                  hint: 'Viloyat, tuman yoki mahalla...',
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Expanded(
                child: _query.trim().isNotEmpty
                    ? _SearchResults(query: _query, tree: tree, onSelect: _finish)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.md,
                          AppSpacing.lg,
                          AppSpacing.xxxl,
                        ),
                        children: [
                          _GpsCard(
                            state: _gps,
                            error: _gpsError,
                            onTap: _useGps,
                            onOpenSettings: () {
                              ref.read(deviceLocationServiceProvider).openSettings();
                            },
                          ),
                          if (!widget.pickOnly) ...[
                            const SizedBox(height: AppSpacing.xl),
                            Text('Qidiruv radiusi', style: text.titleSmall),
                            const SizedBox(height: AppSpacing.sm),
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.sm,
                              children: [
                                for (final km in <int?>[null, ...listingRadiusOptionsKm])
                                  ChoiceChip(
                                    label: Text(km == null ? 'Butun hudud' : '$km km'),
                                    selected: _radius == km,
                                    labelStyle: text.labelMedium?.copyWith(
                                      color: _radius == km ? palette.onPrimary : palette.textPrimary,
                                    ),
                                    onSelected: (_) => setState(() => _radius = km),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: AppSpacing.xl),
                          _Breadcrumbs(
                            region: _region,
                            district: _district,
                            onRoot: () => setState(() {
                              _region = null;
                              _district = null;
                            }),
                            onRegion: () => setState(() => _district = null),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          SurfaceCard(
                            padding: EdgeInsets.zero,
                            child: Column(children: _levelTiles(tree, current)),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _levelTiles(LocationTree tree, LocationSelection current) {
    final region = _region;
    final district = _district;
    if (region == null) {
      return [
        for (final r in tree.regions)
          _LevelTile(
            title: r.name,
            selected: current.regionId == r.id,
            hasChildren: r.districts.isNotEmpty,
            onTap: () => setState(() => _region = r),
          ),
      ];
    }
    if (district == null) {
      return [
        _LevelTile(
          title: 'Butun ${region.name.toLowerCase().replaceAll(' viloyati', ' viloyati bo‘ylab')}',
          icon: Icons.select_all_rounded,
          selected: current.regionId == region.id && current.districtId == null,
          onTap: () => _finish(_selection(region)),
        ),
        for (final d in region.districts)
          _LevelTile(
            title: d.name,
            selected: current.districtId == d.id && current.localityId == null,
            hasChildren: d.localities.isNotEmpty,
            onTap: d.localities.isEmpty ? () => _finish(_selection(region, d)) : () => setState(() => _district = d),
          ),
      ];
    }
    return [
      _LevelTile(
        title: 'Butun ${district.name}',
        icon: Icons.select_all_rounded,
        selected: current.districtId == district.id && current.localityId == null,
        onTap: () => _finish(_selection(region, district)),
      ),
      for (final l in district.localities)
        _LevelTile(
          title: l.name,
          selected: current.localityId == l.id,
          onTap: () => _finish(_selection(region, district, l)),
        ),
    ];
  }
}

class _GpsCard extends StatelessWidget {
  const _GpsCard({required this.state, required this.error, required this.onTap, required this.onOpenSettings});

  final _GpsState state;
  final AppFailure? error;
  final VoidCallback onTap;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    final permanentlyDenied = error is PermissionFailure && (error! as PermissionFailure).permanentlyDenied;
    return SurfaceCard(
      color: palette.primarySoft,
      borderColor: Colors.transparent,
      onTap: state == _GpsState.locating ? null : onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: palette.primary, shape: BoxShape.circle),
                child: state == _GpsState.locating
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                      )
                    : const Icon(Icons.my_location_rounded, color: Colors.white),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state == _GpsState.locating ? 'Aniqlanmoqda…' : 'Joriy joylashuvni aniqlash',
                      style: text.titleSmall?.copyWith(color: palette.primary),
                    ),
                    const SizedBox(height: 2),
                    Text('Aniq manzil saqlanmaydi — faqat tuman aniqlanadi', style: text.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(error!.message, style: text.bodySmall?.copyWith(color: palette.danger)),
            if (permanentlyDenied)
              TextButton(onPressed: onOpenSettings, child: const Text('Sozlamalarni ochish'))
            else
              Text('Yoki quyidagi ro‘yxatdan qo‘lda tanlang.', style: text.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.region, required this.district, required this.onRoot, required this.onRegion});

  final Region? region;
  final District? district;
  final VoidCallback onRoot;
  final VoidCallback onRegion;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    Widget crumb(String label, VoidCallback? onTap, {bool active = false}) => InkWell(
      borderRadius: AppRadii.smAll,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.xs),
        child: Text(label, style: text.labelMedium?.copyWith(color: active ? palette.textPrimary : palette.primary)),
      ),
    );
    final separator = Icon(Icons.chevron_right_rounded, size: AppIconSize.sm, color: palette.textTertiary);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        crumb('O‘zbekiston', region == null ? null : onRoot, active: region == null),
        if (region != null) ...[
          separator,
          crumb(region!.name, district == null ? null : onRegion, active: district == null),
        ],
        if (district != null) ...[separator, crumb(district!.name, null, active: true)],
      ],
    );
  }
}

class _LevelTile extends StatelessWidget {
  const _LevelTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.hasChildren = false,
    this.icon,
  });

  final String title;
  final bool selected;
  final bool hasChildren;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      selected: selected,
      child: ListTile(
        onTap: onTap,
        leading: icon != null
            ? Icon(icon, color: palette.primary)
            : Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: selected ? palette.primary : palette.borderStrong,
              ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: icon != null ? palette.primary : null,
          ),
        ),
        trailing: hasChildren
            ? Icon(Icons.chevron_right_rounded, color: palette.textTertiary)
            : (selected ? Icon(Icons.check_circle_rounded, color: palette.primary) : null),
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.query, required this.tree, required this.onSelect});

  final String query;
  final LocationTree tree;
  final ValueChanged<LocationSelection> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = SearchNormalizer.tokens(query);
    final results = <(String, String, LocationSelection)>[];
    for (final region in tree.regions) {
      final regionSelection = LocationSelection(regionId: region.id, regionName: region.name);
      if (SearchNormalizer.matches(tokens, region.name)) results.add((region.name, 'O‘zbekiston', regionSelection));
      for (final district in region.districts) {
        final districtSelection = LocationSelection(
          regionId: region.id,
          regionName: region.name,
          districtId: district.id,
          districtName: district.name,
        );
        if (SearchNormalizer.matches(tokens, district.name)) {
          results.add((district.name, region.name, districtSelection));
        }
        for (final locality in district.localities) {
          if (SearchNormalizer.matches(tokens, locality.name)) {
            results.add((
              locality.name,
              '${district.name}, ${region.name}',
              LocationSelection(
                regionId: region.id,
                regionName: region.name,
                districtId: district.id,
                districtName: district.name,
                localityId: locality.id,
                localityName: locality.name,
              ),
            ));
          }
        }
      }
    }
    if (results.isEmpty) {
      return const EmptyState(
        icon: Icons.location_off_outlined,
        title: 'Hudud topilmadi',
        message: 'Nomini boshqacha yozib ko‘ring (masalan: Chust, Chortoq).',
        compact: true,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final (title, subtitle, selection) = results[index];
        return ListTile(
          leading: const Icon(Icons.location_on_outlined),
          title: Text(title),
          subtitle: Text(subtitle),
          onTap: () => onSelect(selection),
        );
      },
    );
  }
}

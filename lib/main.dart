import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

const String _vehicleModelAsset = 'assets/models/2024_byd_seal_u_dm-i.glb';
const bool _preferNativeVehicleRenderer = true;
const String _themeModePreferenceKey = 'launcher.themeMode';
const String _vehicleColorPreferenceKey = 'launcher.vehicleColor';
const String _renderQualityPreferenceKey = 'launcher.renderQuality';
const String _navigationDefaultPackagePreferenceKey =
    'launcher.navigation.defaultPackage';
const String _launchNavigationWithLauncherPreferenceKey =
    'launcher.navigation.launchWithLauncher';
const MethodChannel _musicChannel = MethodChannel('byd/music');
const EventChannel _musicEvents = EventChannel('byd/music/events');
const MethodChannel _vehicleChannel = MethodChannel('byd.vehicle');
const EventChannel _vehicleEvents = EventChannel('byd.vehicle/events');
const MethodChannel _navigationChannel = MethodChannel('byd/navigation');
const MethodChannel _navigationVdChannel = MethodChannel('byd/navigation_vd');
const MethodChannel _permissionChannel = MethodChannel('byd/permissions');

const List<_VehiclePaintOption> _vehiclePaintOptions = [
  _VehiclePaintOption('Arctic White', Color(0xFFE9EEF4)),
  _VehiclePaintOption('Harbour Grey', Color(0xFF6F7880)),
  _VehiclePaintOption('Delan Black', Color(0xFF090C12)),
  _VehiclePaintOption('Azure Blue', Color(0xFF1687FF)),
  _VehiclePaintOption('Stone Grey', Color(0xFF9AA0A4)),
  _VehiclePaintOption('Ruby Red', Color(0xFF9D1028)),
];

class _VehicleSnapshot {
  const _VehicleSnapshot({
    this.available = false,
    this.speedKmh,
    this.gear,
    this.rangeKm,
    this.fuelPercent,
    this.batteryPercent,
    this.outsideTemperatureC,
    this.tpms = const {},
  });

  factory _VehicleSnapshot.fromMap(Map<dynamic, dynamic> map) {
    final tpmsMap = map['tpms'];
    return _VehicleSnapshot(
      available: map['available'] == true,
      speedKmh: _doubleFromMap(map, 'speedKmh'),
      gear: _gearFromString(_stringFromMap(map, 'gear')),
      rangeKm: _intFromMapOrNull(map, 'rangeKm'),
      fuelPercent: _intFromMapOrNull(map, 'fuelPercent'),
      batteryPercent: _doubleFromMap(map, 'batteryPercent'),
      outsideTemperatureC: _intFromMapOrNull(map, 'outsideTemperatureC'),
      tpms: tpmsMap is Map
          ? {
              'frontLeft': _TyreSnapshot.fromMap(tpmsMap['frontLeft']),
              'frontRight': _TyreSnapshot.fromMap(tpmsMap['frontRight']),
              'rearLeft': _TyreSnapshot.fromMap(tpmsMap['rearLeft']),
              'rearRight': _TyreSnapshot.fromMap(tpmsMap['rearRight']),
            }
          : const {},
    );
  }

  final bool available;
  final double? speedKmh;
  final _VehicleGear? gear;
  final int? rangeKm;
  final int? fuelPercent;
  final double? batteryPercent;
  final int? outsideTemperatureC;
  final Map<String, _TyreSnapshot> tpms;

  _TyreSnapshot tyre(String key) => tpms[key] ?? const _TyreSnapshot();
}

class _TyreSnapshot {
  const _TyreSnapshot({
    this.pressureBar,
    this.pressureState,
    this.airLeakState,
    this.signalState,
  });

  factory _TyreSnapshot.fromMap(Object? value) {
    if (value is! Map) return const _TyreSnapshot();
    return _TyreSnapshot(
      pressureBar: _doubleFromMap(value, 'pressureBar'),
      pressureState: _intFromMapOrNull(value, 'pressureState'),
      airLeakState: _intFromMapOrNull(value, 'airLeakState'),
      signalState: _intFromMapOrNull(value, 'signalState'),
    );
  }

  final double? pressureBar;
  final int? pressureState;
  final int? airLeakState;
  final int? signalState;

  String get pressureLabel {
    final value = pressureBar;
    if (value == null || value <= 0) return '--';
    return '${value.toStringAsFixed(1)} bar';
  }

  String get stateLabel {
    if (signalState == 1) return 'Signal';
    if (airLeakState == 1 || airLeakState == 2) return 'Leak';
    if (pressureState == 1) return 'High';
    if (pressureState == 2) return 'Low';
    if (pressureBar != null) return 'OK';
    return '--';
  }
}

class _VehiclePaintOption {
  const _VehiclePaintOption(this.label, this.color);

  final String label;
  final Color color;
}

class _NavigationApp {
  const _NavigationApp({required this.label, required this.packageName});

  factory _NavigationApp.fromMap(Map<dynamic, dynamic> map) {
    return _NavigationApp(
      label: _stringFromMap(map, 'label'),
      packageName: _stringFromMap(map, 'packageName'),
    );
  }

  final String label;
  final String packageName;
}

const List<_NavigationApp> _previewNavigationApps = [
  _NavigationApp(label: 'BYD', packageName: 'com.byd.navigation'),
  _NavigationApp(label: 'Google', packageName: 'com.google.android.apps.maps'),
  _NavigationApp(label: 'Waze', packageName: 'com.waze'),
];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _preloadVehicleModelAssets();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(const BydLauncherApp());
}

void _preloadVehicleModelAssets() {
  unawaited(rootBundle.load(_vehicleModelAsset));
  unawaited(
    rootBundle.load('packages/model_viewer_plus/assets/model-viewer.min.js'),
  );
  unawaited(
    rootBundle.loadString('packages/model_viewer_plus/assets/template.html'),
  );
}

class BydLauncherApp extends StatefulWidget {
  const BydLauncherApp({super.key});

  @override
  State<BydLauncherApp> createState() => _BydLauncherAppState();
}

class _BydLauncherAppState extends State<BydLauncherApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  bool _themePreferenceLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BYD Launcher',
      themeMode: _themeMode,
      theme: _launcherTheme(Brightness.light),
      darkTheme: _launcherTheme(Brightness.dark),
      home: LauncherHomePage(
        enable3dModel: _themePreferenceLoaded,
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
      ),
    );
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_themeModePreferenceKey);
    final themeMode = _parseThemeMode(stored);
    if (!mounted) return;
    setState(() {
      _themeMode = themeMode;
      _themePreferenceLoaded = true;
    });
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModePreferenceKey, mode.name);
  }
}

ThemeData _launcherTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final textColor = dark ? _textPrimary : const Color(0xFF17202B);

  return ThemeData(
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF45A3FF),
      brightness: brightness,
    ),
    scaffoldBackgroundColor: dark
        ? const Color(0xFF070B12)
        : const Color(0xFFF1F5FA),
    fontFamily: 'sans-serif',
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    textTheme: Typography.material2021(
      platform: TargetPlatform.android,
    ).englishLike.apply(bodyColor: textColor, displayColor: textColor),
  );
}

enum _VehicleView { status, rear }

enum _LauncherTab { status, map, settings }

enum _VehicleGear { p, r, n, d }

enum _VehicleRenderQuality { low, medium, high }

enum _VehicleHotspot {
  frontLeftWindow,
  frontRightWindow,
  rearLeftWindow,
  rearRightWindow,
  sunroof,
  trunk,
}

ThemeMode _parseThemeMode(String? value) {
  return ThemeMode.values.firstWhere(
    (mode) => mode.name == value,
    orElse: () => ThemeMode.dark,
  );
}

_VehicleRenderQuality _parseRenderQuality(String? value) {
  return _VehicleRenderQuality.values.firstWhere(
    (quality) => quality.name == value,
    orElse: () => _VehicleRenderQuality.medium,
  );
}

const Color _textPrimary = Color(0xFFF6FAFF);
const Color _textSecondary = Color(0xFFE5ECF5);
const Color _textMuted = Color(0xFFB7C2CF);
const Color _accentSoftBlue = Color(0xFF78B7FF);
const Color _premiumLightStroke = Color(0xFFD5E0EB);
const Color _premiumLightText = Color(0xFF182230);
const Color _premiumLightMuted = Color(0xFF64748B);

const Color _lightInk = Color(0xFF101827);
const Color _lightInkSoft = Color(0xFF334155);
const Color _lightMuted = Color(0xFF728197);

bool _isLight(BuildContext context) {
  return Theme.of(context).brightness == Brightness.light;
}

Color _tone(BuildContext context, Color color) {
  if (!_isLight(context)) {
    return color;
  }

  if (color == _textPrimary || color == Colors.white) {
    return _lightInk;
  }
  if (color == _textSecondary) {
    return _lightInkSoft;
  }
  if (color == _textMuted || color == const Color(0xFF9FAEBE)) {
    return _lightMuted;
  }

  return color;
}

TextStyle? _sharp(
  BuildContext context,
  TextStyle? base, {
  Color color = _textPrimary,
  FontWeight weight = FontWeight.w500,
  double? size,
  double? height,
  double? letterSpacing,
}) {
  return base?.copyWith(
    color: _tone(context, color),
    fontWeight: weight,
    fontSize: size,
    height: height,
    letterSpacing: letterSpacing,
    leadingDistribution: TextLeadingDistribution.even,
  );
}

class LauncherHomePage extends StatefulWidget {
  const LauncherHomePage({
    super.key,
    this.enable3dModel = true,
    this.themeMode = ThemeMode.dark,
    this.onThemeModeChanged,
  });

  final bool enable3dModel;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  @override
  State<LauncherHomePage> createState() => _LauncherHomePageState();
}

class _LauncherHomePageState extends State<LauncherHomePage> {
  _VehicleView _view = _VehicleView.status;
  _LauncherTab _activeTab = _LauncherTab.status;
  _VehicleRenderQuality _renderQuality = _VehicleRenderQuality.medium;
  Color _vehicleColor = const Color(0xFFE9EEF4);
  _VehicleGear _selectedGear = _VehicleGear.p;
  bool _vehiclePreferencesLoaded = false;
  List<_NavigationApp> _navigationApps = const [];
  String? _selectedNavigationPackage;
  bool _launchNavigationWithLauncher = false;
  double _vehicleSpeedKmh = 0;
  _VehicleSnapshot _vehicleSnapshot = const _VehicleSnapshot();
  Timer? _vehicleSnapshotTimer;
  StreamSubscription<dynamic>? _vehicleSnapshotSubscription;

  bool get _roadMotionActive =>
      _effectiveGear == _VehicleGear.d || _effectiveGear == _VehicleGear.r;

  bool get _reverseRoadMotion => _effectiveGear == _VehicleGear.r;

  _VehicleGear get _effectiveGear => _vehicleSnapshot.gear ?? _selectedGear;

  double get _effectiveSpeedKmh =>
      _vehicleSnapshot.speedKmh ?? _vehicleSpeedKmh;

  @override
  void initState() {
    super.initState();
    _loadVehiclePreferences();
    _loadNavigationPreferences();
    _refreshVehicleSnapshot();
    _vehicleSnapshotSubscription = _vehicleEvents
        .receiveBroadcastStream()
        .listen(_handleVehicleSnapshotEvent, onError: (_) {});
    _vehicleSnapshotTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _refreshVehicleSnapshot(),
    );
  }

  @override
  void dispose() {
    _vehicleSnapshotTimer?.cancel();
    _vehicleSnapshotSubscription?.cancel();
    super.dispose();
  }

  String get _cameraOrbit {
    if (_roadMotionActive) {
      return '180deg 78deg 99%';
    }

    return switch (_view) {
      _VehicleView.rear => '148deg 70deg 92%',
      _VehicleView.status => '318deg 70deg 86%',
    };
  }

  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.40, -0.25),
              radius: 1.18,
              colors: light
                  ? const [
                      Color(0xFFFFFFFF),
                      Color(0xFFF1F6FC),
                      Color(0xFFDCE7F2),
                    ]
                  : const [
                      Color(0xFF202A38),
                      Color(0xFF0B111A),
                      Color(0xFF05070C),
                    ],
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 1100;
              final sidebarWidth = compact ? 292.0 : 348.0;

              return Stack(
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: sidebarWidth,
                        child: _LeftDashboard(
                          selectedGear: _selectedGear,
                          effectiveGear: _effectiveGear,
                          vehicleSpeedKmh: _effectiveSpeedKmh,
                          vehicleSnapshot: _vehicleSnapshot,
                          vehicleColor: _vehicleColor,
                          onGearChanged: _setGear,
                        ),
                      ),
                      Expanded(
                        child: _VehicleCanvas(
                          enable3dModel:
                              widget.enable3dModel && _vehiclePreferencesLoaded,
                          cameraOrbit: _cameraOrbit,
                          view: _view,
                          activeTab: _activeTab,
                          vehicleColor: _vehicleColor,
                          renderQuality: _renderQuality,
                          roadMotionActive: _roadMotionActive,
                          reverseRoadMotion: _reverseRoadMotion,
                          vehicleSpeedKmh: _effectiveSpeedKmh,
                          effectiveGear: _effectiveGear,
                          vehicleSnapshot: _vehicleSnapshot,
                          onGearChanged: _setGear,
                          onViewChanged: (view) => setState(() => _view = view),
                          onTabChanged: _handleTabChanged,
                          onVehicleColorChanged: _setVehicleColor,
                          onRenderQualityChanged: _setRenderQuality,
                          navigationApps: _navigationApps,
                          selectedNavigationPackage: _selectedNavigationPackage,
                          launchNavigationWithLauncher:
                              _launchNavigationWithLauncher,
                          onDefaultNavigationAppChanged:
                              _setDefaultNavigationApp,
                          onNavigationReloadRequested: _reloadNavigationApps,
                          onDefaultNavigationOpenRequested:
                              _openDefaultNavigationApp,
                          onLaunchNavigationWithLauncherChanged:
                              _setLaunchNavigationWithLauncher,
                          themeMode: widget.themeMode,
                          onThemeModeChanged: widget.onThemeModeChanged,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _handleTabChanged(_LauncherTab tab) {
    setState(() => _activeTab = tab);
  }

  void _setGear(_VehicleGear gear) {
    setState(() {
      _selectedGear = gear;
      _vehicleSpeedKmh = switch (gear) {
        _VehicleGear.d => 24,
        _VehicleGear.r => 8,
        _VehicleGear.p || _VehicleGear.n => 0,
      };

      if (gear == _VehicleGear.d || gear == _VehicleGear.r) {
        _activeTab = _LauncherTab.status;
        _view = _VehicleView.status;
      }

      if (gear == _VehicleGear.p || gear == _VehicleGear.n) {
        _activeTab = _LauncherTab.status;
        _view = _VehicleView.status;
      }
    });
  }

  Future<void> _loadVehiclePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final storedColor = prefs.getInt(_vehicleColorPreferenceKey);
    final storedQuality = prefs.getString(_renderQualityPreferenceKey);

    if (!mounted) return;
    setState(() {
      if (storedColor != null) {
        _vehicleColor = Color(storedColor);
      }
      _renderQuality = _parseRenderQuality(storedQuality);
      _vehiclePreferencesLoaded = true;
    });
  }

  Future<void> _setVehicleColor(Color color) async {
    setState(() => _vehicleColor = color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_vehicleColorPreferenceKey, color.toARGB32());
  }

  Future<void> _setRenderQuality(_VehicleRenderQuality quality) async {
    setState(() => _renderQuality = quality);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_renderQualityPreferenceKey, quality.name);
  }

  Future<void> _loadNavigationPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final storedPackage = prefs.getString(
      _navigationDefaultPackagePreferenceKey,
    );
    final launchWithLauncher =
        prefs.getBool(_launchNavigationWithLauncherPreferenceKey) ?? false;
    final apps = await _loadNavigationAppsFromPlatform();
    final selectedPackage = _resolveNavigationPackage(apps, storedPackage);
    final effectiveLaunchWithLauncher =
        launchWithLauncher && selectedPackage != null;

    if (!mounted) return;
    setState(() {
      _navigationApps = apps;
      _selectedNavigationPackage = selectedPackage;
      _launchNavigationWithLauncher = effectiveLaunchWithLauncher;
    });

    if (effectiveLaunchWithLauncher) {
      unawaited(_launchNavigationApp(selectedPackage));
    }
  }

  Future<List<_NavigationApp>> _loadNavigationAppsFromPlatform() async {
    try {
      final rawApps = await _navigationChannel.invokeListMethod<dynamic>(
        'getNavigationApps',
      );
      final apps = (rawApps ?? [])
          .whereType<Map<dynamic, dynamic>>()
          .map(_NavigationApp.fromMap)
          .where((app) => app.label.isNotEmpty && app.packageName.isNotEmpty)
          .toList();
      return apps;
    } catch (_) {
      return defaultTargetPlatform == TargetPlatform.android
          ? const []
          : _previewNavigationApps;
    }
  }

  String? _resolveNavigationPackage(
    List<_NavigationApp> apps,
    String? storedPackage,
  ) {
    if (apps.isEmpty) return null;
    if (storedPackage != null &&
        apps.any((app) => app.packageName == storedPackage)) {
      return storedPackage;
    }
    return apps.first.packageName;
  }

  Future<void> _setDefaultNavigationApp(_NavigationApp app) async {
    setState(() => _selectedNavigationPackage = app.packageName);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _navigationDefaultPackagePreferenceKey,
      app.packageName,
    );
  }

  Future<void> _reloadNavigationApps() async {
    final apps = await _loadNavigationAppsFromPlatform();
    if (!mounted) return;
    final selectedPackage = _resolveNavigationPackage(
      apps,
      _selectedNavigationPackage,
    );
    setState(() {
      _navigationApps = apps;
      _selectedNavigationPackage = selectedPackage;
      if (selectedPackage == null) {
        _launchNavigationWithLauncher = false;
      }
    });
  }

  Future<void> _openDefaultNavigationApp() async {
    final packageName = _selectedNavigationPackage;
    if (packageName == null) return;
    await _launchNavigationApp(packageName);
  }

  Future<void> _launchNavigationApp(String packageName) async {
    try {
      await _navigationChannel.invokeMethod<Object?>('launchNavigationApp', {
        'packageName': packageName,
      });
    } catch (_) {}
  }

  Future<void> _setLaunchNavigationWithLauncher(bool value) async {
    if (value && _selectedNavigationPackage == null) {
      return;
    }
    setState(() => _launchNavigationWithLauncher = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_launchNavigationWithLauncherPreferenceKey, value);
  }

  Future<void> _refreshVehicleSnapshot() async {
    try {
      final data = await _vehicleChannel.invokeMapMethod<String, dynamic>(
        'getVehicleSnapshot',
      );
      if (!mounted || data == null) return;
      setState(() => _vehicleSnapshot = _VehicleSnapshot.fromMap(data));
    } catch (_) {}
  }

  void _handleVehicleSnapshotEvent(dynamic value) {
    if (!mounted || value is! Map) return;
    setState(() => _vehicleSnapshot = _VehicleSnapshot.fromMap(value));
  }
}

class _LeftDashboard extends StatelessWidget {
  const _LeftDashboard({
    required this.selectedGear,
    required this.effectiveGear,
    required this.vehicleSpeedKmh,
    required this.vehicleSnapshot,
    required this.vehicleColor,
    required this.onGearChanged,
  });

  final _VehicleGear selectedGear;
  final _VehicleGear effectiveGear;
  final double vehicleSpeedKmh;
  final _VehicleSnapshot vehicleSnapshot;
  final Color vehicleColor;
  final ValueChanged<_VehicleGear> onGearChanged;

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 8, 18),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: light
                    ? [
                        const Color(0xFFFFFFFF).withValues(alpha: 0.92),
                        const Color(0xFFEAF2FA).withValues(alpha: 0.86),
                      ]
                    : [
                        const Color(0xFF101824).withValues(alpha: 0.94),
                        const Color(0xFF070D15).withValues(alpha: 0.90),
                      ],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: light
                    ? const Color(0xFFE7EEF6).withValues(alpha: 0.98)
                    : Colors.white.withValues(alpha: 0.065),
                width: light ? 1.15 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: light ? 0.07 : 0.22),
                  blurRadius: light ? 22 : 28,
                  offset: Offset(0, light ? 10 : 18),
                ),
                BoxShadow(
                  color: _accentSoftBlue.withValues(
                    alpha: light ? 0.075 : 0.035,
                  ),
                  blurRadius: light ? 26 : 34,
                  spreadRadius: light ? -1 : 1,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                children: [
                  _StatusBar(
                    outsideTemperatureC: vehicleSnapshot.outsideTemperatureC,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 214,
                    child: _TpmsCluster(
                      vehicleColor: vehicleColor,
                      snapshot: vehicleSnapshot,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const SizedBox(height: 168, child: _MediaWidget()),
                  const SizedBox(height: 10),
                  _EnergyStrip(snapshot: vehicleSnapshot),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBar extends StatefulWidget {
  const _StatusBar({this.outsideTemperatureC});

  final int? outsideTemperatureC;

  @override
  State<_StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends State<_StatusBar> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _scheduleNextTick();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _scheduleNextTick() {
    _timer?.cancel();
    final nextMinute = DateTime(
      _now.year,
      _now.month,
      _now.day,
      _now.hour,
      _now.minute + 1,
    );
    final delay = nextMinute.difference(DateTime.now());
    _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _scheduleNextTick();
    });
  }

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          _formatClockTime(_now),
          style: _sharp(
            context,
            Theme.of(context).textTheme.titleMedium,
            color: _textPrimary,
            weight: FontWeight.w600,
            size: 18,
            letterSpacing: -0.1,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: light
                ? Colors.white.withValues(alpha: 0.58)
                : Colors.white.withValues(alpha: 0.055),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: light
                  ? const Color(0xFFD4DEE9).withValues(alpha: 0.84)
                  : Colors.white.withValues(alpha: 0.055),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.wb_sunny_outlined,
                color: _tone(context, _textSecondary),
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                widget.outsideTemperatureC == null
                    ? '--°C'
                    : '${widget.outsideTemperatureC}°C',
                style: _sharp(
                  context,
                  Theme.of(context).textTheme.labelMedium,
                  color: _textSecondary,
                  weight: FontWeight.w500,
                  size: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _formatClockTime(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

class _SpeedCluster extends StatelessWidget {
  const _SpeedCluster({
    required this.selectedGear,
    required this.vehicleSpeedKmh,
    required this.onGearChanged,
  });

  final _VehicleGear selectedGear;
  final double vehicleSpeedKmh;
  final ValueChanged<_VehicleGear> onGearChanged;

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);

    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween<double>(end: vehicleSpeedKmh),
          duration: const Duration(milliseconds: 620),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) {
            return Text(
              value.round().toString(),
              style: _sharp(
                context,
                Theme.of(context).textTheme.displayLarge,
                color: _textPrimary,
                weight: FontWeight.w300,
                size: 88,
                height: 0.86,
                letterSpacing: -2.6,
              ),
            );
          },
        ),
        Text(
          'km/h',
          style: _sharp(
            context,
            Theme.of(context).textTheme.titleMedium,
            color: _textSecondary,
            weight: FontWeight.w500,
            size: 14,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: light
                ? Colors.white.withValues(alpha: 0.58)
                : Colors.black.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: light
                  ? const Color(0xFFD4DEE9).withValues(alpha: 0.84)
                  : Colors.white.withValues(alpha: 0.055),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _GearText(
                'P',
                active: selectedGear == _VehicleGear.p,
                onTap: () => onGearChanged(_VehicleGear.p),
              ),
              _GearText(
                'R',
                active: selectedGear == _VehicleGear.r,
                onTap: () => onGearChanged(_VehicleGear.r),
              ),
              _GearText(
                'N',
                active: selectedGear == _VehicleGear.n,
                onTap: () => onGearChanged(_VehicleGear.n),
              ),
              _GearText(
                'D',
                active: selectedGear == _VehicleGear.d,
                onTap: () => onGearChanged(_VehicleGear.d),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GearText extends StatelessWidget {
  const _GearText(this.label, {this.active = false, this.onTap});

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? _accentSoftBlue.withValues(alpha: 0.18)
              : Colors.transparent,
          boxShadow: active
              ? [
                  BoxShadow(
                    color: _accentSoftBlue.withValues(alpha: 0.14),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: _sharp(
              context,
              Theme.of(context).textTheme.labelMedium,
              color: active ? Colors.white : _textMuted,
              weight: active ? FontWeight.w700 : FontWeight.w500,
              size: 13,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
    );
  }
}

class _PremiumSpeedGearCluster extends StatelessWidget {
  const _PremiumSpeedGearCluster({
    required this.selectedGear,
    required this.vehicleSpeedKmh,
    required this.onGearChanged,
  });

  final _VehicleGear selectedGear;
  final double vehicleSpeedKmh;
  final ValueChanged<_VehicleGear> onGearChanged;

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);
    final ringColor = light
        ? const Color(0xFF2F80ED).withValues(alpha: 0.20)
        : _accentSoftBlue.withValues(alpha: 0.22);

    return Padding(
      padding: const EdgeInsets.all(4),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _accentSoftBlue.withValues(alpha: light ? 0.12 : 0.10),
                    Colors.transparent,
                  ],
                ),
                border: Border.all(color: ringColor, width: 1.4),
                boxShadow: [
                  BoxShadow(
                    color: _accentSoftBlue.withValues(
                      alpha: light ? 0.14 : 0.08,
                    ),
                    blurRadius: 24,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: light
                        ? Colors.white.withValues(alpha: 0.74)
                        : Colors.white.withValues(alpha: 0.075),
                  ),
                ),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: vehicleSpeedKmh),
                duration: const Duration(milliseconds: 620),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) {
                  return Text(
                    value.round().toString(),
                    style: _sharp(
                      context,
                      Theme.of(context).textTheme.displayMedium,
                      color: _textPrimary,
                      weight: FontWeight.w300,
                      size: 58,
                      height: 0.86,
                      letterSpacing: -1.8,
                    ),
                  );
                },
              ),
              Text(
                'km/h',
                style: _sharp(
                  context,
                  Theme.of(context).textTheme.labelMedium,
                  color: _textSecondary,
                  weight: FontWeight.w600,
                  size: 12,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: light
                      ? Colors.white.withValues(alpha: 0.58)
                      : Colors.black.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: light
                        ? const Color(0xFFD4DEE9).withValues(alpha: 0.84)
                        : Colors.white.withValues(alpha: 0.055),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _GearText(
                      'P',
                      active: selectedGear == _VehicleGear.p,
                      onTap: () => onGearChanged(_VehicleGear.p),
                    ),
                    _GearText(
                      'R',
                      active: selectedGear == _VehicleGear.r,
                      onTap: () => onGearChanged(_VehicleGear.r),
                    ),
                    _GearText(
                      'N',
                      active: selectedGear == _VehicleGear.n,
                      onTap: () => onGearChanged(_VehicleGear.n),
                    ),
                    _GearText(
                      'D',
                      active: selectedGear == _VehicleGear.d,
                      onTap: () => onGearChanged(_VehicleGear.d),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TpmsCluster extends StatelessWidget {
  const _TpmsCluster({required this.vehicleColor, required this.snapshot});

  final Color vehicleColor;
  final _VehicleSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.tire_repair_outlined,
                color: _accentSoftBlue,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                'TPMS',
                style: _sharp(
                  context,
                  Theme.of(context).textTheme.labelMedium,
                  color: _textMuted,
                  weight: FontWeight.w500,
                  size: 12,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final carWidth = constraints.maxWidth >= 280 ? 96.0 : 82.0;
                final lineWidth = constraints.maxWidth >= 280 ? 46.0 : 32.0;
                final lineTop = constraints.maxHeight * 0.27;
                final lineBottom = constraints.maxHeight * 0.27;
                final leftLine = math.max(
                  62.0,
                  constraints.maxWidth / 2 - carWidth / 2 - lineWidth + 8,
                );
                final rightLine = math.max(
                  62.0,
                  constraints.maxWidth / 2 - carWidth / 2 - lineWidth + 8,
                );

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: Center(
                        child: SizedBox(
                          width: carWidth,
                          height: constraints.maxHeight * 0.94,
                          child: _TintedTpmsVehicleImage(
                            vehicleColor: vehicleColor,
                          ),
                        ),
                      ),
                    ),

                    Positioned(
                      left: 0,
                      top: 16,
                      child: _PressureBlock(
                        value: snapshot.tyre('frontLeft').pressureLabel,
                        temp: snapshot.tyre('frontLeft').stateLabel,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 16,
                      child: _PressureBlock(
                        value: snapshot.tyre('frontRight').pressureLabel,
                        temp: snapshot.tyre('frontRight').stateLabel,
                        alignRight: true,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      bottom: 16,
                      child: _PressureBlock(
                        value: snapshot.tyre('rearLeft').pressureLabel,
                        temp: snapshot.tyre('rearLeft').stateLabel,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 16,
                      child: _PressureBlock(
                        value: snapshot.tyre('rearRight').pressureLabel,
                        temp: snapshot.tyre('rearRight').stateLabel,
                        alignRight: true,
                      ),
                    ),

                    Positioned(
                      left: leftLine,
                      top: lineTop,
                      child: _TpmsLine(width: lineWidth),
                    ),
                    Positioned(
                      right: rightLine,
                      top: lineTop,
                      child: _TpmsLine(width: lineWidth, flip: true),
                    ),
                    Positioned(
                      left: leftLine,
                      bottom: lineBottom,
                      child: _TpmsLine(width: lineWidth),
                    ),
                    Positioned(
                      right: rightLine,
                      bottom: lineBottom,
                      child: _TpmsLine(width: lineWidth, flip: true),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TpmsLine extends StatelessWidget {
  const _TpmsLine({required this.width, this.flip = false});

  final double width;
  final bool flip;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scaleX: flip ? -1 : 1,
      child: Container(
        width: width,
        height: 1.4,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF45A3FF).withValues(alpha: 0.9),
              const Color(0xFF45A3FF).withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }
}

class _TintedTpmsVehicleImage extends StatelessWidget {
  const _TintedTpmsVehicleImage({required this.vehicleColor});

  final Color vehicleColor;

  static const _assetPath = 'assets/images/sealion6_tpms_top_view.png';
  static const _maskPath = 'assets/images/sealion6_tpms_body_mask.png';

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: vehicleColor),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, color, child) {
        final paintColor = color ?? vehicleColor;
        final isWhitePaint = paintColor.computeLuminance() > 0.72;
        final overlayColor = isWhitePaint
            ? const Color(0xFFF6FAFF)
            : paintColor;
        final overlayOpacity = isWhitePaint ? 0.46 : 0.72;

        return Stack(
          fit: StackFit.expand,
          children: [
            child!,
            Opacity(
              opacity: overlayOpacity,
              child: Image.asset(
                _maskPath,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                color: overlayColor,
                colorBlendMode: BlendMode.srcIn,
              ),
            ),
          ],
        );
      },
      child: Image.asset(
        _assetPath,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

class _PressureBlock extends StatelessWidget {
  const _PressureBlock({
    required this.value,
    required this.temp,
    this.alignRight = false,
  });

  final String value;
  final String temp;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 70,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: alignRight
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            style: _sharp(
              context,
              Theme.of(context).textTheme.bodyMedium,
              color: _textPrimary,
              weight: FontWeight.w700,
              size: 12.5,
              height: 1.05,
              letterSpacing: 0.02,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            temp,
            maxLines: 1,
            style: _sharp(
              context,
              Theme.of(context).textTheme.bodySmall,
              color: _textSecondary,
              weight: FontWeight.w500,
              size: 10.5,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaWidget extends StatefulWidget {
  const _MediaWidget();

  @override
  State<_MediaWidget> createState() => _MediaWidgetState();
}

class _MediaWidgetState extends State<_MediaWidget>
    with WidgetsBindingObserver {
  StreamSubscription<dynamic>? _subscription;
  Timer? _progressTimer;
  _MediaPlaybackState _state = const _MediaPlaybackState();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInitialState();
    _subscription = _musicEvents.receiveBroadcastStream().listen(
      _handleNativeState,
      onError: (_) {},
    );
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _state.isPlaying && _state.durationMs > 0) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _progressTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadInitialState();
    }
  }

  Future<void> _loadInitialState() async {
    try {
      final data = await _musicChannel.invokeMapMethod<String, dynamic>(
        'getState',
      );
      _handleNativeState(data);
    } catch (_) {}
  }

  void _handleNativeState(dynamic value) {
    if (!mounted || value is! Map) return;
    setState(() {
      _state = _MediaPlaybackState.fromMap(value);
    });
  }

  void _invoke(String method) {
    unawaited(
      _musicChannel
          .invokeMethod<Object?>(method)
          .catchError((Object _) => null),
    );
  }

  void _openMusicApp() {
    _invoke('openMusicApp');
  }

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);
    final controlColor = light ? const Color(0xFF31516F) : _textSecondary;
    final progressTrack = light
        ? const Color(0xFFD4E0EB)
        : const Color(0xFF293241);

    return _GlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _openMusicApp,
                child: Container(
                  width: 66,
                  height: 66,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF5E1E2A), Color(0xFF171B2D)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFC857).withValues(alpha: 0.08),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: _state.albumArt == null
                      ? const Icon(
                          Icons.music_note_rounded,
                          color: Color(0xFFFFD36E),
                          size: 32,
                        )
                      : Image.memory(
                          _state.albumArt!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _state.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _sharp(
                        context,
                        Theme.of(context).textTheme.titleMedium,
                        color: _textPrimary,
                        weight: FontWeight.w600,
                        size: 16,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _state.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _sharp(
                        context,
                        Theme.of(context).textTheme.bodyMedium,
                        color: _textMuted,
                        weight: FontWeight.w500,
                        size: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                _state.hasPermission
                    ? Icons.bluetooth
                    : Icons.music_off_outlined,
                color: _accentSoftBlue,
                size: light ? 22 : 20,
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Text(
                _state.elapsedLabel,
                style: _sharp(
                  context,
                  Theme.of(context).textTheme.labelSmall,
                  color: _textMuted,
                  weight: FontWeight.w600,
                  size: 10.5,
                  height: 1,
                ),
              ),
              const Spacer(),
              Text(
                _state.durationLabel,
                style: _sharp(
                  context,
                  Theme.of(context).textTheme.labelSmall,
                  color: _textMuted,
                  weight: FontWeight.w600,
                  size: 10.5,
                  height: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: _state.progress ?? 0,
              minHeight: light ? 4 : 3,
              color: _accentSoftBlue,
              backgroundColor: progressTrack,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _MediaControlButton(
                icon: Icons.skip_previous_rounded,
                color: controlColor,
                enabled: _state.hasController,
                onPressed: () => _invoke('previous'),
              ),
              const SizedBox(width: 22),
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _invoke('playPause'),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: light
                        ? _accentSoftBlue.withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: light
                          ? _accentSoftBlue.withValues(alpha: 0.24)
                          : Colors.white.withValues(alpha: 0.07),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: light
                            ? _accentSoftBlue.withValues(alpha: 0.12)
                            : Colors.black.withValues(alpha: 0.10),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Icon(
                    _state.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: light ? const Color(0xFF1D4F86) : Colors.white,
                    size: _state.isPlaying ? 22 : 25,
                  ),
                ),
              ),
              const SizedBox(width: 22),
              _MediaControlButton(
                icon: Icons.skip_next_rounded,
                color: controlColor,
                enabled: _state.hasController,
                onPressed: () => _invoke('next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MediaControlButton extends StatelessWidget {
  const _MediaControlButton({
    required this.icon,
    required this.color,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      visualDensity: VisualDensity.compact,
      onPressed: enabled ? onPressed : null,
      icon: Icon(
        icon,
        color: enabled
            ? color
            : _tone(context, _textMuted).withValues(alpha: 0.45),
        size: 26,
      ),
    );
  }
}

class _MediaPlaybackState {
  const _MediaPlaybackState({
    this.hasPermission = false,
    this.hasController = false,
    this.title = 'Music',
    this.artist = 'Open system music',
    this.album = '',
    this.isPlaying = false,
    this.durationMs = 0,
    this.positionMs = 0,
    this.receivedAtMs = 0,
    this.albumArt,
  });

  factory _MediaPlaybackState.fromMap(Map<dynamic, dynamic> map) {
    final hasPermission = map['hasPermission'] == true;
    final hasController = map['hasController'] == true;
    final title = _stringFromMap(map, 'title');
    final artist = _stringFromMap(map, 'artist');
    final album = _stringFromMap(map, 'album');

    return _MediaPlaybackState(
      hasPermission: hasPermission,
      hasController: hasController,
      title: title.isEmpty
          ? (hasController ? 'Unknown track' : 'Music')
          : title,
      artist: artist.isEmpty
          ? (hasPermission
                ? 'Open system music'
                : 'Enable Music access in Settings')
          : artist,
      album: album,
      isPlaying: map['isPlaying'] == true,
      durationMs: _intFromMap(map, 'durationMs'),
      positionMs: _intFromMap(map, 'positionMs'),
      receivedAtMs: DateTime.now().millisecondsSinceEpoch,
      albumArt: map['albumArt'] is Uint8List
          ? map['albumArt'] as Uint8List
          : null,
    );
  }

  final bool hasPermission;
  final bool hasController;
  final String title;
  final String artist;
  final String album;
  final bool isPlaying;
  final int durationMs;
  final int positionMs;
  final int receivedAtMs;
  final Uint8List? albumArt;

  String get subtitle {
    if (album.isEmpty) return artist;
    return '$artist - $album';
  }

  double? get progress {
    if (durationMs <= 0) return null;
    final position = currentPositionMs.clamp(0, durationMs);
    return position / durationMs;
  }

  String get elapsedLabel {
    if (durationMs <= 0) return '--:--';
    return _formatMediaTime(currentPositionMs.clamp(0, durationMs));
  }

  String get durationLabel {
    if (durationMs <= 0) return '--:--';
    return _formatMediaTime(durationMs);
  }

  int get currentPositionMs {
    if (!isPlaying || receivedAtMs <= 0) {
      return positionMs;
    }

    final age = DateTime.now().millisecondsSinceEpoch - receivedAtMs;
    return positionMs + age.clamp(0, 3600000);
  }
}

String _stringFromMap(Map<dynamic, dynamic> map, String key) {
  final value = map[key];
  return value is String ? value.trim() : '';
}

int _intFromMap(Map<dynamic, dynamic> map, String key) {
  final value = map[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return 0;
}

int? _intFromMapOrNull(Map<dynamic, dynamic> map, String key) {
  final value = map[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

double? _doubleFromMap(Map<dynamic, dynamic> map, String key) {
  final value = map[key];
  if (value is num) return value.toDouble();
  return null;
}

_VehicleGear? _gearFromString(String value) {
  return switch (value.toUpperCase()) {
    'P' => _VehicleGear.p,
    'R' => _VehicleGear.r,
    'N' => _VehicleGear.n,
    'D' || 'M' || 'S' => _VehicleGear.d,
    _ => null,
  };
}

String _formatMediaTime(int milliseconds) {
  final totalSeconds = Duration(milliseconds: milliseconds).inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

class _EnergyStrip extends StatelessWidget {
  const _EnergyStrip({required this.snapshot});

  final _VehicleSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final fuel = snapshot.fuelPercent;
    final battery = snapshot.batteryPercent;
    final range = snapshot.rangeKm;

    return _GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Range',
            style: _sharp(
              context,
              Theme.of(context).textTheme.labelMedium,
              color: _textMuted,
              weight: FontWeight.w500,
              size: 12,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                range?.toString() ?? '--',
                style: _sharp(
                  context,
                  Theme.of(context).textTheme.headlineMedium,
                  color: _textPrimary,
                  weight: FontWeight.w500,
                  size: 28,
                  height: 0.95,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(width: 5),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  'km',
                  style: _sharp(
                    context,
                    Theme.of(context).textTheme.labelLarge,
                    color: _textSecondary,
                    weight: FontWeight.w500,
                    size: 13,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.route_outlined,
                color: _accentSoftBlue,
                size: 22,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _EnergyLevel(
                  icon: Icons.local_gas_station,
                  label: 'Fuel',
                  value: fuel == null ? '--' : '$fuel%',
                  color: Color(0xFF25D366),
                  progress: (fuel ?? 0) / 100,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _EnergyLevel(
                  icon: Icons.battery_5_bar,
                  label: 'Battery',
                  value: battery == null ? '--' : '${battery.round()}%',
                  color: _accentSoftBlue,
                  progress: (battery ?? 0) / 100,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EnergyLevel extends StatelessWidget {
  const _EnergyLevel({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.progress,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              color: _isLight(context)
                  ? const Color(0xFF475569)
                  : _textSecondary,
              size: 16,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _sharp(
                  context,
                  Theme.of(context).textTheme.labelMedium,
                  color: _textSecondary,
                  weight: FontWeight.w500,
                  size: 12,
                ),
              ),
            ),
            Text(
              value,
              style: _sharp(
                context,
                Theme.of(context).textTheme.bodyMedium,
                color: _textPrimary,
                weight: FontWeight.w600,
                size: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            color: color,
            backgroundColor: _isLight(context)
                ? const Color(0xFFD4E0EB)
                : const Color(0xFF293241),
          ),
        ),
      ],
    );
  }
}

class _VehicleCanvas extends StatelessWidget {
  const _VehicleCanvas({
    required this.enable3dModel,
    required this.cameraOrbit,
    required this.view,
    required this.activeTab,
    required this.vehicleColor,
    required this.renderQuality,
    required this.roadMotionActive,
    required this.reverseRoadMotion,
    required this.vehicleSpeedKmh,
    required this.effectiveGear,
    required this.vehicleSnapshot,
    required this.onGearChanged,
    required this.onViewChanged,
    required this.onTabChanged,
    required this.onVehicleColorChanged,
    required this.onRenderQualityChanged,
    required this.navigationApps,
    required this.selectedNavigationPackage,
    required this.launchNavigationWithLauncher,
    required this.onDefaultNavigationAppChanged,
    required this.onNavigationReloadRequested,
    required this.onDefaultNavigationOpenRequested,
    required this.onLaunchNavigationWithLauncherChanged,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final bool enable3dModel;
  final String cameraOrbit;
  final _VehicleView view;
  final _LauncherTab activeTab;
  final Color vehicleColor;
  final _VehicleRenderQuality renderQuality;
  final bool roadMotionActive;
  final bool reverseRoadMotion;
  final double vehicleSpeedKmh;
  final _VehicleGear effectiveGear;
  final _VehicleSnapshot vehicleSnapshot;
  final ValueChanged<_VehicleGear> onGearChanged;
  final ValueChanged<_VehicleView> onViewChanged;
  final ValueChanged<_LauncherTab> onTabChanged;
  final ValueChanged<Color> onVehicleColorChanged;
  final ValueChanged<_VehicleRenderQuality> onRenderQualityChanged;
  final List<_NavigationApp> navigationApps;
  final String? selectedNavigationPackage;
  final bool launchNavigationWithLauncher;
  final ValueChanged<_NavigationApp> onDefaultNavigationAppChanged;
  final VoidCallback onNavigationReloadRequested;
  final VoidCallback onDefaultNavigationOpenRequested;
  final ValueChanged<bool> onLaunchNavigationWithLauncherChanged;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 28, 38, 28),
      child: Stack(
        children: [
          Positioned.fill(
            left: 0,
            top: 0,
            right: 0,
            bottom: 68,
            child: Offstage(
              offstage: activeTab != _LauncherTab.status,
              child: IgnorePointer(
                ignoring: activeTab != _LauncherTab.status,
                child: _VehicleStage(
                  enable3dModel: enable3dModel,
                  cameraOrbit: cameraOrbit,
                  vehicleColor: vehicleColor,
                  renderQuality: renderQuality,
                  roadMotionActive: roadMotionActive,
                  reverseRoadMotion: reverseRoadMotion,
                  vehicleSpeedKmh: vehicleSpeedKmh,
                ),
              ),
            ),
          ),
          if (activeTab != _LauncherTab.status)
            Positioned.fill(
              left: 0,
              top: 0,
              right: 0,
              bottom: 68,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeOutCubic,
                child: activeTab == _LauncherTab.settings
                    ? _SettingsPanel(
                        key: const ValueKey('settings'),
                        vehicleColor: vehicleColor,
                        onVehicleColorChanged: onVehicleColorChanged,
                        renderQuality: renderQuality,
                        onRenderQualityChanged: onRenderQualityChanged,
                        launchNavigationWithLauncher:
                            launchNavigationWithLauncher,
                        hasNavigationApps: navigationApps.isNotEmpty,
                        onLaunchNavigationWithLauncherChanged:
                            onLaunchNavigationWithLauncherChanged,
                        themeMode: themeMode,
                        onThemeModeChanged: onThemeModeChanged,
                      )
                    : _NavigationPanel(
                        key: const ValueKey('navigation'),
                        apps: navigationApps,
                        selectedPackage: selectedNavigationPackage,
                        onAppSelected: onDefaultNavigationAppChanged,
                        onReload: onNavigationReloadRequested,
                        onOpen: onDefaultNavigationOpenRequested,
                      ),
              ),
            ),
          if (activeTab == _LauncherTab.status)
            Positioned(
              left: 4,
              top: 12,
              right: 430,
              child: _FloatingVehicleControls(
                view: view,
                onRear: () => onViewChanged(_VehicleView.rear),
              ),
            ),
          if (activeTab == _LauncherTab.status)
            Positioned(
              top: 12,
              right: 0,
              width: 212,
              height: 212,
              child: _PremiumSpeedGearCluster(
                selectedGear: effectiveGear,
                vehicleSpeedKmh: vehicleSpeedKmh,
                onGearChanged: onGearChanged,
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 4,
            child: Center(
              child: _BottomTabs(
                activeTab: activeTab,
                onTabChanged: onTabChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleStage extends StatelessWidget {
  const _VehicleStage({
    required this.enable3dModel,
    required this.cameraOrbit,
    required this.vehicleColor,
    required this.renderQuality,
    required this.roadMotionActive,
    required this.reverseRoadMotion,
    required this.vehicleSpeedKmh,
  });

  final bool enable3dModel;
  final String cameraOrbit;
  final Color vehicleColor;
  final _VehicleRenderQuality renderQuality;
  final bool roadMotionActive;
  final bool reverseRoadMotion;
  final double vehicleSpeedKmh;

  @override
  Widget build(BuildContext context) {
    return _VehicleReveal(
      child: _VehicleEntrance(
        child: _VehicleHero(
          enable3dModel: enable3dModel,
          cameraOrbit: cameraOrbit,
          vehicleColor: vehicleColor,
          renderQuality: renderQuality,
          roadMotionActive: roadMotionActive,
          reverseRoadMotion: reverseRoadMotion,
          vehicleSpeedKmh: vehicleSpeedKmh,
        ),
      ),
    );
  }
}

class _NavigationPanel extends StatelessWidget {
  const _NavigationPanel({
    required this.apps,
    required this.selectedPackage,
    required this.onAppSelected,
    required this.onReload,
    required this.onOpen,
    super.key,
  });

  final List<_NavigationApp> apps;
  final String? selectedPackage;
  final ValueChanged<_NavigationApp> onAppSelected;
  final VoidCallback onReload;
  final VoidCallback onOpen;

  _NavigationApp? get _selectedApp {
    for (final app in apps) {
      if (app.packageName == selectedPackage) return app;
    }
    return apps.isEmpty ? null : apps.first;
  }

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);
    final selectedApp = _selectedApp;

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: light
                      ? const [
                          Color(0xFFFDFEFF),
                          Color(0xFFE9F2FB),
                          Color(0xFFD9E6F2),
                        ]
                      : const [
                          Color(0xFF152334),
                          Color(0xFF0B141F),
                          Color(0xFF060B12),
                        ],
                ),
              ),
              child: CustomPaint(painter: _MapGridPainter()),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.18, -0.10),
                    radius: 0.88,
                    colors: [
                      _accentSoftBlue.withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 16,
            left: 18,
            right: 188,
            child: _NavigationAppPicker(
              apps: apps,
              selectedPackage: selectedApp?.packageName,
              onAppSelected: onAppSelected,
              onReload: onReload,
            ),
          ),
          Positioned(
            top: 22,
            right: 22,
            child: _MapStatusPill(icon: Icons.gps_fixed, label: 'GPS Ready'),
          ),
          Positioned.fill(
            left: 16,
            top: 82,
            right: 16,
            bottom: 16,
            child: _EmbeddedNavigationSurface(
              app: selectedApp,
              onOpen: selectedApp == null ? null : onOpen,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmbeddedNavigationSurface extends StatelessWidget {
  const _EmbeddedNavigationSurface({required this.app, required this.onOpen});

  final _NavigationApp? app;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final app = this.app;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _isLight(context)
              ? Colors.white.withValues(alpha: 0.58)
              : Colors.black.withValues(alpha: 0.18),
          border: Border.all(
            color: _isLight(context)
                ? const Color(0xFFD4DEE9).withValues(alpha: 0.82)
                : Colors.white.withValues(alpha: 0.055),
          ),
        ),
        child: app == null
            ? const _EmbeddedNavigationFallback(
                icon: Icons.map_outlined,
                title: 'No map app installed',
                subtitle: 'Install a navigation app, then tap reload above.',
              )
            : defaultTargetPlatform == TargetPlatform.android
            ? _NavigationVirtualDisplayView(
                key: ValueKey('navigation-vd-${app.packageName}'),
                app: app,
              )
            : _EmbeddedNavigationFallback(
                icon: Icons.map_outlined,
                title: app.label,
                subtitle: 'Embedded navigation is available on Android.',
                onTap: onOpen,
              ),
      ),
    );
  }
}

class _NavigationVirtualDisplayView extends StatefulWidget {
  const _NavigationVirtualDisplayView({super.key, required this.app});

  final _NavigationApp app;

  @override
  State<_NavigationVirtualDisplayView> createState() =>
      _NavigationVirtualDisplayViewState();
}

class _NavigationVirtualDisplayViewState
    extends State<_NavigationVirtualDisplayView> {
  int? _textureId;
  Size? _textureSize;
  bool _launchOk = true;
  Object? _error;

  @override
  void didUpdateWidget(covariant _NavigationVirtualDisplayView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app.packageName != widget.app.packageName) {
      _disposeSession();
      _textureId = null;
      _textureSize = null;
      _error = null;
    }
  }

  @override
  void dispose() {
    _disposeSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ratio = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 2.0);
        final size = Size(
          (constraints.maxWidth * ratio).clamp(1.0, 4096.0),
          (constraints.maxHeight * ratio).clamp(1.0, 4096.0),
        );
        if (_textureSize != size && size.width > 1 && size.height > 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _createOrResize(size);
            }
          });
        }

        final textureId = _textureId;
        if (textureId == null) {
          return _EmbeddedNavigationFallback(
            icon: Icons.map_outlined,
            title: widget.app.label,
            subtitle: _error == null
                ? 'Starting embedded navigation...'
                : 'Virtual display could not start.',
          );
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (details) => _sendTouch('down', details.localPosition),
          onPanUpdate: (details) => _sendTouch('move', details.localPosition),
          onPanEnd: (_) => _sendTouch('up', null),
          onPanCancel: () => _sendTouch('cancel', null),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Texture(textureId: textureId),
              if (!_launchOk)
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: _MapStatusPill(
                    icon: Icons.warning_amber_rounded,
                    label: 'Virtual display blocked',
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _createOrResize(Size size) async {
    final width = size.width.round();
    final height = size.height.round();
    final textureId = _textureId;
    try {
      if (textureId == null) {
        final result = await _navigationVdChannel
            .invokeMapMethod<String, dynamic>('create', {
              'packageName': widget.app.packageName,
              'width': width,
              'height': height,
              'densityDpi': (160 * MediaQuery.devicePixelRatioOf(context))
                  .round()
                  .clamp(160, 320),
            });
        if (!mounted) return;
        setState(() {
          _textureId = (result?['textureId'] as num?)?.toInt();
          _launchOk = result?['launchOk'] != false;
          _textureSize = size;
          _error = null;
        });
      } else {
        await _navigationVdChannel.invokeMethod<Object?>('resize', {
          'textureId': textureId,
          'width': width,
          'height': height,
        });
        if (!mounted) return;
        setState(() => _textureSize = size);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  void _sendTouch(String action, Offset? position) {
    final textureId = _textureId;
    if (textureId == null) return;
    final box = context.findRenderObject() as RenderBox?;
    final size = box?.size ?? Size.zero;
    final textureSize = _textureSize;
    final local = position ?? Offset(size.width / 2, size.height / 2);
    final x = size.width <= 0 || textureSize == null
        ? local.dx
        : local.dx * textureSize.width / size.width;
    final y = size.height <= 0 || textureSize == null
        ? local.dy
        : local.dy * textureSize.height / size.height;
    unawaited(
      _navigationVdChannel
          .invokeMethod<Object?>('touch', {
            'textureId': textureId,
            'action': action,
            'x': x,
            'y': y,
          })
          .catchError((Object _) => null),
    );
  }

  void _disposeSession() {
    final textureId = _textureId;
    if (textureId == null) return;
    unawaited(
      _navigationVdChannel
          .invokeMethod<Object?>('dispose', {'textureId': textureId})
          .catchError((Object _) => null),
    );
  }
}

class _EmbeddedNavigationFallback extends StatelessWidget {
  const _EmbeddedNavigationFallback({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _accentSoftBlue, size: 42),
            const SizedBox(height: 12),
            Text(
              title,
              style: _sharp(
                context,
                Theme.of(context).textTheme.titleMedium,
                color: _textPrimary,
                weight: FontWeight.w700,
                size: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _sharp(
                context,
                Theme.of(context).textTheme.bodySmall,
                color: _textMuted,
                weight: FontWeight.w500,
                size: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationAppPicker extends StatelessWidget {
  const _NavigationAppPicker({
    required this.apps,
    required this.selectedPackage,
    required this.onAppSelected,
    required this.onReload,
  });

  final List<_NavigationApp> apps;
  final String? selectedPackage;
  final ValueChanged<_NavigationApp> onAppSelected;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);
    _NavigationApp? selectedApp;
    for (final app in apps) {
      if (app.packageName == selectedPackage) {
        selectedApp = app;
        break;
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: light
                ? Colors.white.withValues(alpha: 0.74)
                : const Color(0xFF07101A).withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: light
                  ? Colors.white.withValues(alpha: 0.86)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Wrap(
            spacing: 7,
            runSpacing: 7,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(Icons.apps_outlined, color: _accentSoftBlue, size: 19),
              Text(
                'Navigation app',
                style: _sharp(
                  context,
                  Theme.of(context).textTheme.labelLarge,
                  color: _textPrimary,
                  weight: FontWeight.w700,
                  size: 13,
                ),
              ),
              _NavigationTopIconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Reload navigation apps',
                onTap: onReload,
              ),
              for (final app in apps.take(5))
                _NavigationAppChip(
                  label: app.label,
                  selected: app.packageName == selectedPackage,
                  onTap: () => onAppSelected(app),
                ),
              PopupMenuButton<_NavigationApp>(
                tooltip: 'Choose navigation app',
                enabled: apps.isNotEmpty,
                onSelected: onAppSelected,
                itemBuilder: (context) => [
                  for (final app in apps)
                    PopupMenuItem<_NavigationApp>(
                      value: app,
                      child: Text(app.label),
                    ),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      selectedApp == null ? 'Choose' : 'Change',
                      style: _sharp(
                        context,
                        Theme.of(context).textTheme.labelSmall,
                        color: _textSecondary,
                        weight: FontWeight.w700,
                        size: 11.5,
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: _tone(context, _textSecondary),
                      size: 20,
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
}

class _NavigationTopIconButton extends StatelessWidget {
  const _NavigationTopIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.white.withValues(
              alpha: _isLight(context) ? 0.54 : 0.07,
            ),
            shape: BoxShape.circle,
            border: Border.all(
              color: _isLight(context)
                  ? const Color(0xFFD4DEE9).withValues(alpha: 0.84)
                  : Colors.white.withValues(alpha: 0.055),
            ),
          ),
          child: Icon(icon, color: _tone(context, _textSecondary), size: 17),
        ),
      ),
    );
  }
}

class _NavigationAppChip extends StatelessWidget {
  const _NavigationAppChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? _accentSoftBlue.withValues(alpha: 0.18)
              : light
              ? Colors.white.withValues(alpha: 0.66)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? _accentSoftBlue.withValues(alpha: 0.30)
                : light
                ? const Color(0xFFD4DEE9).withValues(alpha: 0.84)
                : Colors.white.withValues(alpha: 0.055),
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _sharp(
            context,
            Theme.of(context).textTheme.labelSmall,
            color: selected
                ? (_isLight(context) ? _premiumLightText : _textPrimary)
                : (_isLight(context) ? _premiumLightMuted : _textMuted),
            weight: selected ? FontWeight.w700 : FontWeight.w500,
            size: 11.5,
          ),
        ),
      ),
    );
  }
}

class _MapStatusPill extends StatelessWidget {
  const _MapStatusPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: light
            ? Colors.white.withValues(alpha: 0.68)
            : const Color(0xFF07101A).withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: light
              ? Colors.white.withValues(alpha: 0.84)
              : Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _accentSoftBlue, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: _sharp(
              context,
              Theme.of(context).textTheme.labelSmall,
              color: _textSecondary,
              weight: FontWeight.w600,
              size: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final roadPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.075)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final accentRoadPaint = Paint()
      ..color = _accentSoftBlue.withValues(alpha: 0.24)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (var i = -2; i < 8; i++) {
      final y = size.height * (0.12 + i * 0.16);
      final path = Path()
        ..moveTo(-40, y)
        ..cubicTo(
          size.width * 0.24,
          y + 42,
          size.width * 0.44,
          y - 58,
          size.width + 40,
          y + 12,
        );
      canvas.drawPath(path, roadPaint);
    }

    for (var i = -1; i < 6; i++) {
      final x = size.width * (0.10 + i * 0.18);
      final path = Path()
        ..moveTo(x, -40)
        ..cubicTo(
          x + 48,
          size.height * 0.26,
          x - 54,
          size.height * 0.52,
          x + 20,
          size.height + 40,
        );
      canvas.drawPath(path, roadPaint);
    }

    final route = Path()
      ..moveTo(size.width * 0.18, size.height * 0.82)
      ..cubicTo(
        size.width * 0.34,
        size.height * 0.64,
        size.width * 0.50,
        size.height * 0.74,
        size.width * 0.52,
        size.height * 0.50,
      )
      ..cubicTo(
        size.width * 0.54,
        size.height * 0.30,
        size.width * 0.70,
        size.height * 0.34,
        size.width * 0.82,
        size.height * 0.16,
      );
    canvas.drawPath(route, accentRoadPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.vehicleColor,
    required this.onVehicleColorChanged,
    required this.renderQuality,
    required this.onRenderQualityChanged,
    required this.launchNavigationWithLauncher,
    required this.hasNavigationApps,
    required this.onLaunchNavigationWithLauncherChanged,
    required this.themeMode,
    required this.onThemeModeChanged,
    super.key,
  });

  final Color vehicleColor;
  final ValueChanged<Color> onVehicleColorChanged;
  final _VehicleRenderQuality renderQuality;
  final ValueChanged<_VehicleRenderQuality> onRenderQualityChanged;
  final bool launchNavigationWithLauncher;
  final bool hasNavigationApps;
  final ValueChanged<bool> onLaunchNavigationWithLauncherChanged;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _accentSoftBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.07),
                  ),
                ),
                child: const Icon(
                  Icons.settings_outlined,
                  color: _accentSoftBlue,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Settings',
                    style: _sharp(
                      context,
                      Theme.of(context).textTheme.headlineSmall,
                      color: _textPrimary,
                      weight: FontWeight.w700,
                      size: 28,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Launcher and vehicle display preferences',
                    style: _sharp(
                      context,
                      Theme.of(context).textTheme.bodyMedium,
                      color: _textMuted,
                      weight: FontWeight.w500,
                      size: 13,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 11,
                  child: _SettingsMainColumn(
                    vehicleColor: vehicleColor,
                    onVehicleColorChanged: onVehicleColorChanged,
                    renderQuality: renderQuality,
                    onRenderQualityChanged: onRenderQualityChanged,
                    launchNavigationWithLauncher: launchNavigationWithLauncher,
                    hasNavigationApps: hasNavigationApps,
                    onLaunchNavigationWithLauncherChanged:
                        onLaunchNavigationWithLauncherChanged,
                    themeMode: themeMode,
                    onThemeModeChanged: onThemeModeChanged,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(flex: 9, child: _SettingsPermissionColumn()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsMainColumn extends StatelessWidget {
  const _SettingsMainColumn({
    required this.vehicleColor,
    required this.onVehicleColorChanged,
    required this.renderQuality,
    required this.onRenderQualityChanged,
    required this.launchNavigationWithLauncher,
    required this.hasNavigationApps,
    required this.onLaunchNavigationWithLauncherChanged,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final Color vehicleColor;
  final ValueChanged<Color> onVehicleColorChanged;
  final _VehicleRenderQuality renderQuality;
  final ValueChanged<_VehicleRenderQuality> onRenderQualityChanged;
  final bool launchNavigationWithLauncher;
  final bool hasNavigationApps;
  final ValueChanged<bool> onLaunchNavigationWithLauncherChanged;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          _GlassCard(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SettingsSectionTitle(
                  icon: Icons.palette_outlined,
                  title: 'Vehicle color',
                  subtitle:
                      'Used by the launcher preview and future render states.',
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final rawWidth = (constraints.maxWidth - 20) / 3;
                    final swatchWidth = rawWidth < 96
                        ? 96.0
                        : rawWidth > 156
                        ? 156.0
                        : rawWidth;

                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final option in _vehiclePaintOptions)
                          SizedBox(
                            width: swatchWidth,
                            child: _VehicleColorSwatch(
                              label: option.label,
                              color: option.color,
                              selected: vehicleColor == option.color,
                              onTap: onVehicleColorChanged,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _GlassCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SettingsSectionTitle(
                  icon: Icons.contrast_outlined,
                  title: 'Appearance',
                  subtitle:
                      'Choose a light theme, dark theme, or follow the system setting.',
                ),
                const SizedBox(height: 14),
                _ThemeModePicker(
                  selectedMode: themeMode,
                  onChanged: onThemeModeChanged,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _GlassCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SettingsSectionTitle(
                  icon: Icons.speed_outlined,
                  title: '3D render quality',
                  subtitle:
                      'Lower quality reduces texture resolution and anti-aliasing for smoother rotation.',
                ),
                const SizedBox(height: 14),
                _RenderQualityPicker(
                  selectedQuality: renderQuality,
                  onChanged: onRenderQualityChanged,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _GlassCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              children: [
                const _SettingsSwitchRow(
                  icon: Icons.home_outlined,
                  title: 'Default launcher',
                  subtitle:
                      'Open this launcher when the vehicle head unit starts.',
                  value: true,
                ),
                const SizedBox(height: 12),
                const _SettingsSwitchRow(
                  icon: Icons.screen_rotation_alt_outlined,
                  title: 'Force landscape',
                  subtitle:
                      'Keep the launcher optimized for the 15.6 inch display.',
                  value: true,
                ),
                const SizedBox(height: 12),
                _SettingsSwitchRow(
                  icon: Icons.map_outlined,
                  title: 'Launch navigation',
                  subtitle: hasNavigationApps
                      ? 'Open the default map app when this launcher starts.'
                      : 'Install or reload a map app before enabling this.',
                  value: launchNavigationWithLauncher,
                  onChanged: hasNavigationApps
                      ? onLaunchNavigationWithLauncherChanged
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsPermissionColumn extends StatefulWidget {
  const _SettingsPermissionColumn();

  @override
  State<_SettingsPermissionColumn> createState() =>
      _SettingsPermissionColumnState();
}

class _SettingsPermissionColumnState extends State<_SettingsPermissionColumn>
    with WidgetsBindingObserver {
  static const String _permissionCachePrefix = 'launcher.permission.';
  static Map<String, _PermissionStatus> _cachedPermissionStatuses =
      _PermissionStatus.defaults;

  Map<String, _PermissionStatus> _permissionStatuses =
      _cachedPermissionStatuses;
  bool _grantInProgress = false;
  Timer? _permissionRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCachedPermissionStatus();
    _schedulePermissionRefresh();
  }

  @override
  void dispose() {
    _permissionRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _schedulePermissionRefresh();
    }
  }

  Future<void> _loadCachedPermissionStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = Map<String, _PermissionStatus>.from(
        _cachedPermissionStatuses,
      );

      for (final key in cached.keys.toList()) {
        final ready = prefs.getBool('$_permissionCachePrefix$key.ready');
        final status = prefs.getString('$_permissionCachePrefix$key.status');
        final systemOnly = prefs.getBool(
          '$_permissionCachePrefix$key.systemOnly',
        );

        if (ready != null || status != null || systemOnly != null) {
          final fallback = cached[key] ?? _PermissionStatus.defaults[key]!;
          cached[key] = _PermissionStatus(
            ready: ready ?? fallback.ready,
            status: status ?? fallback.status,
            systemOnly: systemOnly ?? fallback.systemOnly,
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _permissionStatuses = cached;
        _cachedPermissionStatuses = cached;
      });
    } catch (_) {
      // Keep in-memory cache when SharedPreferences is temporarily unavailable.
    }
  }

  void _schedulePermissionRefresh() {
    _permissionRefreshTimer?.cancel();
    _permissionRefreshTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(_refreshPermissionStatus());
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_refreshPermissionStatus());
      }
    });
  }

  Map<String, dynamic>? _normalizePermissionMap(Object? raw) {
    if (raw is! Map) return null;
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }

  Map<String, _PermissionStatus> _mergePermissionStatuses(
    Map<String, _PermissionStatus> current,
    Map<String, _PermissionStatus> incoming,
  ) {
    final merged = Map<String, _PermissionStatus>.from(
      _PermissionStatus.defaults,
    )..addAll(incoming);

    for (final key in const ['musicAccess', 'systemOverlay']) {
      final previous = current[key];
      final next = merged[key];

      // On BYD head units these checks can briefly return false while Settings
      // or the notification/overlay service is rebinding. Avoid flashing a
      // granted permission back to unchecked when the user just navigates away
      // and returns to Settings.
      if (previous?.ready == true && next?.ready != true) {
        merged[key] = previous!;
      }
    }

    return merged;
  }

  Future<void> _savePermissionStatusCache(
    Map<String, _PermissionStatus> statuses,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final entry in statuses.entries) {
        await prefs.setBool(
          '$_permissionCachePrefix${entry.key}.ready',
          entry.value.ready,
        );
        await prefs.setString(
          '$_permissionCachePrefix${entry.key}.status',
          entry.value.status,
        );
        await prefs.setBool(
          '$_permissionCachePrefix${entry.key}.systemOnly',
          entry.value.systemOnly,
        );
      }
    } catch (_) {}
  }

  Future<void> _applyPermissionStatusMap(
    Object? raw, {
    bool preserveGranted = true,
  }) async {
    final parsed = _PermissionStatus.fromStatusMap(
      _normalizePermissionMap(raw),
    );
    final merged = preserveGranted
        ? _mergePermissionStatuses(_permissionStatuses, parsed)
        : parsed;

    _cachedPermissionStatuses = merged;
    await _savePermissionStatusCache(merged);

    if (!mounted) return;
    setState(() => _permissionStatuses = merged);
  }

  Future<void> _refreshPermissionStatus() async {
    try {
      final data = await _permissionChannel.invokeMethod<Object?>('getStatus');
      await _applyPermissionStatusMap(data);
    } catch (_) {
      // Do not reset to defaults on a transient channel failure. This was the
      // reason Music/Overlay looked checked right after grant, then unchecked
      // after leaving Settings and coming back.
      if (!mounted) return;
      setState(() => _permissionStatuses = _cachedPermissionStatuses);
    }
  }

  Future<void> _grantRecommendedPermissions() async {
    if (_grantInProgress) return;
    setState(() => _grantInProgress = true);
    try {
      final result = await _permissionChannel.invokeMethod<Object?>(
        'grantRecommendedPermissions',
      );
      await _applyPermissionStatusMap(result);
      await _refreshPermissionStatus();
      _permissionRefreshTimer?.cancel();
      _permissionRefreshTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) {
          unawaited(_refreshPermissionStatus());
        }
      });
    } catch (_) {
      await _refreshPermissionStatus();
    } finally {
      if (mounted) {
        setState(() => _grantInProgress = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final music = _permissionStatuses['musicAccess']!;
    final overlay = _permissionStatuses['systemOverlay']!;
    final vehicle = _permissionStatuses['vehicleData']!;
    final navigation = _permissionStatuses['navigationEmbed']!;
    final internet = _permissionStatuses['internet']!;
    final readyCount = [
      music,
      overlay,
      vehicle,
      navigation,
      internet,
    ].where((status) => status.ready).length;
    final allReady = readyCount == 5;

    return _GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SettingsSectionTitle(
            icon: Icons.admin_panel_settings_outlined,
            title: 'System permissions',
            subtitle:
                'One tap setup for music, overlay, vehicle data and launcher bridge.',
          ),
          const SizedBox(height: 16),
          _PermissionSummaryPanel(
            readyCount: readyCount,
            totalCount: 5,
            allReady: allReady,
            statuses: _permissionStatuses,
          ),
          const SizedBox(height: 16),
          _SettingsActionButton(
            icon: allReady
                ? Icons.verified_user_outlined
                : Icons.admin_panel_settings_outlined,
            label: _grantInProgress
                ? 'Checking permissions'
                : allReady
                ? 'Permissions ready'
                : 'Grant all permissions',
            onPressed: _grantRecommendedPermissions,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _PermissionSummaryPanel extends StatelessWidget {
  const _PermissionSummaryPanel({
    required this.readyCount,
    required this.totalCount,
    required this.allReady,
    required this.statuses,
  });

  final int readyCount;
  final int totalCount;
  final bool allReady;
  final Map<String, _PermissionStatus> statuses;

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);
    final borderColor = allReady
        ? const Color(0xFF25D366).withValues(alpha: light ? 0.30 : 0.24)
        : _accentSoftBlue.withValues(alpha: light ? 0.24 : 0.20);
    final backgroundColor = allReady
        ? const Color(0xFF25D366).withValues(alpha: light ? 0.10 : 0.08)
        : _accentSoftBlue.withValues(alpha: light ? 0.10 : 0.07);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                allReady
                    ? Icons.check_circle_outline_rounded
                    : Icons.pending_actions_outlined,
                color: allReady ? const Color(0xFF25D366) : _accentSoftBlue,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  allReady
                      ? 'All permissions are ready'
                      : '$readyCount/$totalCount permissions ready',
                  style: _sharp(
                    context,
                    Theme.of(context).textTheme.titleSmall,
                    color: _textPrimary,
                    weight: FontWeight.w700,
                    size: 14.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PermissionStatusChip(
                label: 'Music',
                status: statuses['musicAccess']!,
              ),
              _PermissionStatusChip(
                label: 'Overlay',
                status: statuses['systemOverlay']!,
              ),
              _PermissionStatusChip(
                label: 'Vehicle',
                status: statuses['vehicleData']!,
              ),
              _PermissionStatusChip(
                label: 'Navigation',
                status: statuses['navigationEmbed']!,
              ),
              _PermissionStatusChip(
                label: 'Internet',
                status: statuses['internet']!,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PermissionStatusChip extends StatelessWidget {
  const _PermissionStatusChip({required this.label, required this.status});

  final String label;
  final _PermissionStatus status;

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);
    final ready = status.ready;
    final color = ready ? const Color(0xFF25D366) : _accentSoftBlue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ready
            ? color.withValues(alpha: light ? 0.11 : 0.10)
            : Colors.white.withValues(alpha: light ? 0.58 : 0.055),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: ready
              ? color.withValues(alpha: light ? 0.26 : 0.22)
              : _tone(
                  context,
                  _textMuted,
                ).withValues(alpha: light ? 0.18 : 0.14),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ready ? Icons.check_rounded : Icons.lock_outline_rounded,
            color: ready ? color : _tone(context, _textMuted),
            size: 14,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: _sharp(
              context,
              Theme.of(context).textTheme.labelSmall,
              color: ready ? _textPrimary : _textMuted,
              weight: FontWeight.w600,
              size: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionStatus {
  const _PermissionStatus({
    required this.ready,
    required this.status,
    this.systemOnly = false,
  });

  final bool ready;
  final String status;
  final bool systemOnly;

  static const defaults = {
    'musicAccess': _PermissionStatus(ready: false, status: 'Needed'),
    'systemOverlay': _PermissionStatus(ready: false, status: 'Needed'),
    'vehicleData': _PermissionStatus(
      ready: false,
      status: 'System only',
      systemOnly: true,
    ),
    'navigationEmbed': _PermissionStatus(
      ready: false,
      status: 'System only',
      systemOnly: true,
    ),
    'internet': _PermissionStatus(ready: true, status: 'Granted'),
  };

  static Map<String, _PermissionStatus> fromStatusMap(
    Map<String, dynamic>? data,
  ) {
    final result = Map<String, _PermissionStatus>.from(defaults);
    if (data == null) return result;

    for (final entry in data.entries) {
      final value = entry.value;
      if (value is Map) {
        result[entry.key] = _PermissionStatus(
          ready: value['ready'] == true,
          status: value['status'] is String
              ? value['status'] as String
              : (value['ready'] == true ? 'Ready' : 'Needed'),
          systemOnly: value['systemOnly'] == true,
        );
      }
    }
    return result;
  }
}

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _accentSoftBlue, size: 21),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: _sharp(
                  context,
                  Theme.of(context).textTheme.titleMedium,
                  color: _textPrimary,
                  weight: FontWeight.w700,
                  size: 16,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _sharp(
                  context,
                  Theme.of(context).textTheme.bodySmall,
                  color: _textMuted,
                  weight: FontWeight.w500,
                  size: 11.5,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VehicleColorSwatch extends StatelessWidget {
  const _VehicleColorSwatch({
    required this.label,
    required this.color,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final Color color;
  final ValueChanged<Color> onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => onTap(color),
      child: Container(
        height: 76,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: selected ? 0.08 : 0.035),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? _accentSoftBlue.withValues(alpha: 0.62)
                : Colors.white.withValues(alpha: 0.06),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.32),
                    blurRadius: 14,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _sharp(
                context,
                Theme.of(context).textTheme.labelSmall,
                color: selected
                    ? (_isLight(context) ? _premiumLightText : _textPrimary)
                    : (_isLight(context) ? _premiumLightMuted : _textMuted),
                weight: FontWeight.w600,
                size: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeModePicker extends StatelessWidget {
  const _ThemeModePicker({required this.selectedMode, required this.onChanged});

  final ThemeMode selectedMode;
  final ValueChanged<ThemeMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);

    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: light
            ? const Color(0xFFE5EDF6).withValues(alpha: 0.72)
            : Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: light
              ? Colors.white.withValues(alpha: 0.88)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          _ThemeModeOption(
            icon: Icons.light_mode_outlined,
            label: 'Light',
            selected: selectedMode == ThemeMode.light,
            onTap: () => onChanged?.call(ThemeMode.light),
          ),
          _ThemeModeOption(
            icon: Icons.dark_mode_outlined,
            label: 'Dark',
            selected: selectedMode == ThemeMode.dark,
            onTap: () => onChanged?.call(ThemeMode.dark),
          ),
          _ThemeModeOption(
            icon: Icons.brightness_auto_outlined,
            label: 'System',
            selected: selectedMode == ThemeMode.system,
            onTap: () => onChanged?.call(ThemeMode.system),
          ),
        ],
      ),
    );
  }
}

class _ThemeModeOption extends StatelessWidget {
  const _ThemeModeOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? _tone(context, _textPrimary)
        : _tone(context, _textMuted);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected
                ? _accentSoftBlue.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: selected
                ? Border.all(color: _accentSoftBlue.withValues(alpha: 0.28))
                : null,
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 17),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: _sharp(
                      context,
                      Theme.of(context).textTheme.labelMedium,
                      color: color,
                      weight: selected ? FontWeight.w700 : FontWeight.w500,
                      size: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RenderQualityPicker extends StatelessWidget {
  const _RenderQualityPicker({
    required this.selectedQuality,
    required this.onChanged,
  });

  final _VehicleRenderQuality selectedQuality;
  final ValueChanged<_VehicleRenderQuality> onChanged;

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);

    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: light
            ? const Color(0xFFE5EDF6).withValues(alpha: 0.72)
            : Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: light
              ? Colors.white.withValues(alpha: 0.88)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          _RenderQualityOption(
            icon: Icons.battery_saver_outlined,
            label: 'Low',
            selected: selectedQuality == _VehicleRenderQuality.low,
            onTap: () => onChanged(_VehicleRenderQuality.low),
          ),
          _RenderQualityOption(
            icon: Icons.tune_outlined,
            label: 'Medium',
            selected: selectedQuality == _VehicleRenderQuality.medium,
            onTap: () => onChanged(_VehicleRenderQuality.medium),
          ),
          _RenderQualityOption(
            icon: Icons.auto_awesome_outlined,
            label: 'High',
            selected: selectedQuality == _VehicleRenderQuality.high,
            onTap: () => onChanged(_VehicleRenderQuality.high),
          ),
        ],
      ),
    );
  }
}

class _RenderQualityOption extends StatelessWidget {
  const _RenderQualityOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? _tone(context, _textPrimary)
        : _tone(context, _textMuted);

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected
                ? _accentSoftBlue.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: selected
                ? Border.all(color: _accentSoftBlue.withValues(alpha: 0.28))
                : null,
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 17),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: _sharp(
                      context,
                      Theme.of(context).textTheme.labelMedium,
                      color: color,
                      weight: selected ? FontWeight.w700 : FontWeight.w500,
                      size: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: light
            ? Colors.white.withValues(alpha: 0.60)
            : Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: light
              ? const Color(0xFFD4DEE9).withValues(alpha: 0.82)
              : Colors.white.withValues(alpha: 0.045),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: _tone(context, _textSecondary), size: 21),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: _sharp(
                    context,
                    Theme.of(context).textTheme.bodyMedium,
                    color: _textPrimary,
                    weight: FontWeight.w600,
                    size: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _sharp(
                    context,
                    Theme.of(context).textTheme.bodySmall,
                    color: _textMuted,
                    weight: FontWeight.w500,
                    size: 11.5,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: _accentSoftBlue,
            activeTrackColor: _accentSoftBlue.withValues(alpha: 0.25),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.status,
    this.highlighted = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String status;
  final bool highlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: highlighted
              ? const Color(0xFF78B7FF).withValues(alpha: 0.09)
              : light
              ? Colors.white.withValues(alpha: 0.58)
              : Colors.black.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: highlighted
                ? _accentSoftBlue.withValues(alpha: 0.22)
                : light
                ? const Color(0xFFD4DEE9).withValues(alpha: 0.82)
                : Colors.white.withValues(alpha: 0.045),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: highlighted
                  ? _accentSoftBlue
                  : _tone(context, _textSecondary),
              size: 21,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                title,
                style: _sharp(
                  context,
                  Theme.of(context).textTheme.bodyMedium,
                  color: _textPrimary,
                  weight: FontWeight.w600,
                  size: 13.5,
                ),
              ),
            ),
            Text(
              status,
              style: _sharp(
                context,
                Theme.of(context).textTheme.labelSmall,
                color: highlighted ? _accentSoftBlue : _textMuted,
                weight: FontWeight.w700,
                size: 11.5,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 5),
              Icon(
                Icons.chevron_right_rounded,
                color: _tone(context, _textMuted),
                size: 18,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsActionButton extends StatelessWidget {
  const _SettingsActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);

    return SizedBox(
      width: double.infinity,
      height: 46,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: _accentSoftBlue.withValues(
            alpha: light ? 0.22 : 0.18,
          ),
          foregroundColor: _tone(context, _textPrimary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          style: _sharp(
            context,
            Theme.of(context).textTheme.labelLarge,
            color: _textPrimary,
            weight: FontWeight.w700,
            size: 13,
          ),
        ),
      ),
    );
  }
}

class _FloatingVehicleControls extends StatelessWidget {
  const _FloatingVehicleControls({required this.view, required this.onRear});

  final _VehicleView view;
  final VoidCallback onRear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_QuickActionStrip(onRear: onRear)],
    );
  }
}

class _QuickActionStrip extends StatelessWidget {
  const _QuickActionStrip({required this.onRear});

  final VoidCallback onRear;

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: light
                ? Colors.white.withValues(alpha: 0.88)
                : const Color(0xFF0B111A).withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: light
                  ? _premiumLightStroke.withValues(alpha: 0.92)
                  : Colors.white.withValues(alpha: 0.075),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: light ? 0.08 : 0.18),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: const Color(
                  0xFF78B7FF,
                ).withValues(alpha: light ? 0.10 : 0.055),
                blurRadius: 24,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _MiniAction(icon: Icons.lock_outline, label: 'Lock'),
              _MiniAction(
                icon: Icons.airport_shuttle_outlined,
                label: 'Trunk',
                onTap: onRear,
              ),
              const _MiniAction(
                icon: Icons.flip_to_front_outlined,
                label: 'Mirrors',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: light ? const Color(0xFF475569) : const Color(0xFFEAF1F8),
              size: 17,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: _sharp(
                context,
                Theme.of(context).textTheme.labelSmall,
                color: light
                    ? const Color(0xFF475569)
                    : const Color(0xFFD8E2ED),
                weight: FontWeight.w600,
                size: 11.5,
                letterSpacing: 0.12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VehicleReveal extends StatelessWidget {
  const _VehicleReveal({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.15, 0.06),
                  radius: 0.68,
                  colors: [
                    const Color(0xFF78B7FF).withValues(alpha: 0.14),
                    const Color(0xFF78B7FF).withValues(alpha: 0.045),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class _VehicleEntrance extends StatefulWidget {
  const _VehicleEntrance({required this.child});

  final Widget child;

  @override
  State<_VehicleEntrance> createState() => _VehicleEntranceState();
}

class _VehicleEntranceState extends State<_VehicleEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 980),
    );

    final fadeCurve = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.02, 0.55, curve: Curves.easeOutCubic),
    );

    _opacity = Tween<double>(begin: 0.0, end: 1).animate(fadeCurve);

    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return Opacity(opacity: _opacity.value, child: child);
      },
    );
  }
}

class _VehicleHero extends StatefulWidget {
  const _VehicleHero({
    required this.enable3dModel,
    required this.cameraOrbit,
    required this.vehicleColor,
    required this.renderQuality,
    required this.roadMotionActive,
    required this.reverseRoadMotion,
    required this.vehicleSpeedKmh,
  });

  final bool enable3dModel;
  final String cameraOrbit;
  final Color vehicleColor;
  final _VehicleRenderQuality renderQuality;
  final bool roadMotionActive;
  final bool reverseRoadMotion;
  final double vehicleSpeedKmh;

  @override
  State<_VehicleHero> createState() => _VehicleHeroState();
}

class _VehicleHeroState extends State<_VehicleHero> {
  WebViewController? _webViewController;
  final List<Timer> _colorRetryTimers = [];
  Timer? _hotspotAutoHideTimer;
  bool _hotspotsVisible = false;
  int _hotspotAnimationSeed = 0;
  _VehicleHotspot? _selectedHotspot;
  final Map<_VehicleHotspot, double> _hotspotLevels = {
    _VehicleHotspot.frontLeftWindow: 0,
    _VehicleHotspot.frontRightWindow: 0,
    _VehicleHotspot.rearLeftWindow: 0,
    _VehicleHotspot.rearRightWindow: 0,
    _VehicleHotspot.sunroof: 0,
    _VehicleHotspot.trunk: 0,
  };

  @override
  void initState() {
    super.initState();
    if (widget.enable3dModel) {
      _scheduleColorApply();
    }
  }

  @override
  void didUpdateWidget(covariant _VehicleHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enable3dModel) {
      _cancelColorTimers();
      return;
    }

    if (widget.roadMotionActive && _selectedHotspot == _VehicleHotspot.trunk) {
      _selectedHotspot = null;
    }

    if (oldWidget.vehicleColor != widget.vehicleColor ||
        oldWidget.enable3dModel != widget.enable3dModel ||
        oldWidget.renderQuality != widget.renderQuality ||
        oldWidget.roadMotionActive != widget.roadMotionActive) {
      _applyVehicleColor();
      _scheduleColorApply();
    }
  }

  @override
  void dispose() {
    _cancelColorTimers();
    _hotspotAutoHideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enable3dModel) {
      return const _VehicleModelPlaceholder();
    }

    final sceneBackground = _vehicleSceneBackground(context);
    final useNativeRenderer =
        _preferNativeVehicleRenderer &&
        defaultTargetPlatform == TargetPlatform.android;
    final focusedOrbit = _focusedCameraOrbit;
    final focusOffset = _focusOffset;
    final focusScale = _focusScale;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _showHotspots,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _DrivingRoadLayer(
            active: widget.roadMotionActive,
            reverse: widget.reverseRoadMotion,
            speedKmh: widget.vehicleSpeedKmh,
          ),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(end: _selectedHotspot == null ? 0 : 1),
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeOutCubic,
            builder: (context, focusT, child) {
              return Transform.translate(
                offset: Offset(
                  focusOffset.dx * focusT,
                  focusOffset.dy * focusT,
                ),
                child: Transform.scale(
                  scale: 1 + (focusScale - 1) * focusT,
                  alignment: Alignment.center,
                  child: child,
                ),
              );
            },
            child: useNativeRenderer
                ? _NativeVehicleScene(
                    asset: _vehicleModelAsset,
                    cameraOrbit: focusedOrbit,
                    vehicleColor: widget.vehicleColor,
                    renderQuality: widget.renderQuality,
                    drivingMode: widget.roadMotionActive,
                    backgroundColor: sceneBackground,
                  )
                : ModelViewer(
                    src: _vehicleModelAsset,
                    alt: '2024 BYD Seal U DM-i 3D model',
                    loading: Loading.eager,
                    reveal: Reveal.auto,
                    backgroundColor: Colors.transparent,
                    cameraControls: true,
                    autoRotate: false,
                    disablePan: true,
                    disableTap: true,
                    disableZoom: true,
                    interactionPrompt: InteractionPrompt.none,
                    cameraOrbit: focusedOrbit,
                    minCameraOrbit: 'auto 42deg 64%',
                    maxCameraOrbit: 'auto 86deg 120%',
                    fieldOfView: '19deg',
                    minFieldOfView: '19deg',
                    maxFieldOfView: '19deg',
                    exposure: 0.78,
                    shadowIntensity: 0.30,
                    relatedCss:
                        'html, body { background: transparent !important; margin: 0; overflow: hidden; } '
                        'model-viewer { background: transparent !important; background-color: transparent !important; '
                        '--poster-color: transparent; }',
                    onWebViewCreated: (controller) {
                      _webViewController = controller;
                      _scheduleColorApply();
                    },
                  ),
          ),
          if (useNativeRenderer) const _NativeSceneLightWash(),
          if (!useNativeRenderer) const _ModelStartupCover(),
          _VehicleHotspotLayer(
            visible: _hotspotsVisible,
            selectedHotspot: _selectedHotspot,
            levels: _hotspotLevels,
            onHotspotTap: _selectHotspot,
            onSetLevel: _setHotspotLevel,
            onDismiss: _hideHotspots,
            animationSeed: _hotspotAnimationSeed,
            allowTrunk: !widget.roadMotionActive,
            cameraOrbit: focusedOrbit,
            focusOffset: focusOffset,
            focusScale: focusScale,
            focusActive: _selectedHotspot != null && !widget.roadMotionActive,
          ),
        ],
      ),
    );
  }

  String get _focusedCameraOrbit {
    if (widget.roadMotionActive) {
      return widget.cameraOrbit;
    }

    final hotspot = _selectedHotspot;
    if (hotspot == null) {
      return widget.cameraOrbit;
    }

    return switch (hotspot) {
      _VehicleHotspot.frontLeftWindow => '312deg 66deg 70%',
      _VehicleHotspot.frontRightWindow => '046deg 66deg 70%',
      _VehicleHotspot.rearLeftWindow => '286deg 66deg 68%',
      _VehicleHotspot.rearRightWindow => '064deg 66deg 68%',
      _VehicleHotspot.sunroof => '0deg 38deg 66%',
      _VehicleHotspot.trunk => '180deg 66deg 69%',
    };
  }

  Offset get _focusOffset {
    if (widget.roadMotionActive) {
      return Offset.zero;
    }

    final hotspot = _selectedHotspot;
    if (hotspot == null) {
      return Offset.zero;
    }

    return switch (hotspot) {
      _VehicleHotspot.frontLeftWindow => const Offset(58, 14),
      _VehicleHotspot.frontRightWindow => const Offset(-58, 14),
      _VehicleHotspot.rearLeftWindow => const Offset(70, 8),
      _VehicleHotspot.rearRightWindow => const Offset(-70, 8),
      _VehicleHotspot.sunroof => const Offset(0, 46),
      _VehicleHotspot.trunk => const Offset(0, 12),
    };
  }

  double get _focusScale {
    if (widget.roadMotionActive) {
      return 1.0;
    }

    final hotspot = _selectedHotspot;
    if (hotspot == null) return 1.0;

    return switch (hotspot) {
      _VehicleHotspot.frontLeftWindow ||
      _VehicleHotspot.frontRightWindow => 1.075,
      _VehicleHotspot.rearLeftWindow ||
      _VehicleHotspot.rearRightWindow => 1.095,
      _VehicleHotspot.sunroof => 1.085,
      _VehicleHotspot.trunk => 1.085,
    };
  }

  void _showHotspots() {
    if (!mounted) return;
    setState(() => _hotspotsVisible = true);
    _restartHotspotAutoHideTimer();
  }

  void _hideHotspots() {
    _hotspotAutoHideTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _hotspotsVisible = false;
      _selectedHotspot = null;
    });
  }

  void _selectHotspot(_VehicleHotspot hotspot) {
    if (widget.roadMotionActive && hotspot == _VehicleHotspot.trunk) {
      return;
    }
    setState(() {
      _hotspotsVisible = true;
      _selectedHotspot = hotspot;
      _hotspotAnimationSeed++;
    });
    _restartHotspotAutoHideTimer();
  }

  void _setHotspotLevel(_VehicleHotspot hotspot, double level) {
    if (widget.roadMotionActive && hotspot == _VehicleHotspot.trunk) {
      return;
    }
    setState(() {
      _hotspotLevels[hotspot] = level.clamp(0.0, 1.0);
      _selectedHotspot = hotspot;
      _hotspotsVisible = true;
    });
    _restartHotspotAutoHideTimer();
  }

  void _restartHotspotAutoHideTimer() {
    _hotspotAutoHideTimer?.cancel();
    _hotspotAutoHideTimer = Timer(const Duration(seconds: 6), _hideHotspots);
  }

  void _scheduleColorApply() {
    _cancelColorTimers();
    for (final delay in const [
      Duration(milliseconds: 450),
      Duration(milliseconds: 1200),
      Duration(milliseconds: 2600),
    ]) {
      _colorRetryTimers.add(Timer(delay, _applyVehicleColor));
    }
  }

  void _cancelColorTimers() {
    for (final timer in _colorRetryTimers) {
      timer.cancel();
    }
    _colorRetryTimers.clear();
  }

  Future<void> _applyVehicleColor() async {
    final controller = _webViewController;
    if (controller == null) {
      return;
    }

    try {
      await controller.runJavaScript(_vehicleColorScript(widget.vehicleColor));
    } on Object {
      // WebView may not be ready while model-viewer is still loading.
    }
  }
}

class _VehicleHotspotLayer extends StatelessWidget {
  const _VehicleHotspotLayer({
    required this.visible,
    required this.selectedHotspot,
    required this.levels,
    required this.onHotspotTap,
    required this.onSetLevel,
    required this.onDismiss,
    required this.animationSeed,
    required this.allowTrunk,
    required this.cameraOrbit,
    required this.focusOffset,
    required this.focusScale,
    required this.focusActive,
  });

  final bool visible;
  final _VehicleHotspot? selectedHotspot;
  final Map<_VehicleHotspot, double> levels;
  final ValueChanged<_VehicleHotspot> onHotspotTap;
  final void Function(_VehicleHotspot hotspot, double level) onSetLevel;
  final VoidCallback onDismiss;
  final int animationSeed;
  final bool allowTrunk;
  final String cameraOrbit;
  final Offset focusOffset;
  final double focusScale;
  final bool focusActive;

  List<_HotspotSpec> _buildProjectedHotspots({
    required BoxConstraints constraints,
    required String cameraOrbit,
    required Offset focusOffset,
    required double focusScale,
  }) {
    final yaw = _cameraOrbitYawRadians(cameraOrbit);
    final pitch = _cameraOrbitPitchDegrees(cameraOrbit);
    final pitchTopDownT = ((72.0 - pitch) / 34.0).clamp(0.0, 1.0);
    final vehicleCenter = Offset(
      constraints.maxWidth * 0.50,
      constraints.maxHeight * (0.455 + pitchTopDownT * 0.035),
    );
    final horizontalRadius =
        constraints.maxWidth * (0.235 + pitchTopDownT * 0.018);
    final lengthRadius =
        constraints.maxHeight * (0.145 + pitchTopDownT * 0.038);
    final heightLift = constraints.maxHeight * (0.155 + pitchTopDownT * 0.030);

    Offset project(double carX, double carY, double carZ) {
      final cosYaw = math.cos(yaw);
      final sinYaw = math.sin(yaw);

      // carX = left/right, carZ = rear/front.  We rotate this top-view point
      // by the current camera yaw, then apply a small height lift for glass / roof.
      // This is intentionally a screen-space projection, because the native
      // renderer and model-viewer do not expose exact 3D-to-2D anchor points.
      final rotatedX = carX * cosYaw - carZ * sinYaw;
      final rotatedZ = carX * sinYaw + carZ * cosYaw;
      final perspective = (1.0 + rotatedZ * 0.10).clamp(0.86, 1.16);
      final local = Offset(
        rotatedX * horizontalRadius / perspective,
        rotatedZ * lengthRadius - carY * heightLift,
      );
      return vehicleCenter + local * focusScale + focusOffset;
    }

    Alignment sideAlignment(double carX, double carZ) {
      final cosYaw = math.cos(yaw);
      final sinYaw = math.sin(yaw);
      final rotatedX = carX * cosYaw - carZ * sinYaw;
      return rotatedX < 0 ? Alignment.centerLeft : Alignment.centerRight;
    }

    final rawSpots = <_HotspotSpec>[
      _HotspotSpec(
        hotspot: _VehicleHotspot.frontLeftWindow,
        label: 'Front Left Window',
        shortLabel: 'FL',
        icon: Icons.window_outlined,
        position: project(-0.50, 0.20, -0.34),
        cardAlignment: sideAlignment(-0.50, -0.34),
      ),
      _HotspotSpec(
        hotspot: _VehicleHotspot.frontRightWindow,
        label: 'Front Right Window',
        shortLabel: 'FR',
        icon: Icons.window_outlined,
        position: project(0.50, 0.20, -0.34),
        cardAlignment: sideAlignment(0.50, -0.34),
      ),
      _HotspotSpec(
        hotspot: _VehicleHotspot.rearLeftWindow,
        label: 'Rear Left Window',
        shortLabel: 'RL',
        icon: Icons.window_outlined,
        position: project(-0.50, 0.19, 0.22),
        cardAlignment: sideAlignment(-0.50, 0.22),
      ),
      _HotspotSpec(
        hotspot: _VehicleHotspot.rearRightWindow,
        label: 'Rear Right Window',
        shortLabel: 'RR',
        icon: Icons.window_outlined,
        position: project(0.50, 0.19, 0.22),
        cardAlignment: sideAlignment(0.50, 0.22),
      ),
      _HotspotSpec(
        hotspot: _VehicleHotspot.sunroof,
        label: 'Sunroof',
        shortLabel: 'Roof',
        icon: Icons.roofing_outlined,
        position: project(0.0, 0.78, -0.02),
        wide: true,
        cardAlignment: Alignment.topCenter,
      ),
      _HotspotSpec(
        hotspot: _VehicleHotspot.trunk,
        label: 'Trunk',
        shortLabel: 'Trunk',
        icon: Icons.airport_shuttle_outlined,
        // The Sealion 6 GLB is oriented with its tail on the negative Z side
        // in this projected overlay. The old +Z anchor placed Trunk near the
        // vehicle nose, so keep this anchor on the rear/tail end instead.
        position: project(0.0, -0.02, -0.92),
        cardAlignment: Alignment.topCenter,
      ),
    ];

    return _spreadOverlappingHotspots(rawSpots, constraints);
  }

  List<_HotspotSpec> _spreadOverlappingHotspots(
    List<_HotspotSpec> spots,
    BoxConstraints constraints,
  ) {
    final adjusted = spots.toList(growable: true);
    const minDistance = 58.0;

    for (var pass = 0; pass < 7; pass++) {
      for (var i = 0; i < adjusted.length; i++) {
        for (var j = i + 1; j < adjusted.length; j++) {
          final a = adjusted[i];
          final b = adjusted[j];
          final delta = b.position - a.position;
          final distance = delta.distance;
          if (distance >= minDistance) continue;

          final direction = distance < 0.01
              ? Offset((j.isEven ? 1 : -1).toDouble(), 0.35)
              : delta / distance;
          final push = (minDistance - distance) * 0.52;
          adjusted[i] = a.copyWith(
            position: _clampHotspotPosition(
              a.position - direction * push,
              constraints,
              a.wide,
            ),
          );
          adjusted[j] = b.copyWith(
            position: _clampHotspotPosition(
              b.position + direction * push,
              constraints,
              b.wide,
            ),
          );
        }
      }
    }

    return adjusted
        .map(
          (spot) => spot.copyWith(
            position: _clampHotspotPosition(
              spot.position,
              constraints,
              spot.wide,
            ),
          ),
        )
        .toList(growable: false);
  }

  Offset _clampHotspotPosition(
    Offset position,
    BoxConstraints constraints,
    bool wide,
  ) {
    final horizontalPadding = wide ? 54.0 : 34.0;
    const verticalPadding = 34.0;
    return Offset(
      position.dx
          .clamp(horizontalPadding, constraints.maxWidth - horizontalPadding)
          .toDouble(),
      position.dy
          .clamp(verticalPadding, constraints.maxHeight - verticalPadding)
          .toDouble(),
    );
  }

  double _cameraOrbitYawRadians(String orbit) {
    final tokens = orbit.trim().split(RegExp(r'\s+'));
    final token = tokens.isEmpty ? '318deg' : tokens.first;
    final numeric = double.tryParse(token.replaceAll('deg', '')) ?? 318.0;
    return numeric * math.pi / 180.0;
  }

  double _cameraOrbitPitchDegrees(String orbit) {
    final tokens = orbit.trim().split(RegExp(r'\s+'));
    if (tokens.length < 2) return 70.0;
    return double.tryParse(tokens[1].replaceAll('deg', '')) ?? 70.0;
  }

  @override
  Widget build(BuildContext context) {
    final selected = !allowTrunk && selectedHotspot == _VehicleHotspot.trunk
        ? null
        : selectedHotspot;

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final spots = _buildProjectedHotspots(
              constraints: constraints,
              cameraOrbit: cameraOrbit,
              focusOffset: focusActive ? focusOffset : Offset.zero,
              focusScale: focusActive ? focusScale : 1.0,
            );
            final visibleSpots = allowTrunk
                ? spots
                : spots
                      .where((spot) => spot.hotspot != _VehicleHotspot.trunk)
                      .toList(growable: false);

            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: onDismiss,
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0.12, -0.10),
                          radius: 0.62,
                          colors: [
                            (_isLight(context) ? Colors.white : Colors.black)
                                .withValues(
                                  alpha: _isLight(context) ? 0.12 : 0.10,
                                ),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (selected != null)
                  _HotspotFocusRipple(
                    key: ValueKey('ripple-${selected.name}-$animationSeed'),
                    position: visibleSpots
                        .firstWhere((spot) => spot.hotspot == selected)
                        .position,
                  ),
                for (final spec in visibleSpots)
                  Positioned(
                    left: spec.position.dx - (spec.wide ? 42 : 24),
                    top: spec.position.dy - (spec.wide ? 18 : 24),
                    child: _VehicleHotspotButton(
                      spec: spec,
                      selected: spec.hotspot == selected,
                      progress: levels[spec.hotspot] ?? 0,
                      onTap: () => onHotspotTap(spec.hotspot),
                      animationSeed: animationSeed,
                    ),
                  ),
                if (selected != null)
                  _HotspotControlCardPositioner(
                    selected: visibleSpots.firstWhere(
                      (spot) => spot.hotspot == selected,
                    ),
                    constraints: constraints,
                    progress: levels[selected] ?? 0,
                    onSetLevel: (level) => onSetLevel(selected, level),
                    animationSeed: animationSeed,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HotspotFocusRipple extends StatelessWidget {
  const _HotspotFocusRipple({super.key, required this.position});

  final Offset position;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx - 56,
      top: position.dy - 56,
      width: 112,
      height: 112,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 620),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Opacity(
              opacity: (1 - value).clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 0.45 + value * 1.15,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          (_isLight(context)
                                  ? const Color(0xFF5AA9FF)
                                  : _accentSoftBlue)
                              .withValues(alpha: 0.72),
                      width: 1.4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (_isLight(context)
                                    ? const Color(0xFF5AA9FF)
                                    : _accentSoftBlue)
                                .withValues(
                                  alpha: _isLight(context) ? 0.18 : 0.28,
                                ),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HotspotSpec {
  const _HotspotSpec({
    required this.hotspot,
    required this.label,
    required this.shortLabel,
    required this.icon,
    required this.position,
    required this.cardAlignment,
    this.wide = false,
  });

  final _VehicleHotspot hotspot;
  final String label;
  final String shortLabel;
  final IconData icon;
  final Offset position;
  final Alignment cardAlignment;
  final bool wide;

  _HotspotSpec copyWith({Offset? position, Alignment? cardAlignment}) {
    return _HotspotSpec(
      hotspot: hotspot,
      label: label,
      shortLabel: shortLabel,
      icon: icon,
      position: position ?? this.position,
      cardAlignment: cardAlignment ?? this.cardAlignment,
      wide: wide,
    );
  }
}

class _VehicleHotspotButton extends StatelessWidget {
  const _VehicleHotspotButton({
    required this.spec,
    required this.selected,
    required this.progress,
    required this.onTap,
    required this.animationSeed,
  });

  final _HotspotSpec spec;
  final bool selected;
  final double progress;
  final VoidCallback onTap;
  final int animationSeed;

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);
    final width = spec.wide ? 84.0 : 48.0;
    final height = spec.wide ? 36.0 : 48.0;

    return TweenAnimationBuilder<double>(
      key: ValueKey('${spec.hotspot.name}-$selected-$animationSeed'),
      tween: Tween<double>(begin: selected ? 0.55 : 0, end: selected ? 1 : 0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        final tapPulse = selected ? (1 - value).clamp(0.0, 1.0) : 0.0;
        return Transform.scale(
          scale: 0.92 + value * 0.12 + tapPulse * 0.18,
          child: child,
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: light
                  ? RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: selected ? 0.98 : 0.90),
                        const Color(0xFFEAF3FC).withValues(alpha: 0.92),
                      ],
                    )
                  : RadialGradient(
                      colors: [
                        _accentSoftBlue.withValues(
                          alpha: selected ? 0.44 : 0.28,
                        ),
                        const Color(0xFF08111B).withValues(alpha: 0.72),
                      ],
                    ),
              border: Border.all(
                color: light
                    ? const Color(
                        0xFF9ACBFF,
                      ).withValues(alpha: selected ? 0.86 : 0.58)
                    : _accentSoftBlue.withValues(alpha: selected ? 0.76 : 0.44),
                width: selected ? 1.6 : 1.1,
              ),
              boxShadow: [
                BoxShadow(
                  color: light
                      ? const Color(
                          0xFF5AA9FF,
                        ).withValues(alpha: selected ? 0.24 : 0.14)
                      : _accentSoftBlue.withValues(
                          alpha: selected ? 0.44 : 0.26,
                        ),
                  blurRadius: selected ? 24 : 16,
                  spreadRadius: selected ? 2 : 0,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: light ? 0.12 : 0.22),
                  blurRadius: light ? 20 : 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: progress),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  builder: (context, animatedProgress, _) {
                    return CircularProgressIndicator(
                      value: animatedProgress,
                      strokeWidth: 2.2,
                      color: const Color(0xFF64E58A),
                      backgroundColor:
                          (light ? const Color(0xFFD6E5F4) : Colors.white)
                              .withValues(alpha: light ? 0.86 : 0.10),
                    );
                  },
                ),
                spec.wide
                    ? Text(
                        spec.shortLabel,
                        style: _sharp(
                          context,
                          Theme.of(context).textTheme.labelSmall,
                          color: light ? const Color(0xFF1F4F7A) : _textPrimary,
                          weight: FontWeight.w800,
                          size: 11,
                          letterSpacing: 0.4,
                        ),
                      )
                    : Icon(
                        spec.icon,
                        color: light
                            ? const Color(0xFF1F4F7A)
                            : _tone(context, _textPrimary),
                        size: 20,
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HotspotControlCardPositioner extends StatelessWidget {
  const _HotspotControlCardPositioner({
    required this.selected,
    required this.constraints,
    required this.progress,
    required this.onSetLevel,
    required this.animationSeed,
  });

  final _HotspotSpec selected;
  final BoxConstraints constraints;
  final double progress;
  final ValueChanged<double> onSetLevel;
  final int animationSeed;

  @override
  Widget build(BuildContext context) {
    const cardWidth = 236.0;
    final placeRight = selected.position.dx < constraints.maxWidth * 0.56;
    final left =
        (placeRight
                ? (selected.position.dx + 34).clamp(
                    12.0,
                    constraints.maxWidth - cardWidth - 12,
                  )
                : (selected.position.dx - cardWidth - 34).clamp(
                    12.0,
                    constraints.maxWidth - cardWidth - 12,
                  ))
            .toDouble();
    final top = (selected.position.dy - 58)
        .clamp(12.0, constraints.maxHeight - 146.0)
        .toDouble();

    return Positioned(
      left: left,
      top: top,
      width: cardWidth,
      child: _HotspotControlCard(
        spec: selected,
        progress: progress,
        onSetLevel: onSetLevel,
        animationSeed: animationSeed,
      ),
    );
  }
}

class _HotspotControlCard extends StatelessWidget {
  const _HotspotControlCard({
    required this.spec,
    required this.progress,
    required this.onSetLevel,
    required this.animationSeed,
  });

  final _HotspotSpec spec;
  final double progress;
  final ValueChanged<double> onSetLevel;
  final int animationSeed;

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);

    return TweenAnimationBuilder<double>(
      key: ValueKey('card-${spec.hotspot.name}-$animationSeed'),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - value)),
            child: Transform.scale(
              scale: 0.96 + value * 0.04,
              alignment: Alignment.topCenter,
              child: child,
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            decoration: BoxDecoration(
              color: light
                  ? Colors.white.withValues(alpha: 0.88)
                  : const Color(0xFF07101A).withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: light
                    ? _premiumLightStroke.withValues(alpha: 0.90)
                    : Colors.white.withValues(alpha: 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: light ? 0.10 : 0.22),
                  blurRadius: 26,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _accentSoftBlue.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(spec.icon, color: _accentSoftBlue, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            spec.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _sharp(
                              context,
                              Theme.of(context).textTheme.labelLarge,
                              color: _textPrimary,
                              weight: FontWeight.w800,
                              size: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${(progress * 100).round()}% open',
                            style: _sharp(
                              context,
                              Theme.of(context).textTheme.labelSmall,
                              color: _textMuted,
                              weight: FontWeight.w600,
                              size: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 7,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14,
                    ),
                  ),
                  child: Slider(
                    value: progress,
                    min: 0,
                    max: 1,
                    onChanged: onSetLevel,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: _HotspotActionButton(
                        label: 'Close',
                        onTap: () => onSetLevel(0),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HotspotActionButton(
                        label: 'Open',
                        highlighted: true,
                        onTap: () => onSetLevel(1),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HotspotActionButton extends StatelessWidget {
  const _HotspotActionButton({
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: highlighted
              ? _accentSoftBlue.withValues(alpha: 0.24)
              : Colors.white.withValues(alpha: _isLight(context) ? 0.52 : 0.08),
          foregroundColor: _tone(context, _textPrimary),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: onTap,
        child: Text(
          label,
          style: _sharp(
            context,
            Theme.of(context).textTheme.labelSmall,
            color: _textPrimary,
            weight: FontWeight.w800,
            size: 11.5,
          ),
        ),
      ),
    );
  }
}

class _NativeVehicleScene extends StatefulWidget {
  const _NativeVehicleScene({
    required this.asset,
    required this.cameraOrbit,
    required this.vehicleColor,
    required this.renderQuality,
    required this.drivingMode,
    required this.backgroundColor,
  });

  final String asset;
  final String cameraOrbit;
  final Color vehicleColor;
  final _VehicleRenderQuality renderQuality;
  final bool drivingMode;
  final Color backgroundColor;

  @override
  State<_NativeVehicleScene> createState() => _NativeVehicleSceneState();
}

class _NativeVehicleSceneState extends State<_NativeVehicleScene>
    with SingleTickerProviderStateMixin {
  static const MethodChannel _channel = MethodChannel(
    'byd/native_vehicle_texture',
  );

  int? _textureId;
  Size? _textureSize;
  Object? _error;
  late _NativeOrbit _orbit;
  late final AnimationController _orbitController;
  _NativeOrbit? _orbitStart;
  _NativeOrbit? _orbitTarget;

  @override
  void initState() {
    super.initState();
    _orbit = _NativeOrbit.parse(widget.cameraOrbit);
    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    )..addListener(_tickOrbitAnimation);
  }

  @override
  void didUpdateWidget(covariant _NativeVehicleScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cameraOrbit != widget.cameraOrbit) {
      _animateOrbitTo(_NativeOrbit.parse(widget.cameraOrbit));
    } else if (!oldWidget.drivingMode && widget.drivingMode) {
      _animateOrbitTo(_NativeOrbit.parse(widget.cameraOrbit));
    }
    if (oldWidget.vehicleColor != widget.vehicleColor) {
      _updateNativeTexture();
    }
    if (oldWidget.asset != widget.asset ||
        oldWidget.renderQuality != widget.renderQuality) {
      _recreateForCurrentSize();
    }
  }

  @override
  void dispose() {
    _orbitController.dispose();
    _disposeNativeTexture();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final renderScale = _nativeRenderScale(context, widget.renderQuality);
        final size = Size(
          (constraints.maxWidth * renderScale).clamp(1.0, 4096.0),
          (constraints.maxHeight * renderScale).clamp(1.0, 4096.0),
        );
        if (_textureSize != size && size.width > 1 && size.height > 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _createNativeTexture(size);
            }
          });
        }

        final textureId = _textureId;
        if (textureId != null) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: widget.drivingMode ? null : _handleOrbitDrag,
            child: Texture(textureId: textureId),
          );
        }

        if (_error != null) {
          return ModelViewer(
            src: widget.asset,
            alt: '2024 BYD Seal U DM-i 3D model',
            loading: Loading.eager,
            reveal: Reveal.auto,
            backgroundColor: Colors.transparent,
            cameraControls: true,
            autoRotate: false,
            disablePan: true,
            disableTap: true,
            disableZoom: true,
            interactionPrompt: InteractionPrompt.none,
            cameraOrbit: widget.cameraOrbit,
            fieldOfView: '19deg',
            exposure: 0.78,
            shadowIntensity: 0.30,
            relatedCss:
                'html, body { background: transparent !important; margin: 0; overflow: hidden; } '
                'model-viewer { background: transparent !important; background-color: transparent !important; '
                '--poster-color: transparent; }',
          );
        }

        return const SizedBox.expand();
      },
    );
  }

  Future<void> _recreateForCurrentSize() async {
    final size = _textureSize;
    if (size != null) {
      await _createNativeTexture(size);
    }
  }

  Future<void> _createNativeTexture(Size size) async {
    _textureSize = size;
    await _disposeNativeTexture();
    try {
      final textureId = await _channel.invokeMethod<int>('create', {
        'asset': widget.asset,
        'cameraOrbit': _orbit.toCameraOrbit(),
        'color': widget.vehicleColor.toARGB32(),
        'backgroundColor': widget.backgroundColor.toARGB32(),
        'quality': widget.renderQuality.name,
        'width': size.width.round(),
        'height': size.height.round(),
      });
      if (!mounted) {
        if (textureId != null) {
          await _channel.invokeMethod<void>('dispose', {
            'textureId': textureId,
          });
        }
        return;
      }
      setState(() {
        _textureId = textureId;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _textureId = null;
        _error = error;
      });
    }
  }

  Future<void> _disposeNativeTexture() async {
    final textureId = _textureId;
    _textureId = null;
    if (textureId != null) {
      try {
        await _channel.invokeMethod<void>('dispose', {'textureId': textureId});
      } on Object {
        // Native texture may already be gone after an Android lifecycle change.
      }
    }
  }

  void _handleOrbitDrag(DragUpdateDetails details) {
    _orbitController.stop();
    _orbit = _orbit.dragged(details.delta);
    _updateNativeTexture();
  }

  void _animateOrbitTo(_NativeOrbit target) {
    _orbitStart = _orbit;
    _orbitTarget = target;
    _orbitController.forward(from: 0);
  }

  void _tickOrbitAnimation() {
    final start = _orbitStart;
    final target = _orbitTarget;
    if (start == null || target == null) {
      return;
    }
    final t = Curves.easeInOutCubic.transform(_orbitController.value);
    _orbit = _NativeOrbit.lerp(start, target, t);
    _updateNativeTexture();
  }

  Future<void> _updateNativeTexture() async {
    final textureId = _textureId;
    if (textureId == null) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('update', {
        'textureId': textureId,
        'cameraOrbit': _orbit.toCameraOrbit(),
        'color': widget.vehicleColor.toARGB32(),
      });
    } on Object {
      // Renderer updates are best-effort; Android can drop the texture on lifecycle changes.
    }
  }
}

double _nativeRenderScale(BuildContext context, _VehicleRenderQuality quality) {
  final deviceScale = MediaQuery.devicePixelRatioOf(context);
  return switch (quality) {
    _VehicleRenderQuality.low => (deviceScale * 0.55).clamp(0.70, 1.00),
    _VehicleRenderQuality.medium => (deviceScale * 0.72).clamp(0.85, 1.25),
    _VehicleRenderQuality.high => (deviceScale * 0.90).clamp(1.00, 1.55),
  }.toDouble();
}

class _NativeOrbit {
  const _NativeOrbit({
    required this.theta,
    required this.phi,
    required this.radiusPercent,
  });

  factory _NativeOrbit.parse(String value) {
    final parts = value.split(' ');
    double clean(int index, String suffix, double fallback) {
      return double.tryParse(
            parts.elementAtOrNull(index)?.replaceAll(suffix, '') ?? '',
          ) ??
          fallback;
    }

    return _NativeOrbit(
      theta: clean(0, 'deg', 318),
      phi: clean(1, 'deg', 70),
      radiusPercent: clean(2, '%', 86),
    );
  }

  static _NativeOrbit lerp(_NativeOrbit start, _NativeOrbit end, double t) {
    final thetaDelta = ((end.theta - start.theta + 540) % 360) - 180;
    return _NativeOrbit(
      theta: (start.theta + thetaDelta * t) % 360,
      phi: lerpDouble(start.phi, end.phi, t) ?? end.phi,
      radiusPercent:
          lerpDouble(start.radiusPercent, end.radiusPercent, t) ??
          end.radiusPercent,
    );
  }

  final double theta;
  final double phi;
  final double radiusPercent;

  _NativeOrbit dragged(Offset delta) {
    return _NativeOrbit(
      theta: (theta - delta.dx * 0.32) % 360,
      phi: (phi + delta.dy * 0.18).clamp(42.0, 82.0),
      radiusPercent: radiusPercent,
    );
  }

  String toCameraOrbit() {
    return '${theta.toStringAsFixed(2)}deg ${phi.toStringAsFixed(2)}deg '
        '${radiusPercent.toStringAsFixed(2)}%';
  }
}

Color _vehicleSceneBackground(BuildContext context) {
  return _isLight(context) ? const Color(0xFFEAF2FA) : const Color(0xFF070B12);
}

class _DrivingRoadLayer extends StatefulWidget {
  const _DrivingRoadLayer({
    required this.active,
    required this.reverse,
    required this.speedKmh,
  });

  final bool active;
  final bool reverse;
  final double speedKmh;

  @override
  State<_DrivingRoadLayer> createState() => _DrivingRoadLayerState();
}

class _DrivingRoadLayerState extends State<_DrivingRoadLayer>
    with TickerProviderStateMixin {
  late final AnimationController _revealController;
  late final AnimationController _motionController;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    );
    _motionController = AnimationController(
      vsync: this,
      duration: _roadMotionDuration(widget.speedKmh),
    );

    if (widget.active) {
      _revealController.value = 1;
      _motionController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _DrivingRoadLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.speedKmh != oldWidget.speedKmh ||
        widget.reverse != oldWidget.reverse) {
      _motionController.duration = _roadMotionDuration(widget.speedKmh);
      if (widget.active && !_motionController.isAnimating) {
        _motionController.repeat();
      }
    }

    if (widget.active == oldWidget.active) {
      return;
    }

    if (widget.active) {
      Future<void>.delayed(const Duration(milliseconds: 360), () {
        if (!mounted || !widget.active) {
          return;
        }
        _revealController.forward();
        _motionController.repeat();
      });
    } else {
      _revealController.reverse();
      _motionController.stop();
    }
  }

  @override
  void dispose() {
    _revealController.dispose();
    _motionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: Listenable.merge([_revealController, _motionController]),
        builder: (context, _) {
          final opacity = Curves.easeOutCubic.transform(
            _revealController.value,
          );

          if (opacity <= 0.001) {
            return const SizedBox.expand();
          }

          return Opacity(
            opacity: opacity,
            child: CustomPaint(
              painter: _DrivingRoadPainter(
                progress: _motionController.value,
                light: _isLight(context),
                reverse: widget.reverse,
              ),
            ),
          );
        },
      ),
    );
  }
}

Duration _roadMotionDuration(double speedKmh) {
  final speed = speedKmh.clamp(0, 120).toDouble();
  final milliseconds = lerpDouble(1500, 460, speed / 120)!.round();
  return Duration(milliseconds: milliseconds);
}

class _DrivingRoadPainter extends CustomPainter {
  const _DrivingRoadPainter({
    required this.progress,
    required this.light,
    this.reverse = false,
  });

  final double progress;
  final bool light;
  final bool reverse;

  @override
  void paint(Canvas canvas, Size size) {
    final motionProgress = reverse ? 1.0 - progress : progress;
    final glowCenter = Offset(size.width * 0.55, size.height * 0.52);
    final glowPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              _accentSoftBlue.withValues(alpha: light ? 0.18 : 0.24),
              _accentSoftBlue.withValues(alpha: light ? 0.055 : 0.075),
              Colors.transparent,
            ],
            stops: const [0.0, 0.42, 1.0],
          ).createShader(
            Rect.fromCircle(
              center: glowCenter,
              radius: size.shortestSide * 0.50,
            ),
          );
    canvas.drawRect(Offset.zero & size, glowPaint);

    // Road perspective is tuned to sit under the rear-driving camera view.
    // Wider far end + lower vanishing point avoids the old "runway triangle" feel
    // and makes the vehicle look planted on the surface.
    final vanish = Offset(size.width * 0.56, size.height * 0.27);
    final near = Offset(size.width * 0.56, size.height * 1.18);
    const roadPerp = Offset(1.0, 0.0);

    Offset centerAt(double t) {
      final eased = Curves.easeIn.transform(t);
      return Offset(
        lerpDouble(vanish.dx, near.dx, eased)!,
        lerpDouble(vanish.dy, near.dy, eased)!,
      );
    }

    double halfWidthAt(double t) =>
        lerpDouble(size.width * 0.13, size.width * 0.40, t)!;

    Offset roadPoint(double t, double side) {
      final center = centerAt(t);
      final halfWidth = halfWidthAt(t);
      return Offset(
        center.dx + roadPerp.dx * halfWidth * side,
        center.dy + roadPerp.dy * halfWidth * side,
      );
    }

    final roadPath = Path()
      ..moveTo(roadPoint(1, -1).dx, roadPoint(1, -1).dy)
      ..lineTo(roadPoint(0, -1).dx, roadPoint(0, -1).dy)
      ..quadraticBezierTo(
        vanish.dx,
        vanish.dy - size.height * 0.012,
        roadPoint(0, 1).dx,
        roadPoint(0, 1).dy,
      )
      ..lineTo(roadPoint(1, 1).dx, roadPoint(1, 1).dy)
      ..close();

    final roadPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: light
            ? [
                const Color(0xFFCBD8E5).withValues(alpha: 0.12),
                const Color(0xFF8FA2B7).withValues(alpha: 0.23),
              ]
            : [
                const Color(0xFF101C28).withValues(alpha: 0.18),
                const Color(0xFF02070D).withValues(alpha: 0.38),
              ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(roadPath, roadPaint);

    final vehicleContactCenter = Offset(size.width * 0.56, size.height * 0.705);
    final softShadowPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              Colors.black.withValues(alpha: light ? 0.13 : 0.28),
              Colors.black.withValues(alpha: light ? 0.055 : 0.13),
              Colors.transparent,
            ],
            stops: const [0.0, 0.48, 1.0],
          ).createShader(
            Rect.fromCenter(
              center: vehicleContactCenter,
              width: size.width * 0.34,
              height: size.height * 0.16,
            ),
          );
    canvas.drawOval(
      Rect.fromCenter(
        center: vehicleContactCenter,
        width: size.width * 0.34,
        height: size.height * 0.16,
      ),
      softShadowPaint,
    );

    final tireShadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: light ? 0.18 : 0.34)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas
      ..drawOval(
        Rect.fromCenter(
          center: Offset(size.width * 0.475, size.height * 0.705),
          width: size.width * 0.105,
          height: size.height * 0.055,
        ),
        tireShadowPaint,
      )
      ..drawOval(
        Rect.fromCenter(
          center: Offset(size.width * 0.645, size.height * 0.705),
          width: size.width * 0.105,
          height: size.height * 0.055,
        ),
        tireShadowPaint,
      );

    final edgePaint = Paint()
      ..color = _accentSoftBlue.withValues(alpha: light ? 0.05 : 0.065)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    canvas
      ..drawLine(roadPoint(0, -1), roadPoint(1, -1), edgePaint)
      ..drawLine(roadPoint(0, 1), roadPoint(1, 1), edgePaint);

    canvas.save();
    canvas.clipPath(roadPath);

    final lanePaint = Paint()
      ..color = (light ? const Color(0xFF31516F) : Colors.white).withValues(
        alpha: light ? 0.26 : 0.22,
      )
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    for (var i = -2; i < 7; i++) {
      final t = ((i + motionProgress * 2.2) / 7).clamp(0.0, 1.0);
      final center = centerAt(t);
      final segment = lerpDouble(7, 48, t)!;
      final distanceFade = Curves.easeOut.transform(t).clamp(0.0, 1.0);
      final nearFade = (1.0 - ((t - 0.80).clamp(0.0, 0.20) / 0.20)).clamp(
        0.0,
        1.0,
      );
      final alpha = distanceFade * nearFade;
      lanePaint.color = (light ? const Color(0xFF31516F) : Colors.white)
          .withValues(alpha: (light ? 0.30 : 0.22) * alpha);
      canvas.drawLine(
        Offset(center.dx, center.dy - segment * 0.50),
        Offset(center.dx, center.dy + segment * 0.50),
        lanePaint,
      );
    }

    final speedPaint = Paint()
      ..color = _accentSoftBlue.withValues(alpha: light ? 0.16 : 0.13)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 8; i++) {
      final t = ((i / 8) + motionProgress) % 1.0;
      final left = roadPoint(t, -1);
      final right = roadPoint(t, 1);
      canvas.drawLine(left, left + const Offset(-22, -34), speedPaint);
      canvas.drawLine(right, right + const Offset(22, -34), speedPaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DrivingRoadPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.light != light ||
        oldDelegate.reverse != reverse;
  }
}

class _NativeSceneLightWash extends StatelessWidget {
  const _NativeSceneLightWash();

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);

    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.04, 0.00),
            radius: 0.86,
            colors: light
                ? [
                    Colors.white.withValues(alpha: 0.06),
                    _accentSoftBlue.withValues(alpha: 0.018),
                    Colors.transparent,
                  ]
                : [
                    _accentSoftBlue.withValues(alpha: 0.055),
                    const Color(0xFF1A2A3A).withValues(alpha: 0.025),
                    Colors.transparent,
                  ],
            stops: const [0.0, 0.44, 1.0],
          ),
        ),
      ),
    );
  }
}

String _vehicleColorScript(Color color) {
  final argb = color.toARGB32();
  final r = ((argb >> 16) & 0xFF) / 255.0;
  final g = ((argb >> 8) & 0xFF) / 255.0;
  final b = (argb & 0xFF) / 255.0;

  return '''
(function() {
  const targetColor = [$r, $g, $b, 1.0];
  const skip = ['glass', 'window', 'tire', 'tyre', 'rubber', 'wheel', 'rim',
    'chrome', 'light', 'lamp', 'interior', 'seat', 'logo', 'plate', 'black'];
  const prefer = ['body', 'paint', 'carpaint', 'exterior', 'shell', 'door',
    'hood', 'bonnet', 'bumper', 'fender'];

  function shouldPaint(material) {
    const name = (material.name || '').toLowerCase();
    if (skip.some((part) => name.includes(part))) return false;
    return prefer.some((part) => name.includes(part));
  }

  function applyColor() {
    const viewer = document.querySelector('model-viewer');
    if (!viewer || !viewer.model || !viewer.model.materials) return false;

    let changed = 0;
    for (const material of viewer.model.materials) {
      const pbr = material.pbrMetallicRoughness;
      if (!pbr || !shouldPaint(material)) continue;
      pbr.setBaseColorFactor(targetColor);
      if (pbr.setMetallicFactor) pbr.setMetallicFactor(0.75);
      if (pbr.setRoughnessFactor) pbr.setRoughnessFactor(0.34);
      changed++;
    }

    if (changed === 0) {
      for (const material of viewer.model.materials) {
        const name = (material.name || '').toLowerCase();
        const pbr = material.pbrMetallicRoughness;
        if (!pbr || skip.some((part) => name.includes(part))) continue;
        pbr.setBaseColorFactor(targetColor);
        if (pbr.setMetallicFactor) pbr.setMetallicFactor(0.75);
        if (pbr.setRoughnessFactor) pbr.setRoughnessFactor(0.34);
        changed++;
        if (changed >= 2) break;
      }
    }

    return changed > 0;
  }

  if (!applyColor()) {
    const viewer = document.querySelector('model-viewer');
    if (viewer) viewer.addEventListener('load', applyColor, { once: true });
    setTimeout(applyColor, 500);
    setTimeout(applyColor, 1500);
  }
})();
''';
}

class _ModelStartupCover extends StatefulWidget {
  const _ModelStartupCover();

  @override
  State<_ModelStartupCover> createState() => _ModelStartupCoverState();
}

class _ModelStartupCoverState extends State<_ModelStartupCover> {
  bool _visible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _hideTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) {
        setState(() => _visible = false);
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.10, 0.08),
              radius: 0.86,
              colors: light
                  ? [
                      _accentSoftBlue.withValues(alpha: 0.10),
                      Colors.white.withValues(alpha: 0.58),
                      Colors.transparent,
                    ]
                  : [
                      _accentSoftBlue.withValues(alpha: 0.13),
                      const Color(0xFF101823).withValues(alpha: 0.54),
                      Colors.transparent,
                    ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VehicleModelPlaceholder extends StatelessWidget {
  const _VehicleModelPlaceholder();

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);

    return Center(
      child: Container(
        width: 520,
        height: 300,
        decoration: BoxDecoration(
          color: light
              ? Colors.white.withValues(alpha: 0.72)
              : const Color(0xFF111923),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: light ? const Color(0xFFD4DEE9) : const Color(0xFF263241),
          ),
        ),
        child: const Icon(
          Icons.directions_car_filled,
          size: 150,
          color: Color(0xFF45A3FF),
        ),
      ),
    );
  }
}

class _BottomTabs extends StatelessWidget {
  const _BottomTabs({required this.activeTab, required this.onTabChanged});

  final _LauncherTab activeTab;
  final ValueChanged<_LauncherTab> onTabChanged;

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          height: 52,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: light
                ? Colors.white.withValues(alpha: 0.88)
                : const Color(0xFF07101A).withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: light
                  ? _premiumLightStroke.withValues(alpha: 0.95)
                  : Colors.white.withValues(alpha: 0.07),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: light ? 0.10 : 0.26),
                blurRadius: 30,
                offset: const Offset(0, 14),
              ),
              BoxShadow(
                color: _accentSoftBlue.withValues(alpha: light ? 0.10 : 0.05),
                blurRadius: 26,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BottomTab(
                icon: Icons.directions_car_filled_outlined,
                label: 'Vehicle',
                selected: activeTab == _LauncherTab.status,
                onTap: () => onTabChanged(_LauncherTab.status),
              ),
              _BottomTab(
                icon: Icons.navigation_outlined,
                label: 'Navigation',
                selected: activeTab == _LauncherTab.map,
                onTap: () => onTabChanged(_LauncherTab.map),
              ),
              _BottomTab(
                icon: Icons.settings_outlined,
                label: 'Settings',
                selected: activeTab == _LauncherTab.settings,
                onTap: () => onTabChanged(_LauncherTab.settings),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomTab extends StatelessWidget {
  const _BottomTab({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);
    final color = selected
        ? (light ? const Color(0xFF1D4F86) : _tone(context, Colors.white))
        : _tone(context, const Color(0xFF9FAEBE));

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: selected ? 132 : 116,
        height: 42,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: light
                      ? [
                          const Color(0xFFFFFFFF).withValues(alpha: 0.98),
                          const Color(0xFFE5F2FF).withValues(alpha: 0.98),
                        ]
                      : [
                          const Color(0xFF233040).withValues(alpha: 0.96),
                          const Color(0xFF121C28).withValues(alpha: 0.96),
                        ],
                )
              : null,
          border: selected
              ? Border.all(
                  color: light
                      ? const Color(0xFF78B7FF).withValues(alpha: 0.38)
                      : Colors.white.withValues(alpha: 0.08),
                  width: 1,
                )
              : null,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(
                      0xFF78B7FF,
                    ).withValues(alpha: light ? 0.20 : 0.12),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: light ? 0.06 : 0.18),
                    blurRadius: light ? 16 : 12,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: _sharp(
                    context,
                    Theme.of(context).textTheme.titleMedium,
                    color: color,
                    weight: selected ? FontWeight.w600 : FontWeight.w500,
                    size: 14.5,
                    letterSpacing: 0.14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.showBorder = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: light ? 14 : 14,
          sigmaY: light ? 14 : 14,
        ),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: light
                  ? [
                      const Color(0xFFFFFFFF).withValues(alpha: 0.88),
                      const Color(0xFFEAF2FA).withValues(alpha: 0.74),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.060),
                      Colors.white.withValues(alpha: 0.030),
                    ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: showBorder
                ? Border.all(
                    color: light
                        ? const Color(0xFFE7EEF6).withValues(alpha: 0.96)
                        : Colors.white.withValues(alpha: 0.065),
                    width: light ? 1.1 : 1,
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: light ? 0.055 : 0.13),
                blurRadius: light ? 20 : 18,
                offset: Offset(0, light ? 8 : 8),
              ),
              if (light)
                BoxShadow(
                  color: _accentSoftBlue.withValues(alpha: 0.055),
                  blurRadius: 18,
                  spreadRadius: -4,
                ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

const String _defaultVehicleModelAsset =
    'assets/models/2024_byd_seal_u_dm-i.glb';
const bool _preferNativeVehicleRenderer = true;
const String _themeModePreferenceKey = 'launcher.themeMode';
const String _languagePreferenceKey = 'launcher.language';
const String _vehicleModelPreferenceKey = 'launcher.vehicleModelAsset';
const String _vehicleColorPreferenceKey = 'launcher.vehicleColor';
const String _renderQualityPreferenceKey = 'launcher.renderQuality';
const String _lightEffectEnabledPreferenceKey = 'launcher.lightEffectEnabled';
const String _radarEffectEnabledPreferenceKey = 'launcher.radarEffectEnabled';
const String _debugModePreferenceKey = 'launcher.debugMode';
const String _layoutModePreferenceKey = 'launcher.layoutMode';
const String _landscapeSidebarPositionPreferenceKey =
    'launcher.landscapeSidebarPosition';
const String _navigationDefaultPackagePreferenceKey =
    'launcher.navigation.defaultPackage';
const String _launchNavigationWithLauncherPreferenceKey =
    'launcher.navigation.launchWithLauncher';
const String _favoriteAppsPreferenceKey = 'launcher.favoriteApps';
const int _favoriteAppsMaxCount = 10;
const String _wallpaperFixedFolderPath =
    '/storage/emulated/0/Android/data/com.kimkim/files/wallpapers';
const String _wallpaperIntervalPreferenceKey =
    'launcher.wallpaper.intervalSeconds';
const String _wallpaperButtonEnabledPreferenceKey =
    'launcher.wallpaper.buttonEnabled';
const int _wallpaperDecodeWidth = 1920;
const int _wallpaperDecodeHeight = 1080;
const MethodChannel _musicChannel = MethodChannel('byd/music');
const EventChannel _musicEvents = EventChannel('byd/music/events');
const MethodChannel _vehicleChannel = MethodChannel('byd.vehicle');
const EventChannel _vehicleEvents = EventChannel('byd.vehicle/events');
const MethodChannel _navigationChannel = MethodChannel('byd/navigation');
const MethodChannel _navigationVdChannel = MethodChannel('byd/navigation_vd');
const MethodChannel _permissionChannel = MethodChannel('byd/permissions');

const List<_VehiclePaintOption> _vehiclePaintOptions = [
  _VehiclePaintOption('Arctic White', Color(0xFFE9EEF4)),
  _VehiclePaintOption('Snow White', Color(0xFFF3F5F2)),
  _VehiclePaintOption('Sand Cream', Color(0xFFD8C8B2)),
  _VehiclePaintOption('Harbour Grey', Color(0xFF6F7880)),
  _VehiclePaintOption('Time Grey', Color(0xFF707477)),
  _VehiclePaintOption('Surf Blue', Color(0xFF2DA7D7)),
  _VehiclePaintOption('Delan Black', Color(0xFF090C12)),
  _VehiclePaintOption('Azure Blue', Color(0xFF1687FF)),
  _VehiclePaintOption('Sky Blue', Color(0xFF8BBED4)),
  _VehiclePaintOption('Forest Green', Color(0xFF1F4B3A)),
  _VehiclePaintOption('Boundless Cloud', Color(0xFFD5D7D2)),
  _VehiclePaintOption('Parkour Red', Color(0xFFB21E2B)),
  _VehiclePaintOption('Emperor Red', Color(0xFF7D1820)),
  _VehiclePaintOption('Coral Pink', Color(0xFFE88994)),
  _VehiclePaintOption('Maldive Purple', Color(0xFF7D6EA8)),
];

const List<String> _vehicleModelAssets = [
  'assets/models/2024_byd_atto_3.glb',
  'assets/models/2024_byd_dolphin.glb',
  'assets/models/2024_byd_m6.glb',
  'assets/models/2024_byd_seagull.glb',
  'assets/models/2024_byd_seal.glb',
  'assets/models/2024_byd_seal_5_dm-i.glb',
  'assets/models/2024_byd_seal_u_dm-i.glb',
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

class _LauncherApp {
  const _LauncherApp({
    required this.label,
    required this.packageName,
    required this.iconBase64,
  });

  factory _LauncherApp.fromMap(Map<dynamic, dynamic> map) {
    return _LauncherApp(
      label: _stringFromMap(map, 'label'),
      packageName: _stringFromMap(map, 'packageName'),
      iconBase64: _stringFromMap(map, 'iconBase64'),
    );
  }

  final String label;
  final String packageName;
  final String iconBase64;
}

const List<_NavigationApp> _previewNavigationApps = [
  _NavigationApp(label: 'BYD', packageName: 'com.byd.navigation'),
  _NavigationApp(label: 'Google', packageName: 'com.google.android.apps.maps'),
  _NavigationApp(label: 'Waze', packageName: 'com.waze'),
];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _preloadVehicleModelAssets();
  final prefs = await SharedPreferences.getInstance();
  final layoutMode = _parseLayoutMode(
    prefs.getString(_layoutModePreferenceKey),
  );
  await _applyLayoutModeOrientation(layoutMode);

  runApp(const BydLauncherApp());
}

Future<void> _applyLayoutModeOrientation(_LauncherLayoutMode mode) {
  return SystemChrome.setPreferredOrientations(switch (mode) {
    _LauncherLayoutMode.landscape => const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ],
    _LauncherLayoutMode.portrait => const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ],
  });
}

void _preloadVehicleModelAssets() {
  unawaited(rootBundle.load(_defaultVehicleModelAsset));
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
  _AppLanguage _language = _AppLanguage.en;
  bool _themePreferenceLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  @override
  Widget build(BuildContext context) {
    return _LocalizationScope(
      language: _language,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: _localizedStrings[_language]?['appTitle'] ?? 'Kim Launcher',
        themeMode: _themeMode,
        theme: _launcherTheme(Brightness.light),
        darkTheme: _launcherTheme(Brightness.dark),
        home: _LauncherHomePage(
          enable3dModel: _themePreferenceLoaded,
          themeMode: _themeMode,
          language: _language,
          onThemeModeChanged: _setThemeMode,
          onLanguageChanged: _setLanguage,
        ),
      ),
    );
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_themeModePreferenceKey);
    final storedLanguage = prefs.getString(_languagePreferenceKey);
    final themeMode = _parseThemeMode(stored);
    final language = _parseAppLanguage(storedLanguage);
    if (!mounted) return;
    setState(() {
      _themeMode = themeMode;
      _language = language;
      _themePreferenceLoaded = true;
    });
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModePreferenceKey, mode.name);
  }

  Future<void> _setLanguage(_AppLanguage language) async {
    setState(() => _language = language);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languagePreferenceKey, language.name);
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

enum _LauncherTab { status, map, wallpaper, settings }

enum _LauncherLayoutMode {
  landscape('Landscape'),
  portrait('Portrait');

  const _LauncherLayoutMode(this.label);

  final String label;
}

enum _LandscapeSidebarPosition {
  left('Left'),
  right('Right');

  const _LandscapeSidebarPosition(this.label);

  final String label;
}

enum _AppLanguage {
  en('English'),
  zh('中文'),
  th('ไทย'),
  id('Indonesia'),
  fr('Français'),
  it('Italiano'),
  vi('Tiếng Việt');

  const _AppLanguage(this.label);

  final String label;
}

_AppLanguage _parseAppLanguage(String? value) {
  for (final language in _AppLanguage.values) {
    if (language.name == value) return language;
  }
  return _AppLanguage.en;
}

_LauncherLayoutMode _parseLayoutMode(String? value) {
  for (final mode in _LauncherLayoutMode.values) {
    if (mode.name == value) return mode;
  }
  return _LauncherLayoutMode.landscape;
}

_LandscapeSidebarPosition _parseLandscapeSidebarPosition(String? value) {
  for (final position in _LandscapeSidebarPosition.values) {
    if (position.name == value) return position;
  }
  return _LandscapeSidebarPosition.left;
}

String _parseVehicleModelAsset(String? value) {
  if (value != null && _vehicleModelAssets.contains(value)) {
    return value;
  }
  return _defaultVehicleModelAsset;
}

String _vehicleModelLabel(String asset) {
  final filename = asset.split('/').last;
  final withoutExtension = filename.replaceFirst(RegExp(r'\.glb$'), '');
  final withoutYear = withoutExtension.replaceFirst(RegExp(r'^\d{4}_'), '');
  final words = withoutYear.split('_').where((word) => word.isNotEmpty);
  return words.map(_capitalizeVehicleModelWord).join(' ');
}

String _capitalizeVehicleModelWord(String word) {
  if (word.length <= 2 || word.contains('-')) {
    return word.toUpperCase();
  }
  return word[0].toUpperCase() + word.substring(1);
}

enum _VehicleGear { p, r, n, d }

enum _DemoLightMode { off, auto, lowBeam, highBeam, fog, turnLeft, turnRight }

enum _DemoRadarLevel { off, safe, far, medium, close, veryClose }

enum _DemoRadarZone { rear, front, left, right, all }

enum _VehicleRenderQuality { low, medium, high }

enum _VehicleHotspot {
  frontLeftWindow,
  frontRightWindow,
  rearLeftWindow,
  rearRightWindow,
  sunroof,
  trunk,
}

class _LocalizationScope extends InheritedWidget {
  const _LocalizationScope({required this.language, required super.child});

  final _AppLanguage language;

  static _AppLanguage languageOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_LocalizationScope>()
            ?.language ??
        _AppLanguage.en;
  }

  @override
  bool updateShouldNotify(_LocalizationScope oldWidget) {
    return oldWidget.language != language;
  }
}

String _t(BuildContext context, String key) {
  final language = _LocalizationScope.languageOf(context);
  return _localizedStrings[language]?[key] ??
      _localizedStrings[_AppLanguage.en]?[key] ??
      key;
}

String _tx(BuildContext context, String key, Map<String, Object> values) {
  var text = _t(context, key);
  for (final entry in values.entries) {
    text = text.replaceAll('{${entry.key}}', entry.value.toString());
  }
  return text;
}

const Map<_AppLanguage, Map<String, String>> _localizedStrings = {
  _AppLanguage.en: {
    'appTitle': 'Kim Launcher',
    'language': 'Language',
    'languageSubtitle': 'Choose the display language.',
    'vehicle': 'Vehicle',
    'navigation': 'Navigation',
    'navShort': 'Nav',
    'ambient': 'Ambient',
    'settings': 'Settings',
    'settingsSubtitle': 'Launcher and vehicle display preferences',
    'layout': 'Layout',
    'layoutSubtitle': 'Switch between landscape and portrait layouts.',
    'sidebarPosition': 'Landscape sidebar',
    'sidebarPositionSubtitle':
        'Move the vehicle sidebar for left or right hand drive.',
    'sidebarLeft': 'Left',
    'sidebarRight': 'Right',
    'landscapeShort': 'Land',
    'portraitShort': 'Port',
    'defaultLauncher': 'Default launcher',
    'defaultLauncherReady':
        'This launcher opens when the vehicle head unit starts.',
    'defaultLauncherChoose': 'Choose this app as the system Home launcher.',
    'launchNavigation': 'Launch navigation',
    'launchNavigationReady':
        'Open the default map app when this launcher starts.',
    'launchNavigationMissing':
        'Install or reload a map app before enabling this.',
    'vehicleModel': 'Vehicle model',
    'vehicleModelSubtitle': 'Choose the 3D model shown on the home screen.',
    'vehicleColor': 'Vehicle color',
    'vehicleColorSubtitle':
        'Used by the launcher preview and future render states.',
    'appearance': 'Appearance',
    'appearanceSubtitle':
        'Choose a light theme, dark theme, or follow the system setting.',
    'light': 'Light',
    'dark': 'Dark',
    'system': 'System',
    'renderQuality': '3D render quality',
    'lightEffect': 'Light effect',
    'lightEffectSubtitle': 'Show the animated beam overlay on the vehicle.',
    'radarEffect': 'Radar effect',
    'radarEffectSubtitle': 'Show the animated parking radar overlay.',
    'debugMode': 'Debug mode',
    'debugModeSubtitle': 'Enable demo gear, light and radar controls.',
    'ambientSubtitle': 'Use images from the app Ambient folder.',
    'showAmbientButton': 'Show Ambient button',
    'showAmbientButtonSubtitle':
        'Show or hide the Ambient tab in the bottom dock.',
    'autoChangeInterval': 'Auto change interval',
    'refresh': 'Refresh',
    'noAmbientImages': 'No Ambient images found',
    'ambientEmptyHint':
        'Place JPG, PNG or WEBP images in the Ambient folder, then tap Refresh.',
    'favoriteApps': 'Favorite apps',
    'noLaunchableApps': 'No launchable apps found',
    'add': 'Add',
    'cancel': 'Cancel',
    'saveCount': 'Save ({count}/10)',
    'range': 'Range',
    'fuel': 'Fuel',
    'battery': 'Battery',
    'music': 'Music',
    'unknownTrack': 'Unknown track',
    'enableMusicAccess': 'Enable Music access in Settings',
    'systemPermissions': 'System permissions',
    'systemPermissionsSubtitle':
        'One tap setup for music, overlay, vehicle data and launcher bridge.',
    'checkingPermissions': 'Checking permissions',
    'permissionsReady': 'Permissions ready',
    'grantAllPermissions': 'Grant all permissions',
    'allPermissionsReady': 'All permissions are ready',
    'permissionsReadyCount': '{ready}/{total} permissions ready',
    'overlay': 'Overlay',
    'internet': 'Internet',
  },
  _AppLanguage.vi: {
    'language': 'Ngôn ngữ',
    'languageSubtitle': 'Chọn ngôn ngữ hiển thị.',
    'vehicle': 'Xe',
    'navigation': 'Dẫn đường',
    'navShort': 'Map',
    'ambient': 'Ambient',
    'settings': 'Cài đặt',
    'settingsSubtitle': 'Tùy chọn launcher và hiển thị xe',
    'layout': 'Bố cục',
    'layoutSubtitle': 'Chuyển giữa bố cục ngang và dọc.',
    'sidebarPosition': 'Vị trí sidebar ngang',
    'sidebarPositionSubtitle':
        'Đổi sidebar xe sang trái/phải cho xe tay lái nghịch.',
    'sidebarLeft': 'Trái',
    'sidebarRight': 'Phải',
    'landscapeShort': 'Ngang',
    'portraitShort': 'Dọc',
    'defaultLauncher': 'Launcher mặc định',
    'defaultLauncherReady': 'Launcher này sẽ mở khi màn hình xe khởi động.',
    'defaultLauncherChoose': 'Chọn app này làm Home launcher của hệ thống.',
    'launchNavigation': 'Mở dẫn đường',
    'launchNavigationReady': 'Mở app bản đồ mặc định khi launcher khởi động.',
    'launchNavigationMissing': 'Cài hoặc tải lại app bản đồ trước khi bật.',
    'vehicleModel': 'Mẫu xe',
    'vehicleModelSubtitle': 'Chọn model 3D hiển thị ở màn hình chính.',
    'vehicleColor': 'Màu xe',
    'vehicleColorSubtitle':
        'Dùng cho preview launcher và trạng thái render sau này.',
    'appearance': 'Giao diện',
    'appearanceSubtitle': 'Chọn sáng, tối hoặc theo hệ thống.',
    'light': 'Sáng',
    'dark': 'Tối',
    'system': 'Hệ thống',
    'renderQuality': 'Chất lượng 3D',
    'lightEffect': 'Hiệu ứng đèn',
    'lightEffectSubtitle': 'Hiển thị animation luồng sáng trên xe.',
    'radarEffect': 'Hiệu ứng radar',
    'radarEffectSubtitle': 'Hiển thị animation radar quanh xe.',
    'debugMode': 'Debug mode',
    'debugModeSubtitle': 'Bật điều khiển demo số, đèn và radar.',
    'ambientSubtitle': 'Dùng ảnh từ thư mục Ambient của app.',
    'showAmbientButton': 'Hiện nút Ambient',
    'showAmbientButtonSubtitle': 'Hiện hoặc ẩn tab Ambient ở dock dưới.',
    'autoChangeInterval': 'Tự đổi ảnh',
    'refresh': 'Tải lại',
    'noAmbientImages': 'Chưa có ảnh Ambient',
    'ambientEmptyHint':
        'Chép ảnh JPG, PNG hoặc WEBP vào thư mục Ambient rồi bấm Tải lại.',
    'favoriteApps': 'Ứng dụng yêu thích',
    'noLaunchableApps': 'Không tìm thấy app có thể mở',
    'add': 'Thêm',
    'cancel': 'Huỷ',
    'saveCount': 'Lưu ({count}/10)',
    'range': 'Tầm hoạt động',
    'fuel': 'Xăng',
    'battery': 'Pin',
    'music': 'Nhạc',
    'unknownTrack': 'Không rõ bài hát',
    'enableMusicAccess': 'Bật quyền Nhạc trong Cài đặt',
    'systemPermissions': 'Quyền hệ thống',
    'systemPermissionsSubtitle':
        'Thiết lập một chạm cho nhạc, overlay, dữ liệu xe và launcher bridge.',
    'checkingPermissions': 'Đang kiểm tra quyền',
    'permissionsReady': 'Quyền đã sẵn sàng',
    'grantAllPermissions': 'Cấp tất cả quyền',
    'allPermissionsReady': 'Tất cả quyền đã sẵn sàng',
    'permissionsReadyCount': '{ready}/{total} quyền sẵn sàng',
    'overlay': 'Overlay',
    'internet': 'Internet',
  },
  _AppLanguage.zh: {
    'language': '语言',
    'settings': '设置',
    'vehicle': '车辆',
    'navigation': '导航',
    'ambient': '氛围',
    'layout': '布局',
    'add': '添加',
    'cancel': '取消',
    'refresh': '刷新',
    'favoriteApps': '收藏应用',
    'music': '音乐',
    'range': '续航',
    'fuel': '燃油',
    'battery': '电池',
  },
  _AppLanguage.th: {
    'language': 'ภาษา',
    'settings': 'ตั้งค่า',
    'vehicle': 'รถ',
    'navigation': 'นำทาง',
    'ambient': 'Ambient',
    'layout': 'เลย์เอาต์',
    'add': 'เพิ่ม',
    'cancel': 'ยกเลิก',
    'refresh': 'รีเฟรช',
    'favoriteApps': 'แอปโปรด',
    'music': 'เพลง',
    'range': 'ระยะทาง',
    'fuel': 'น้ำมัน',
    'battery': 'แบตเตอรี่',
  },
  _AppLanguage.id: {
    'language': 'Bahasa',
    'settings': 'Pengaturan',
    'vehicle': 'Kendaraan',
    'navigation': 'Navigasi',
    'ambient': 'Ambient',
    'layout': 'Tata letak',
    'add': 'Tambah',
    'cancel': 'Batal',
    'refresh': 'Muat ulang',
    'favoriteApps': 'Aplikasi favorit',
    'music': 'Musik',
    'range': 'Jarak',
    'fuel': 'Bensin',
    'battery': 'Baterai',
  },
  _AppLanguage.fr: {
    'language': 'Langue',
    'settings': 'Réglages',
    'vehicle': 'Véhicule',
    'navigation': 'Navigation',
    'ambient': 'Ambiance',
    'layout': 'Disposition',
    'add': 'Ajouter',
    'cancel': 'Annuler',
    'refresh': 'Actualiser',
    'favoriteApps': 'Apps favorites',
    'music': 'Musique',
    'range': 'Autonomie',
    'fuel': 'Carburant',
    'battery': 'Batterie',
  },
  _AppLanguage.it: {
    'language': 'Lingua',
    'settings': 'Impostazioni',
    'vehicle': 'Veicolo',
    'navigation': 'Navigazione',
    'ambient': 'Ambient',
    'layout': 'Layout',
    'add': 'Aggiungi',
    'cancel': 'Annulla',
    'refresh': 'Aggiorna',
    'favoriteApps': 'App preferite',
    'music': 'Musica',
    'range': 'Autonomia',
    'fuel': 'Carburante',
    'battery': 'Batteria',
  },
};

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

class _LauncherHomePage extends StatefulWidget {
  const _LauncherHomePage({
    this.enable3dModel = true,
    this.themeMode = ThemeMode.dark,
    this.language = _AppLanguage.en,
    this.onThemeModeChanged,
    this.onLanguageChanged,
  });

  final bool enable3dModel;
  final ThemeMode themeMode;
  final _AppLanguage language;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final ValueChanged<_AppLanguage>? onLanguageChanged;

  @override
  State<_LauncherHomePage> createState() => _LauncherHomePageState();
}

class _LauncherHomePageState extends State<_LauncherHomePage>
    with WidgetsBindingObserver {
  _VehicleView _view = _VehicleView.status;
  _LauncherTab _activeTab = _LauncherTab.status;
  _VehicleRenderQuality _renderQuality = _VehicleRenderQuality.medium;
  String _vehicleModelAsset = _defaultVehicleModelAsset;
  Color _vehicleColor = const Color(0xFFE9EEF4);
  _VehicleGear _selectedGear = _VehicleGear.p;
  bool _vehiclePreferencesLoaded = false;
  _LauncherLayoutMode _layoutMode = _LauncherLayoutMode.landscape;
  _LandscapeSidebarPosition _landscapeSidebarPosition =
      _LandscapeSidebarPosition.left;
  List<_LauncherApp> _launcherApps = const [];
  List<String> _favoriteAppPackages = const [];
  List<_NavigationApp> _navigationApps = const [];
  String? _selectedNavigationPackage;
  bool _launchNavigationWithLauncher = false;
  bool _defaultLauncherEnabled = false;
  bool _wallpaperButtonEnabled = true;
  String _wallpaperFolderPath = _wallpaperFixedFolderPath;
  int _wallpaperIntervalSeconds = 60;
  List<String> _wallpaperPaths = const [];
  int _wallpaperIndex = 0;
  Timer? _wallpaperTimer;
  Timer? _transitionLoadingTimer;
  bool _transitionLoading = false;
  double _vehicleSpeedKmh = 0;
  _DemoLightMode _demoLightMode = _DemoLightMode.off;
  _DemoRadarLevel _demoRadarLevel = _DemoRadarLevel.off;
  _DemoRadarZone _demoRadarZone = _DemoRadarZone.rear;
  bool _lightEffectEnabled = true;
  bool _radarEffectEnabled = true;
  bool _debugModeEnabled = false;
  _VehicleSnapshot _vehicleSnapshot = const _VehicleSnapshot();
  Timer? _vehicleSnapshotTimer;
  StreamSubscription<dynamic>? _vehicleSnapshotSubscription;

  bool get _roadMotionActive =>
      _effectiveGear == _VehicleGear.d || _effectiveGear == _VehicleGear.r;

  bool get _reverseRoadMotion => _effectiveGear == _VehicleGear.r;

  _VehicleGear get _effectiveGear => _vehicleSnapshot.gear ?? _selectedGear;

  double get _effectiveSpeedKmh =>
      _vehicleSnapshot.speedKmh ?? _vehicleSpeedKmh;

  List<_LauncherApp> get _favoriteApps {
    final appsByPackage = {
      for (final app in _launcherApps) app.packageName: app,
    };
    return [
      for (final packageName in _favoriteAppPackages)
        if (appsByPackage[packageName] != null) appsByPackage[packageName]!,
    ];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadVehiclePreferences();
    _loadDisplayPreferences();
    _loadFavoriteApps();
    _loadNavigationPreferences();
    _loadWallpaperPreferences();
    _refreshDefaultLauncherStatus();
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
    WidgetsBinding.instance.removeObserver(this);
    _vehicleSnapshotTimer?.cancel();
    _wallpaperTimer?.cancel();
    _transitionLoadingTimer?.cancel();
    _vehicleSnapshotSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshDefaultLauncherStatus();
    }
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
          child: Stack(
            children: [
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 1100;
                    final sidebarWidth = compact ? 292.0 : 348.0;
                    final dashboard = _LeftDashboard(
                      selectedGear: _selectedGear,
                      effectiveGear: _effectiveGear,
                      vehicleSpeedKmh: _effectiveSpeedKmh,
                      vehicleSnapshot: _vehicleSnapshot,
                      vehicleColor: _vehicleColor,
                      favoriteApps: _favoriteApps,
                      onGearChanged: _setGear,
                      onFavoriteAppTap: _launchFavoriteApp,
                      onFavoriteAppsEdit: _editFavoriteApps,
                      onFavoriteAppRemove: _removeFavoriteApp,
                      onFavoriteAppsReorder: _reorderFavoriteApps,
                    );
                    final vehicleCanvas = _VehicleCanvas(
                      enable3dModel:
                          widget.enable3dModel && _vehiclePreferencesLoaded,
                      cameraOrbit: _cameraOrbit,
                      view: _view,
                      activeTab: _activeTab,
                      vehicleModelAsset: _vehicleModelAsset,
                      vehicleColor: _vehicleColor,
                      renderQuality: _renderQuality,
                      layoutMode: _layoutMode,
                      landscapeSidebarPosition: _landscapeSidebarPosition,
                      onLandscapeSidebarPositionChanged:
                          _setLandscapeSidebarPosition,
                      roadMotionActive: _roadMotionActive,
                      reverseRoadMotion: _reverseRoadMotion,
                      vehicleSpeedKmh: _effectiveSpeedKmh,
                      demoLightMode: _demoLightMode,
                      demoRadarLevel: _demoRadarLevel,
                      demoRadarZone: _demoRadarZone,
                      debugModeEnabled: _debugModeEnabled,
                      onDemoLightModeChanged: (mode) =>
                          setState(() => _demoLightMode = mode),
                      onDemoRadarLevelChanged: (level) =>
                          setState(() => _demoRadarLevel = level),
                      onDemoRadarZoneChanged: (zone) =>
                          setState(() => _demoRadarZone = zone),
                      effectiveGear: _effectiveGear,
                      vehicleSnapshot: _vehicleSnapshot,
                      onGearChanged: _setGear,
                      onViewChanged: (view) => setState(() => _view = view),
                      onTabChanged: _handleTabChanged,
                      onVehicleModelChanged: _setVehicleModel,
                      onVehicleColorChanged: _setVehicleColor,
                      onRenderQualityChanged: _setRenderQuality,
                      onLayoutModeChanged: _setLayoutMode,
                      navigationApps: _navigationApps,
                      selectedNavigationPackage: _selectedNavigationPackage,
                      launchNavigationWithLauncher:
                          _launchNavigationWithLauncher,
                      defaultLauncherEnabled: _defaultLauncherEnabled,
                      onDefaultNavigationAppChanged: _setDefaultNavigationApp,
                      onNavigationReloadRequested: _reloadNavigationApps,
                      onDefaultNavigationOpenRequested:
                          _openDefaultNavigationApp,
                      onLaunchNavigationWithLauncherChanged:
                          _setLaunchNavigationWithLauncher,
                      onDefaultLauncherChanged: _setDefaultLauncher,
                      wallpaperButtonEnabled: _wallpaperButtonEnabled,
                      wallpaperFolderPath: _wallpaperFolderPath,
                      wallpaperIntervalSeconds: _wallpaperIntervalSeconds,
                      wallpaperPaths: _wallpaperPaths,
                      wallpaperIndex: _wallpaperIndex,
                      onWallpaperReloadRequested: _reloadWallpapers,
                      onWallpaperIntervalChanged: _setWallpaperInterval,
                      onWallpaperButtonEnabledChanged:
                          _setWallpaperButtonEnabled,
                      lightEffectEnabled: _lightEffectEnabled,
                      radarEffectEnabled: _radarEffectEnabled,
                      onLightEffectEnabledChanged: _setLightEffectEnabled,
                      onRadarEffectEnabledChanged: _setRadarEffectEnabled,
                      onDebugModeChanged: _setDebugModeEnabled,
                      themeMode: widget.themeMode,
                      onThemeModeChanged: widget.onThemeModeChanged,
                      language: widget.language,
                      onLanguageChanged: widget.onLanguageChanged,
                    );

                    if (_layoutMode == _LauncherLayoutMode.portrait) {
                      return Column(
                        children: [
                          Expanded(child: vehicleCanvas),
                          if (_activeTab == _LauncherTab.status)
                            SizedBox(
                              height: 292,
                              child: _PortraitBottomDashboard(
                                vehicleColor: _vehicleColor,
                                vehicleSnapshot: _vehicleSnapshot,
                                favoriteApps: _favoriteApps,
                                onFavoriteAppTap: _launchFavoriteApp,
                                onFavoriteAppsEdit: _editFavoriteApps,
                                onFavoriteAppRemove: _removeFavoriteApp,
                                onFavoriteAppsReorder: _reorderFavoriteApps,
                              ),
                            ),
                        ],
                      );
                    }

                    final showSidebar = _activeTab != _LauncherTab.wallpaper;
                    final sidebar = SizedBox(
                      width: sidebarWidth,
                      child: dashboard,
                    );
                    final canvas = Expanded(child: vehicleCanvas);
                    final sidebarOnRight =
                        _landscapeSidebarPosition ==
                        _LandscapeSidebarPosition.right;

                    return Row(
                      children: [
                        if (showSidebar && !sidebarOnRight) sidebar,
                        canvas,
                        if (showSidebar && sidebarOnRight) sidebar,
                      ],
                    );
                  },
                ),
              ),
              if (_transitionLoading)
                Positioned.fill(
                  child: _LauncherTransitionLoading(
                    layoutMode: _layoutMode,
                    activeTab: _activeTab,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleTabChanged(_LauncherTab tab) {
    if (tab == _activeTab) return;
    _showTransitionLoading();
    setState(() => _activeTab = tab);
    _scheduleWallpaperTimer();
  }

  void _showTransitionLoading({
    Duration duration = const Duration(milliseconds: 620),
  }) {
    _transitionLoadingTimer?.cancel();
    if (mounted) {
      setState(() => _transitionLoading = true);
    }
    _transitionLoadingTimer = Timer(duration, () {
      if (!mounted) return;
      setState(() => _transitionLoading = false);
    });
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
    final storedModel = prefs.getString(_vehicleModelPreferenceKey);
    final storedQuality = prefs.getString(_renderQualityPreferenceKey);

    if (!mounted) return;
    setState(() {
      if (storedColor != null) {
        _vehicleColor = Color(storedColor);
      }
      _vehicleModelAsset = _parseVehicleModelAsset(storedModel);
      _renderQuality = _parseRenderQuality(storedQuality);
      _vehiclePreferencesLoaded = true;
    });
  }

  Future<void> _setVehicleModel(String asset) async {
    final parsedAsset = _parseVehicleModelAsset(asset);
    setState(() => _vehicleModelAsset = parsedAsset);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_vehicleModelPreferenceKey, parsedAsset);
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

  Future<void> _loadDisplayPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final layoutMode = _parseLayoutMode(
      prefs.getString(_layoutModePreferenceKey),
    );
    final sidebarPosition = _parseLandscapeSidebarPosition(
      prefs.getString(_landscapeSidebarPositionPreferenceKey),
    );
    final lightEffectEnabled =
        prefs.getBool(_lightEffectEnabledPreferenceKey) ?? true;
    final radarEffectEnabled =
        prefs.getBool(_radarEffectEnabledPreferenceKey) ?? true;
    final debugModeEnabled = prefs.getBool(_debugModePreferenceKey) ?? false;
    await _applyLayoutModeOrientation(layoutMode);
    if (!mounted) return;
    setState(() {
      _layoutMode = layoutMode;
      _landscapeSidebarPosition = sidebarPosition;
      _lightEffectEnabled = lightEffectEnabled;
      _radarEffectEnabled = radarEffectEnabled;
      _debugModeEnabled = debugModeEnabled;
    });
  }

  Future<void> _setDebugModeEnabled(bool value) async {
    setState(() {
      _debugModeEnabled = value;
      if (!value) {
        _selectedGear = _VehicleGear.p;
        _vehicleSpeedKmh = 0;
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_debugModePreferenceKey, value);
  }

  Future<void> _setLightEffectEnabled(bool value) async {
    setState(() => _lightEffectEnabled = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_lightEffectEnabledPreferenceKey, value);
  }

  Future<void> _setRadarEffectEnabled(bool value) async {
    setState(() => _radarEffectEnabled = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_radarEffectEnabledPreferenceKey, value);
  }

  Future<void> _setLayoutMode(_LauncherLayoutMode value) async {
    if (value == _layoutMode) return;
    _showTransitionLoading(duration: const Duration(milliseconds: 900));
    setState(() => _layoutMode = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_layoutModePreferenceKey, value.name);
    await _applyLayoutModeOrientation(value);
  }

  Future<void> _setLandscapeSidebarPosition(
    _LandscapeSidebarPosition value,
  ) async {
    if (value == _landscapeSidebarPosition) return;
    _showTransitionLoading(duration: const Duration(milliseconds: 520));
    setState(() => _landscapeSidebarPosition = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_landscapeSidebarPositionPreferenceKey, value.name);
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

  Future<void> _loadFavoriteApps() async {
    final prefs = await SharedPreferences.getInstance();
    final storedPackages =
        prefs.getStringList(_favoriteAppsPreferenceKey) ?? const [];
    final apps = await _loadLauncherAppsFromPlatform();
    if (!mounted) return;
    final availablePackages = apps.map((app) => app.packageName).toSet();
    setState(() {
      _launcherApps = apps;
      _favoriteAppPackages = storedPackages
          .where(availablePackages.contains)
          .take(_favoriteAppsMaxCount)
          .toList(growable: false);
    });
  }

  Future<List<_LauncherApp>> _loadLauncherAppsFromPlatform() async {
    try {
      final rawApps = await _navigationChannel.invokeListMethod<dynamic>(
        'getLaunchableApps',
      );
      return (rawApps ?? [])
          .whereType<Map<dynamic, dynamic>>()
          .map(_LauncherApp.fromMap)
          .where((app) => app.label.isNotEmpty && app.packageName.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _launchFavoriteApp(_LauncherApp app) async {
    try {
      await _navigationChannel.invokeMethod<Object?>('launchApp', {
        'packageName': app.packageName,
      });
    } catch (_) {}
  }

  Future<void> _editFavoriteApps() async {
    if (_launcherApps.isEmpty) {
      await _loadFavoriteApps();
    }
    if (!mounted) return;

    final selected = await showDialog<List<String>>(
      context: context,
      builder: (context) => _FavoriteAppsDialog(
        apps: _launcherApps,
        selectedPackages: _favoriteAppPackages,
      ),
    );
    if (selected == null || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoriteAppsPreferenceKey, selected);
    setState(() => _favoriteAppPackages = selected);
  }

  Future<void> _saveFavoriteAppPackages(List<String> packageNames) async {
    final normalized = packageNames
        .take(_favoriteAppsMaxCount)
        .toList(growable: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoriteAppsPreferenceKey, normalized);
    if (!mounted) return;
    setState(() => _favoriteAppPackages = normalized);
  }

  Future<void> _removeFavoriteApp(_LauncherApp app) async {
    await _saveFavoriteAppPackages(
      _favoriteAppPackages
          .where((packageName) => packageName != app.packageName)
          .toList(growable: false),
    );
  }

  Future<void> _reorderFavoriteApps(List<_LauncherApp> apps) async {
    await _saveFavoriteAppPackages(
      apps.map((app) => app.packageName).toList(growable: false),
    );
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

  Future<void> _refreshDefaultLauncherStatus() async {
    try {
      final enabled = await _permissionChannel.invokeMethod<bool>(
        'isDefaultLauncher',
      );
      if (!mounted || enabled == null) return;
      setState(() => _defaultLauncherEnabled = enabled);
    } catch (_) {}
  }

  Future<void> _setDefaultLauncher(bool value) async {
    try {
      await _permissionChannel.invokeMethod<Object?>(
        'openDefaultLauncherSettings',
      );
    } catch (_) {}

    Future<void>.delayed(
      const Duration(milliseconds: 700),
      _refreshDefaultLauncherStatus,
    );
  }

  Future<void> _loadWallpaperPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final interval = prefs.getInt(_wallpaperIntervalPreferenceKey) ?? 60;
    final buttonEnabled =
        prefs.getBool(_wallpaperButtonEnabledPreferenceKey) ?? true;

    if (!mounted) return;
    setState(() {
      _wallpaperFolderPath = _wallpaperFixedFolderPath;
      _wallpaperIntervalSeconds = _normalizeWallpaperInterval(interval);
      _wallpaperButtonEnabled = buttonEnabled;
    });
    await _reloadWallpapers();
  }

  int _normalizeWallpaperInterval(int seconds) {
    if (seconds <= 0) return 0;
    if (seconds < 10) return 10;
    if (seconds > 86400) return 86400;
    return seconds;
  }

  Future<void> _reloadWallpapers() async {
    const folder = _wallpaperFixedFolderPath;

    final paths = await _scanWallpaperFolderWithFallback(folder);
    if (!mounted) return;
    setState(() {
      _wallpaperPaths = paths;
      if (_wallpaperIndex >= paths.length) _wallpaperIndex = 0;
    });
    _scheduleWallpaperTimer();
  }

  Future<List<String>> _scanWallpaperFolderWithFallback(String folder) async {
    try {
      final directory = Directory(folder);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final paths = await directory
          .list(followLinks: false)
          .where(
            (entity) =>
                entity is File && _isSupportedWallpaperPath(entity.path),
          )
          .map((entity) => entity.path)
          .toList();
      paths.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return paths;
    } catch (_) {
      return const [];
    }
  }

  bool _isSupportedWallpaperPath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
  }

  Future<void> _setWallpaperInterval(int seconds) async {
    final normalized = _normalizeWallpaperInterval(seconds);
    setState(() => _wallpaperIntervalSeconds = normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_wallpaperIntervalPreferenceKey, normalized);
    _scheduleWallpaperTimer();
  }

  Future<void> _setWallpaperButtonEnabled(bool value) async {
    setState(() {
      _wallpaperButtonEnabled = value;
      if (!value && _activeTab == _LauncherTab.wallpaper) {
        _activeTab = _LauncherTab.status;
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_wallpaperButtonEnabledPreferenceKey, value);
    _scheduleWallpaperTimer();
  }

  void _scheduleWallpaperTimer() {
    _wallpaperTimer?.cancel();
    if (!_wallpaperButtonEnabled ||
        _activeTab != _LauncherTab.wallpaper ||
        _wallpaperIntervalSeconds <= 0 ||
        _wallpaperPaths.length <= 1) {
      return;
    }
    _wallpaperTimer = Timer.periodic(
      Duration(seconds: _wallpaperIntervalSeconds),
      (_) {
        if (!mounted ||
            _activeTab != _LauncherTab.wallpaper ||
            _wallpaperPaths.length <= 1) {
          _scheduleWallpaperTimer();
          return;
        }
        setState(() {
          _wallpaperIndex = (_wallpaperIndex + 1) % _wallpaperPaths.length;
        });
      },
    );
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

class _PortraitBottomDashboard extends StatelessWidget {
  const _PortraitBottomDashboard({
    required this.vehicleColor,
    required this.vehicleSnapshot,
    required this.favoriteApps,
    required this.onFavoriteAppTap,
    required this.onFavoriteAppsEdit,
    required this.onFavoriteAppRemove,
    required this.onFavoriteAppsReorder,
  });

  final Color vehicleColor;
  final _VehicleSnapshot vehicleSnapshot;
  final List<_LauncherApp> favoriteApps;
  final ValueChanged<_LauncherApp> onFavoriteAppTap;
  final VoidCallback onFavoriteAppsEdit;
  final ValueChanged<_LauncherApp> onFavoriteAppRemove;
  final ValueChanged<List<_LauncherApp>> onFavoriteAppsReorder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(
        children: [
          Expanded(
            flex: 10,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(28),
              ),
              child: _TpmsCluster(
                vehicleColor: vehicleColor,
                snapshot: vehicleSnapshot,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 14,
            child: Column(
              children: [
                const SizedBox(height: 122, child: _CompactMediaWidget()),
                const SizedBox(height: 8),
                SizedBox(
                  height: 72,
                  child: _EnergyStrip(snapshot: vehicleSnapshot),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 56,
                  child: _FavoriteAppsStrip(
                    apps: favoriteApps,
                    onAppTap: onFavoriteAppTap,
                    onEditTap: onFavoriteAppsEdit,
                    onRemove: onFavoriteAppRemove,
                    onReorder: onFavoriteAppsReorder,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LeftDashboard extends StatelessWidget {
  const _LeftDashboard({
    required this.selectedGear,
    required this.effectiveGear,
    required this.vehicleSpeedKmh,
    required this.vehicleSnapshot,
    required this.vehicleColor,
    required this.favoriteApps,
    required this.onGearChanged,
    required this.onFavoriteAppTap,
    required this.onFavoriteAppsEdit,
    required this.onFavoriteAppRemove,
    required this.onFavoriteAppsReorder,
  });

  final _VehicleGear selectedGear;
  final _VehicleGear effectiveGear;
  final double vehicleSpeedKmh;
  final _VehicleSnapshot vehicleSnapshot;
  final Color vehicleColor;
  final List<_LauncherApp> favoriteApps;
  final ValueChanged<_VehicleGear> onGearChanged;
  final ValueChanged<_LauncherApp> onFavoriteAppTap;
  final VoidCallback onFavoriteAppsEdit;
  final ValueChanged<_LauncherApp> onFavoriteAppRemove;
  final ValueChanged<List<_LauncherApp>> onFavoriteAppsReorder;

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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compactHeight = constraints.maxHeight < 610;
                  // BYD head-unit screens have less vertical room than tablets.
                  // Keep Music tall enough for its controls, and reclaim space
                  // mostly from TPMS so neither widget overflows.
                  final mediaHeight = compactHeight ? 166.0 : 168.0;
                  final favoritesHeight = compactHeight ? 58.0 : 62.0;
                  final gapSmall = compactHeight ? 6.0 : 10.0;
                  final gapMedium = compactHeight ? 7.0 : 12.0;
                  final tpmsHeight = compactHeight
                      ? (constraints.maxHeight -
                                mediaHeight -
                                favoritesHeight -
                                166.0)
                            .clamp(156.0, 186.0)
                            .toDouble()
                      : 198.0;

                  return Column(
                    children: [
                      _StatusBar(
                        outsideTemperatureC:
                            vehicleSnapshot.outsideTemperatureC,
                      ),
                      SizedBox(height: gapSmall),
                      SizedBox(
                        height: tpmsHeight,
                        child: _TpmsCluster(
                          vehicleColor: vehicleColor,
                          snapshot: vehicleSnapshot,
                        ),
                      ),
                      SizedBox(height: gapMedium),
                      SizedBox(
                        height: mediaHeight,
                        child: const _MediaWidget(),
                      ),
                      SizedBox(height: gapSmall),
                      Flexible(child: _EnergyStrip(snapshot: vehicleSnapshot)),
                      SizedBox(height: gapSmall),
                      SizedBox(
                        height: favoritesHeight,
                        child: _FavoriteAppsStrip(
                          apps: favoriteApps,
                          onAppTap: onFavoriteAppTap,
                          onEditTap: onFavoriteAppsEdit,
                          onRemove: onFavoriteAppRemove,
                          onReorder: onFavoriteAppsReorder,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FavoriteAppsStrip extends StatefulWidget {
  const _FavoriteAppsStrip({
    required this.apps,
    required this.onAppTap,
    required this.onEditTap,
    required this.onRemove,
    required this.onReorder,
  });

  final List<_LauncherApp> apps;
  final ValueChanged<_LauncherApp> onAppTap;
  final VoidCallback onEditTap;
  final ValueChanged<_LauncherApp> onRemove;
  final ValueChanged<List<_LauncherApp>> onReorder;

  @override
  State<_FavoriteAppsStrip> createState() => _FavoriteAppsStripState();
}

class _FavoriteAppsStripState extends State<_FavoriteAppsStrip> {
  bool _editing = false;

  void _enterEditing() {
    if (!_editing) setState(() => _editing = true);
  }

  void _exitEditing() {
    if (_editing) setState(() => _editing = false);
  }

  void _reorder(_LauncherApp draggedApp, _LauncherApp targetApp) {
    final reordered = widget.apps
        .take(_favoriteAppsMaxCount)
        .toList(growable: true);
    final from = reordered.indexWhere(
      (app) => app.packageName == draggedApp.packageName,
    );
    final to = reordered.indexWhere(
      (app) => app.packageName == targetApp.packageName,
    );
    if (from == -1 || to == -1 || from == to) return;

    final moved = reordered.removeAt(from);
    reordered.insert(to, moved);
    widget.onReorder(reordered);
  }

  @override
  Widget build(BuildContext context) {
    final visibleApps = widget.apps
        .take(_favoriteAppsMaxCount)
        .toList(growable: false);
    final canAdd = visibleApps.length < _favoriteAppsMaxCount;

    return TapRegion(
      onTapOutside: (_) => _exitEditing(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemExtent = constraints.maxWidth >= 430 ? 74.0 : 60.0;
          final addExtent = constraints.maxWidth >= 430 ? 78.0 : 60.0;

          return Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      for (final app in visibleApps)
                        SizedBox(
                          width: itemExtent,
                          child: DragTarget<_LauncherApp>(
                            onWillAcceptWithDetails: (details) =>
                                details.data.packageName != app.packageName,
                            onAcceptWithDetails: (details) {
                              _enterEditing();
                              _reorder(details.data, app);
                            },
                            builder: (context, candidateData, rejectedData) {
                              final highlighted = candidateData.isNotEmpty;
                              final button = _FavoriteAppButton(
                                app: app,
                                editing: _editing,
                                highlighted: highlighted,
                                onTap: () => _editing
                                    ? _exitEditing()
                                    : widget.onAppTap(app),
                                onLongPress: _enterEditing,
                                onRemove: () => widget.onRemove(app),
                              );

                              return LongPressDraggable<_LauncherApp>(
                                data: app,
                                delay: const Duration(milliseconds: 220),
                                onDragStarted: _enterEditing,
                                feedback: Material(
                                  color: Colors.transparent,
                                  child: SizedBox(
                                    width: itemExtent,
                                    height: 58,
                                    child: button,
                                  ),
                                ),
                                childWhenDragging: Opacity(
                                  opacity: 0.32,
                                  child: button,
                                ),
                                child: button,
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (canAdd || visibleApps.isEmpty) ...[
                const SizedBox(width: 6),
                SizedBox(
                  width: addExtent,
                  child: _AddFavoriteAppButton(onTap: widget.onEditTap),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _FavoriteAppButton extends StatelessWidget {
  const _FavoriteAppButton({
    required this.app,
    required this.onTap,
    required this.onLongPress,
    required this.onRemove,
    this.editing = false,
    this.highlighted = false,
  });

  final _LauncherApp app;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onRemove;
  final bool editing;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
            decoration: BoxDecoration(
              color: highlighted
                  ? _accentSoftBlue.withValues(alpha: light ? 0.14 : 0.18)
                  : editing
                  ? Colors.white.withValues(alpha: light ? 0.34 : 0.045)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: highlighted
                    ? _accentSoftBlue.withValues(alpha: 0.30)
                    : Colors.transparent,
              ),
            ),
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LauncherAppIcon(app: app, size: 28),
                const SizedBox(height: 4),
                Text(
                  app.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: _sharp(
                    context,
                    Theme.of(context).textTheme.labelSmall,
                    color: _textPrimary,
                    weight: FontWeight.w600,
                    size: 9.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (editing)
          Positioned(
            right: 0,
            top: -2,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onRemove,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: light ? 0.66 : 0.74),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.58),
                  ),
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 13,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AddFavoriteAppButton extends StatelessWidget {
  const _AddFavoriteAppButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);

    return Align(
      alignment: Alignment.center,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: light
                ? Colors.white.withValues(alpha: 0.70)
                : Colors.white.withValues(alpha: 0.070),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: light
                  ? const Color(0xFFDDE7F1).withValues(alpha: 0.88)
                  : Colors.white.withValues(alpha: 0.060),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_rounded,
                color: _tone(context, _textPrimary),
                size: 20,
              ),
              const SizedBox(height: 2),
              Text(
                _t(context, 'add'),
                style: _sharp(
                  context,
                  Theme.of(context).textTheme.labelSmall,
                  color: _textPrimary,
                  weight: FontWeight.w600,
                  size: 9.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LauncherAppIcon extends StatelessWidget {
  const _LauncherAppIcon({required this.app, required this.size});

  final _LauncherApp app;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (app.iconBase64.isNotEmpty) {
      try {
        return ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.26),
          child: Image.memory(
            base64Decode(app.iconBase64),
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        );
      } catch (_) {}
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _accentSoftBlue.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.26),
      ),
      child: Icon(
        Icons.apps_rounded,
        color: _accentSoftBlue,
        size: size * 0.58,
      ),
    );
  }
}

class _FavoriteAppsDialog extends StatefulWidget {
  const _FavoriteAppsDialog({
    required this.apps,
    required this.selectedPackages,
  });

  final List<_LauncherApp> apps;
  final List<String> selectedPackages;

  @override
  State<_FavoriteAppsDialog> createState() => _FavoriteAppsDialogState();
}

class _FavoriteAppsDialogState extends State<_FavoriteAppsDialog> {
  late final Set<String> _selectedPackages;

  @override
  void initState() {
    super.initState();
    _selectedPackages = widget.selectedPackages
        .take(_favoriteAppsMaxCount)
        .toSet();
  }

  void _toggle(String packageName, bool selected) {
    setState(() {
      if (!selected) {
        _selectedPackages.remove(packageName);
      } else if (_selectedPackages.length < _favoriteAppsMaxCount) {
        _selectedPackages.add(packageName);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _t(context, 'favoriteApps'),
        style: _sharp(
          context,
          Theme.of(context).textTheme.titleLarge,
          color: _textPrimary,
          weight: FontWeight.w700,
          size: 20,
        ),
      ),
      content: SizedBox(
        width: 520,
        height: 390,
        child: widget.apps.isEmpty
            ? Center(
                child: Text(
                  _t(context, 'noLaunchableApps'),
                  style: _sharp(
                    context,
                    Theme.of(context).textTheme.bodyMedium,
                    color: _textMuted,
                    weight: FontWeight.w500,
                    size: 13,
                  ),
                ),
              )
            : ListView.separated(
                itemCount: widget.apps.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final app = widget.apps[index];
                  final selected = _selectedPackages.contains(app.packageName);
                  final disabled =
                      !selected &&
                      _selectedPackages.length >= _favoriteAppsMaxCount;
                  return CheckboxListTile(
                    value: selected,
                    onChanged: disabled
                        ? null
                        : (value) => _toggle(app.packageName, value == true),
                    secondary: _LauncherAppIcon(app: app, size: 34),
                    title: Text(
                      app.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      app.packageName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    dense: true,
                    controlAffinity: ListTileControlAffinity.trailing,
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_t(context, 'cancel')),
        ),
        FilledButton(
          onPressed: () {
            final selected = [
              for (final app in widget.apps)
                if (_selectedPackages.contains(app.packageName))
                  app.packageName,
            ];
            Navigator.of(context).pop(selected);
          },
          child: Text(
            _tx(context, 'saveCount', {'count': _selectedPackages.length}),
          ),
        ),
      ],
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
  const _GearText(
    this.label, {
    this.active = false,
    this.onTap,
    this.size = 24,
    this.fontSize = 13,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;
  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        width: size,
        height: size,
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
              size: fontSize,
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
    required this.debugModeEnabled,
    this.compact = false,
  });

  final _VehicleGear selectedGear;
  final double vehicleSpeedKmh;
  final ValueChanged<_VehicleGear> onGearChanged;
  final bool debugModeEnabled;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);
    final ringColor = light
        ? const Color(0xFF2F80ED).withValues(alpha: 0.20)
        : _accentSoftBlue.withValues(alpha: 0.22);

    final outerPadding = compact ? 1.0 : 4.0;
    final innerRingPadding = compact ? 6.0 : 10.0;
    final speedFontSize = compact ? 34.0 : 58.0;
    final speedLetterSpacing = compact ? -0.8 : -1.8;
    final unitFontSize = compact ? 9.0 : 12.0;
    final gearTopGap = compact ? 5.0 : 12.0;
    final gearButtonSize = compact ? 19.0 : 24.0;
    final gearFontSize = compact ? 10.5 : 13.0;
    final gearPadding = compact
        ? const EdgeInsets.symmetric(horizontal: 4, vertical: 3)
        : const EdgeInsets.symmetric(horizontal: 8, vertical: 6);

    return Padding(
      padding: EdgeInsets.all(outerPadding),
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
              padding: EdgeInsets.all(innerRingPadding),
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
                      size: speedFontSize,
                      height: 0.86,
                      letterSpacing: speedLetterSpacing,
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
                  size: unitFontSize,
                  letterSpacing: 0.6,
                ),
              ),
              SizedBox(height: gearTopGap),
              Container(
                padding: gearPadding,
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
                      onTap: debugModeEnabled
                          ? () => onGearChanged(_VehicleGear.p)
                          : null,
                      size: gearButtonSize,
                      fontSize: gearFontSize,
                    ),
                    _GearText(
                      'R',
                      active: selectedGear == _VehicleGear.r,
                      onTap: debugModeEnabled
                          ? () => onGearChanged(_VehicleGear.r)
                          : null,
                      size: gearButtonSize,
                      fontSize: gearFontSize,
                    ),
                    _GearText(
                      'N',
                      active: selectedGear == _VehicleGear.n,
                      onTap: debugModeEnabled
                          ? () => onGearChanged(_VehicleGear.n)
                          : null,
                      size: gearButtonSize,
                      fontSize: gearFontSize,
                    ),
                    _GearText(
                      'D',
                      active: selectedGear == _VehicleGear.d,
                      onTap: debugModeEnabled
                          ? () => onGearChanged(_VehicleGear.d)
                          : null,
                      size: gearButtonSize,
                      fontSize: gearFontSize,
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
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final carWidth = constraints.maxWidth >= 280 ? 96.0 : 82.0;
          final lineWidth = constraints.maxWidth >= 280 ? 46.0 : 32.0;
          final lineTop = constraints.maxHeight * 0.23;
          final lineBottom = constraints.maxHeight * 0.31;
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
                child: Align(
                  alignment: const Alignment(0, -0.10),
                  child: SizedBox(
                    width: carWidth,
                    height: constraints.maxHeight * 0.94,
                    child: _TintedTpmsVehicleImage(vehicleColor: vehicleColor),
                  ),
                ),
              ),

              Positioned(
                left: 0,
                top: 8,
                child: _PressureBlock(
                  value: snapshot.tyre('frontLeft').pressureLabel,
                  temp: snapshot.tyre('frontLeft').stateLabel,
                ),
              ),
              Positioned(
                right: 0,
                top: 8,
                child: _PressureBlock(
                  value: snapshot.tyre('frontRight').pressureLabel,
                  temp: snapshot.tyre('frontRight').stateLabel,
                  alignRight: true,
                ),
              ),
              Positioned(
                left: 0,
                bottom: 24,
                child: _PressureBlock(
                  value: snapshot.tyre('rearLeft').pressureLabel,
                  temp: snapshot.tyre('rearLeft').stateLabel,
                ),
              ),
              Positioned(
                right: 0,
                bottom: 24,
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

class _CompactMediaWidget extends StatefulWidget {
  const _CompactMediaWidget();

  @override
  State<_CompactMediaWidget> createState() => _CompactMediaWidgetState();
}

class _CompactMediaWidgetState extends State<_CompactMediaWidget>
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
    setState(() => _state = _MediaPlaybackState.fromMap(value));
  }

  void _invoke(String method) {
    unawaited(
      _musicChannel
          .invokeMethod<Object?>(method)
          .catchError((Object _) => null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);
    final controlColor = light ? const Color(0xFF31516F) : _textSecondary;
    final progressTrack = light
        ? const Color(0xFFD4E0EB)
        : const Color(0xFF293241);

    return _GlassCard(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Column(
        children: [
          Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _invoke('openMusicApp'),
                child: Container(
                  width: 46,
                  height: 46,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF5E1E2A), Color(0xFF171B2D)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: _state.albumArt == null
                      ? const Icon(
                          Icons.music_note_rounded,
                          color: Color(0xFFFFD36E),
                          size: 27,
                        )
                      : Image.memory(
                          _state.albumArt!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                ),
              ),
              const SizedBox(width: 10),
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
                        Theme.of(context).textTheme.titleSmall,
                        color: _textPrimary,
                        weight: FontWeight.w700,
                        size: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _state.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _sharp(
                        context,
                        Theme.of(context).textTheme.labelMedium,
                        color: _textMuted,
                        weight: FontWeight.w500,
                        size: 11.5,
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
                size: 19,
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: _state.progress ?? 0,
              minHeight: 3,
              color: _accentSoftBlue,
              backgroundColor: progressTrack,
            ),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _MediaControlButton(
                  icon: Icons.skip_previous_rounded,
                  color: controlColor,
                  enabled: _state.hasController,
                  onPressed: () => _invoke('previous'),
                ),
                const SizedBox(width: 18),
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _invoke('playPause'),
                  child: Container(
                    width: 32,
                    height: 32,
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
                    ),
                    child: Icon(
                      _state.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: light ? const Color(0xFF1D4F86) : Colors.white,
                      size: _state.isPlaying ? 20 : 23,
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                _MediaControlButton(
                  icon: Icons.skip_next_rounded,
                  color: controlColor,
                  enabled: _state.hasController,
                  onPressed: () => _invoke('next'),
                ),
              ],
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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 260,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t(context, 'range'),
                style: _sharp(
                  context,
                  Theme.of(context).textTheme.labelMedium,
                  color: _textMuted,
                  weight: FontWeight.w500,
                  size: 11.5,
                  height: 1,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 1),
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
                      size: 24,
                      height: 0.92,
                      letterSpacing: -0.7,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      'km',
                      style: _sharp(
                        context,
                        Theme.of(context).textTheme.labelLarge,
                        color: _textSecondary,
                        weight: FontWeight.w500,
                        size: 12,
                        height: 1,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.route_outlined,
                    color: _accentSoftBlue,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Expanded(
                    child: _EnergyLevel(
                      icon: Icons.local_gas_station,
                      label: _t(context, 'fuel'),
                      value: fuel == null ? '--' : '$fuel%',
                      color: Color(0xFF25D366),
                      progress: (fuel ?? 0) / 100,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _EnergyLevel(
                      icon: Icons.battery_5_bar,
                      label: _t(context, 'battery'),
                      value: battery == null ? '--' : '${battery.round()}%',
                      color: _accentSoftBlue,
                      progress: (battery ?? 0) / 100,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 3.5,
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

class _LauncherTransitionLoading extends StatelessWidget {
  const _LauncherTransitionLoading({
    required this.layoutMode,
    required this.activeTab,
  });

  final _LauncherLayoutMode layoutMode;
  final _LauncherTab activeTab;

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);
    final label = layoutMode == _LauncherLayoutMode.portrait
        ? 'Loading ...'
        : 'Loading ...';

    return AbsorbPointer(
      child: AnimatedOpacity(
        opacity: 1,
        duration: const Duration(milliseconds: 180),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: (light ? const Color(0xFFEAF2FA) : const Color(0xFF05070C))
                .withValues(alpha: light ? 0.72 : 0.74),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  color: light
                      ? Colors.white.withValues(alpha: 0.82)
                      : const Color(0xFF0D1622).withValues(alpha: 0.86),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: light
                        ? const Color(0xFFD7E5F2).withValues(alpha: 0.95)
                        : Colors.white.withValues(alpha: 0.08),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: light ? 0.08 : 0.22,
                      ),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: _accentSoftBlue,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      label,
                      style: _sharp(
                        context,
                        Theme.of(context).textTheme.titleSmall,
                        color: _textPrimary,
                        weight: FontWeight.w700,
                        size: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VehicleCanvas extends StatelessWidget {
  const _VehicleCanvas({
    required this.enable3dModel,
    required this.cameraOrbit,
    required this.view,
    required this.activeTab,
    required this.vehicleModelAsset,
    required this.vehicleColor,
    required this.renderQuality,
    required this.layoutMode,
    required this.landscapeSidebarPosition,
    required this.onLandscapeSidebarPositionChanged,
    required this.roadMotionActive,
    required this.reverseRoadMotion,
    required this.vehicleSpeedKmh,
    required this.demoLightMode,
    required this.demoRadarLevel,
    required this.demoRadarZone,
    required this.debugModeEnabled,
    required this.lightEffectEnabled,
    required this.radarEffectEnabled,
    required this.onDemoLightModeChanged,
    required this.onDemoRadarLevelChanged,
    required this.onDemoRadarZoneChanged,
    required this.effectiveGear,
    required this.vehicleSnapshot,
    required this.onGearChanged,
    required this.onViewChanged,
    required this.onTabChanged,
    required this.onVehicleModelChanged,
    required this.onVehicleColorChanged,
    required this.onRenderQualityChanged,
    required this.onLayoutModeChanged,
    required this.navigationApps,
    required this.selectedNavigationPackage,
    required this.launchNavigationWithLauncher,
    required this.defaultLauncherEnabled,
    required this.wallpaperButtonEnabled,
    required this.onDefaultNavigationAppChanged,
    required this.onNavigationReloadRequested,
    required this.onDefaultNavigationOpenRequested,
    required this.onLaunchNavigationWithLauncherChanged,
    required this.onDefaultLauncherChanged,
    required this.wallpaperFolderPath,
    required this.wallpaperIntervalSeconds,
    required this.wallpaperPaths,
    required this.wallpaperIndex,
    required this.onWallpaperReloadRequested,
    required this.onWallpaperIntervalChanged,
    required this.onWallpaperButtonEnabledChanged,
    required this.onLightEffectEnabledChanged,
    required this.onRadarEffectEnabledChanged,
    required this.onDebugModeChanged,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.language,
    required this.onLanguageChanged,
  });

  final bool enable3dModel;
  final String cameraOrbit;
  final _VehicleView view;
  final _LauncherTab activeTab;
  final String vehicleModelAsset;
  final Color vehicleColor;
  final _VehicleRenderQuality renderQuality;
  final _LauncherLayoutMode layoutMode;
  final _LandscapeSidebarPosition landscapeSidebarPosition;
  final ValueChanged<_LandscapeSidebarPosition>
  onLandscapeSidebarPositionChanged;
  final bool roadMotionActive;
  final bool reverseRoadMotion;
  final double vehicleSpeedKmh;
  final _DemoLightMode demoLightMode;
  final _DemoRadarLevel demoRadarLevel;
  final _DemoRadarZone demoRadarZone;
  final bool debugModeEnabled;
  final bool lightEffectEnabled;
  final bool radarEffectEnabled;
  final ValueChanged<_DemoLightMode> onDemoLightModeChanged;
  final ValueChanged<_DemoRadarLevel> onDemoRadarLevelChanged;
  final ValueChanged<_DemoRadarZone> onDemoRadarZoneChanged;
  final _VehicleGear effectiveGear;
  final _VehicleSnapshot vehicleSnapshot;
  final ValueChanged<_VehicleGear> onGearChanged;
  final ValueChanged<_VehicleView> onViewChanged;
  final ValueChanged<_LauncherTab> onTabChanged;
  final ValueChanged<String> onVehicleModelChanged;
  final ValueChanged<Color> onVehicleColorChanged;
  final ValueChanged<_VehicleRenderQuality> onRenderQualityChanged;
  final ValueChanged<_LauncherLayoutMode> onLayoutModeChanged;
  final List<_NavigationApp> navigationApps;
  final String? selectedNavigationPackage;
  final bool launchNavigationWithLauncher;
  final bool defaultLauncherEnabled;
  final bool wallpaperButtonEnabled;
  final ValueChanged<_NavigationApp> onDefaultNavigationAppChanged;
  final VoidCallback onNavigationReloadRequested;
  final VoidCallback onDefaultNavigationOpenRequested;
  final ValueChanged<bool> onLaunchNavigationWithLauncherChanged;
  final ValueChanged<bool> onDefaultLauncherChanged;
  final String? wallpaperFolderPath;
  final int wallpaperIntervalSeconds;
  final List<String> wallpaperPaths;
  final int wallpaperIndex;
  final VoidCallback onWallpaperReloadRequested;
  final ValueChanged<int> onWallpaperIntervalChanged;
  final ValueChanged<bool> onWallpaperButtonEnabledChanged;
  final ValueChanged<bool> onLightEffectEnabledChanged;
  final ValueChanged<bool> onRadarEffectEnabledChanged;
  final ValueChanged<bool> onDebugModeChanged;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final _AppLanguage language;
  final ValueChanged<_AppLanguage>? onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    final wallpaperMode = activeTab == _LauncherTab.wallpaper;
    final portraitMode = layoutMode == _LauncherLayoutMode.portrait;
    final demoEffectsAllowed =
        effectiveGear == _VehicleGear.d || effectiveGear == _VehicleGear.r;
    final visibleDemoLightMode =
        demoEffectsAllowed && debugModeEnabled && lightEffectEnabled
        ? demoLightMode
        : _DemoLightMode.off;
    final visibleDemoRadarLevel =
        demoEffectsAllowed && debugModeEnabled && radarEffectEnabled
        ? demoRadarLevel
        : _DemoRadarLevel.off;

    return Padding(
      padding: wallpaperMode
          ? EdgeInsets.zero
          : portraitMode
          ? const EdgeInsets.fromLTRB(14, 16, 14, 18)
          : const EdgeInsets.fromLTRB(26, 28, 38, 28),
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
                  vehicleModelAsset: vehicleModelAsset,
                  vehicleColor: vehicleColor,
                  renderQuality: renderQuality,
                  roadMotionActive: roadMotionActive,
                  reverseRoadMotion: reverseRoadMotion,
                  vehicleSpeedKmh: vehicleSpeedKmh,
                  demoLightMode: visibleDemoLightMode,
                  demoRadarLevel: visibleDemoRadarLevel,
                  demoRadarZone: demoRadarZone,
                ),
              ),
            ),
          ),
          if (activeTab != _LauncherTab.status)
            Positioned.fill(
              left: 0,
              top: 0,
              right: 0,
              bottom: wallpaperMode ? 0 : 68,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeOutCubic,
                layoutBuilder: (currentChild, previousChildren) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      ...previousChildren.map(
                        (child) => Positioned.fill(child: child),
                      ),
                      if (currentChild != null)
                        Positioned.fill(child: currentChild),
                    ],
                  );
                },
                child: switch (activeTab) {
                  _LauncherTab.settings => _SettingsPanel(
                    key: const ValueKey('settings'),
                    vehicleModelAsset: vehicleModelAsset,
                    onVehicleModelChanged: onVehicleModelChanged,
                    vehicleColor: vehicleColor,
                    onVehicleColorChanged: onVehicleColorChanged,
                    renderQuality: renderQuality,
                    onRenderQualityChanged: onRenderQualityChanged,
                    layoutMode: layoutMode,
                    onLayoutModeChanged: onLayoutModeChanged,
                    landscapeSidebarPosition: landscapeSidebarPosition,
                    onLandscapeSidebarPositionChanged:
                        onLandscapeSidebarPositionChanged,
                    launchNavigationWithLauncher: launchNavigationWithLauncher,
                    defaultLauncherEnabled: defaultLauncherEnabled,
                    hasNavigationApps: navigationApps.isNotEmpty,
                    onLaunchNavigationWithLauncherChanged:
                        onLaunchNavigationWithLauncherChanged,
                    onDefaultLauncherChanged: onDefaultLauncherChanged,
                    wallpaperFolderPath: wallpaperFolderPath,
                    wallpaperIntervalSeconds: wallpaperIntervalSeconds,
                    wallpaperImageCount: wallpaperPaths.length,
                    onWallpaperReloadRequested: onWallpaperReloadRequested,
                    onWallpaperIntervalChanged: onWallpaperIntervalChanged,
                    wallpaperButtonEnabled: wallpaperButtonEnabled,
                    onWallpaperButtonEnabledChanged:
                        onWallpaperButtonEnabledChanged,
                    lightEffectEnabled: lightEffectEnabled,
                    radarEffectEnabled: radarEffectEnabled,
                    debugModeEnabled: debugModeEnabled,
                    onLightEffectEnabledChanged: onLightEffectEnabledChanged,
                    onRadarEffectEnabledChanged: onRadarEffectEnabledChanged,
                    onDebugModeChanged: onDebugModeChanged,
                    themeMode: themeMode,
                    onThemeModeChanged: onThemeModeChanged,
                    language: language,
                    onLanguageChanged: onLanguageChanged,
                  ),
                  _LauncherTab.wallpaper => _WallpaperPanel(
                    key: const ValueKey('wallpaper'),
                    folderPath: wallpaperFolderPath,
                    imagePaths: wallpaperPaths,
                    imageIndex: wallpaperIndex,
                    onReload: onWallpaperReloadRequested,
                  ),
                  _ => _NavigationPanel(
                    key: const ValueKey('navigation'),
                    apps: navigationApps,
                    selectedPackage: selectedNavigationPackage,
                    onAppSelected: onDefaultNavigationAppChanged,
                    onReload: onNavigationReloadRequested,
                    onOpen: onDefaultNavigationOpenRequested,
                  ),
                },
              ),
            ),
          if (activeTab == _LauncherTab.status && !portraitMode)
            Positioned(
              left: 4,
              top: 12,
              right: 430,
              child: _FloatingVehicleControls(
                view: view,
                onRear: () => onViewChanged(_VehicleView.rear),
                debugModeEnabled: debugModeEnabled,
                lightMode: demoLightMode,
                radarLevel: demoRadarLevel,
                radarZone: demoRadarZone,
                onLightModeChanged: onDemoLightModeChanged,
                onRadarLevelChanged: onDemoRadarLevelChanged,
                onRadarZoneChanged: onDemoRadarZoneChanged,
              ),
            ),
          if (activeTab == _LauncherTab.status)
            Positioned(
              top: portraitMode ? 16 : 12,
              right: portraitMode ? 16 : 0,
              width: portraitMode ? 108 : 212,
              height: portraitMode ? 108 : 212,
              child: _PremiumSpeedGearCluster(
                selectedGear: effectiveGear,
                vehicleSpeedKmh: vehicleSpeedKmh,
                onGearChanged: onGearChanged,
                debugModeEnabled: debugModeEnabled,
                compact: portraitMode,
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: wallpaperMode ? 16 : 4,
            child: Center(
              child: _BottomTabs(
                activeTab: activeTab,
                showWallpaperTab: wallpaperButtonEnabled,
                ambientMode: wallpaperMode,
                compactMode: portraitMode,
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
    required this.vehicleModelAsset,
    required this.vehicleColor,
    required this.renderQuality,
    required this.roadMotionActive,
    required this.reverseRoadMotion,
    required this.vehicleSpeedKmh,
    required this.demoLightMode,
    required this.demoRadarLevel,
    required this.demoRadarZone,
  });

  final bool enable3dModel;
  final String cameraOrbit;
  final String vehicleModelAsset;
  final Color vehicleColor;
  final _VehicleRenderQuality renderQuality;
  final bool roadMotionActive;
  final bool reverseRoadMotion;
  final double vehicleSpeedKmh;
  final _DemoLightMode demoLightMode;
  final _DemoRadarLevel demoRadarLevel;
  final _DemoRadarZone demoRadarZone;

  @override
  Widget build(BuildContext context) {
    return _VehicleReveal(
      child: _VehicleEntrance(
        child: _VehicleHero(
          enable3dModel: enable3dModel,
          cameraOrbit: cameraOrbit,
          vehicleModelAsset: vehicleModelAsset,
          vehicleColor: vehicleColor,
          renderQuality: renderQuality,
          roadMotionActive: roadMotionActive,
          reverseRoadMotion: reverseRoadMotion,
          vehicleSpeedKmh: vehicleSpeedKmh,
          demoLightMode: demoLightMode,
          demoRadarLevel: demoRadarLevel,
          demoRadarZone: demoRadarZone,
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

class _WallpaperPanel extends StatefulWidget {
  const _WallpaperPanel({
    required this.folderPath,
    required this.imagePaths,
    required this.imageIndex,
    required this.onReload,
    super.key,
  });

  final String? folderPath;
  final List<String> imagePaths;
  final int imageIndex;
  final VoidCallback onReload;

  @override
  State<_WallpaperPanel> createState() => _WallpaperPanelState();
}

class _WallpaperPanelState extends State<_WallpaperPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _precacheVisibleImages(),
    );
  }

  @override
  void didUpdateWidget(covariant _WallpaperPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageIndex != widget.imageIndex ||
        oldWidget.imagePaths != widget.imagePaths) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _precacheVisibleImages(),
      );
    }
  }

  void _precacheVisibleImages() {
    if (!mounted || widget.imagePaths.isEmpty) return;
    final currentIndex = widget.imageIndex % widget.imagePaths.length;
    final nextIndex = (currentIndex + 1) % widget.imagePaths.length;
    _precacheWallpaper(widget.imagePaths[currentIndex]);
    if (nextIndex != currentIndex) {
      _precacheWallpaper(widget.imagePaths[nextIndex]);
    }
  }

  void _precacheWallpaper(String path) {
    precacheImage(
      _wallpaperProvider(path),
      context,
    ).catchError((Object _) => null);
  }

  ImageProvider _wallpaperProvider(String path) {
    return ResizeImage(
      FileImage(File(path)),
      width: _wallpaperDecodeWidth,
      height: _wallpaperDecodeHeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveIndex = widget.imagePaths.isEmpty
        ? 0
        : widget.imageIndex % widget.imagePaths.length;
    final imagePath = widget.imagePaths.isEmpty
        ? null
        : widget.imagePaths[effectiveIndex];

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              fit: StackFit.expand,
              children: [
                ...previousChildren.map(
                  (child) => Positioned.fill(child: child),
                ),
                if (currentChild != null) Positioned.fill(child: currentChild),
              ],
            );
          },
          child: imagePath != null
              ? Image(
                  key: ValueKey(imagePath),
                  image: _wallpaperProvider(imagePath),
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) =>
                      _WallpaperEmptyState(
                        folderPath: widget.folderPath,
                        onReload: widget.onReload,
                      ),
                )
              : _WallpaperEmptyState(
                  key: const ValueKey('wallpaper-empty'),
                  folderPath: widget.folderPath,
                  onReload: widget.onReload,
                ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.10),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.34),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.imagePaths.length > 1)
          Positioned(
            right: 18,
            top: 18,
            child: _MapStatusPill(
              icon: Icons.photo_library_outlined,
              label: '${effectiveIndex + 1}/${widget.imagePaths.length}',
            ),
          ),
      ],
    );
  }
}

class _WallpaperEmptyState extends StatelessWidget {
  const _WallpaperEmptyState({
    required this.folderPath,
    required this.onReload,
    super.key,
  });

  final String? folderPath;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: light
              ? const [Color(0xFFFDFEFF), Color(0xFFE3EEF8), Color(0xFFD4E2EF)]
              : const [Color(0xFF172235), Color(0xFF090F19), Color(0xFF03060A)],
        ),
      ),
      child: Center(
        child: _GlassCard(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.auto_awesome_outlined,
                color: _accentSoftBlue,
                size: 38,
              ),
              const SizedBox(height: 12),
              Text(
                _t(context, 'noAmbientImages'),
                style: _sharp(
                  context,
                  Theme.of(context).textTheme.titleMedium,
                  color: _textPrimary,
                  weight: FontWeight.w700,
                  size: 18,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                _t(context, 'ambientEmptyHint'),
                textAlign: TextAlign.center,
                style: _sharp(
                  context,
                  Theme.of(context).textTheme.bodyMedium,
                  color: _textMuted,
                  weight: FontWeight.w500,
                  size: 13,
                ),
              ),
              const SizedBox(height: 14),
              _PremiumActionButton(
                icon: Icons.refresh_rounded,
                label: _t(context, 'refresh'),
                onTap: onReload,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WallpaperSettingsCard extends StatelessWidget {
  const _WallpaperSettingsCard({
    required this.folderPath,
    required this.intervalSeconds,
    required this.imageCount,
    required this.onReload,
    required this.onIntervalChanged,
    required this.buttonEnabled,
    required this.onButtonEnabledChanged,
  });

  final String? folderPath;
  final int intervalSeconds;
  final int imageCount;
  final VoidCallback onReload;
  final ValueChanged<int> onIntervalChanged;
  final bool buttonEnabled;
  final ValueChanged<bool> onButtonEnabledChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsSectionTitle(
          icon: Icons.auto_awesome_outlined,
          title: _t(context, 'ambient'),
          subtitle: _t(context, 'ambientSubtitle'),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _isLight(context)
                ? Colors.white.withValues(alpha: 0.52)
                : Colors.white.withValues(alpha: 0.045),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _isLight(context)
                  ? const Color(0xFFD4DEE9).withValues(alpha: 0.84)
                  : Colors.white.withValues(alpha: 0.055),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      folderPath ?? _wallpaperFixedFolderPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _sharp(
                        context,
                        Theme.of(context).textTheme.bodyMedium,
                        color: _textPrimary,
                        weight: FontWeight.w600,
                        size: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$imageCount image${imageCount == 1 ? '' : 's'} ready',
                      style: _sharp(
                        context,
                        Theme.of(context).textTheme.labelMedium,
                        color: _textMuted,
                        weight: FontWeight.w500,
                        size: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _SmallSettingsButton(
                icon: Icons.refresh_rounded,
                onTap: onReload,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SettingsSwitchRow(
          icon: Icons.auto_awesome_outlined,
          title: _t(context, 'showAmbientButton'),
          subtitle: _t(context, 'showAmbientButtonSubtitle'),
          value: buttonEnabled,
          onChanged: onButtonEnabledChanged,
        ),
        const SizedBox(height: 14),
        Text(
          _t(context, 'autoChangeInterval'),
          style: _sharp(
            context,
            Theme.of(context).textTheme.labelLarge,
            color: _textSecondary,
            weight: FontWeight.w600,
            size: 13,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _WallpaperIntervalChip(
              label: 'Off',
              seconds: 0,
              selectedSeconds: intervalSeconds,
              onSelected: onIntervalChanged,
            ),
            _WallpaperIntervalChip(
              label: '30s',
              seconds: 30,
              selectedSeconds: intervalSeconds,
              onSelected: onIntervalChanged,
            ),
            _WallpaperIntervalChip(
              label: '1m',
              seconds: 60,
              selectedSeconds: intervalSeconds,
              onSelected: onIntervalChanged,
            ),
            _WallpaperIntervalChip(
              label: '5m',
              seconds: 300,
              selectedSeconds: intervalSeconds,
              onSelected: onIntervalChanged,
            ),
            _WallpaperIntervalChip(
              label: '10m',
              seconds: 600,
              selectedSeconds: intervalSeconds,
              onSelected: onIntervalChanged,
            ),
            _WallpaperIntervalChip(
              label: '1h',
              seconds: 3600,
              selectedSeconds: intervalSeconds,
              onSelected: onIntervalChanged,
            ),
            _WallpaperIntervalChip(
              label: '4h',
              seconds: 14400,
              selectedSeconds: intervalSeconds,
              onSelected: onIntervalChanged,
            ),
            _WallpaperIntervalChip(
              label: '1d',
              seconds: 86400,
              selectedSeconds: intervalSeconds,
              onSelected: onIntervalChanged,
            ),
          ],
        ),
      ],
    );
  }
}

class _WallpaperIntervalChip extends StatelessWidget {
  const _WallpaperIntervalChip({
    required this.label,
    required this.seconds,
    required this.selectedSeconds,
    required this.onSelected,
  });

  final String label;
  final int seconds;
  final int selectedSeconds;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = seconds == selectedSeconds;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => onSelected(seconds),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? _accentSoftBlue.withValues(
                  alpha: _isLight(context) ? 0.20 : 0.16,
                )
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? _accentSoftBlue.withValues(alpha: 0.45)
                : _tone(context, _textMuted).withValues(alpha: 0.25),
          ),
        ),
        child: Text(
          label,
          style: _sharp(
            context,
            Theme.of(context).textTheme.labelMedium,
            color: selected ? _textPrimary : _textMuted,
            weight: selected ? FontWeight.w700 : FontWeight.w500,
            size: 12,
          ),
        ),
      ),
    );
  }
}

class _SmallSettingsButton extends StatelessWidget {
  const _SmallSettingsButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: _accentSoftBlue.withValues(
            alpha: _isLight(context) ? 0.14 : 0.10,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _accentSoftBlue.withValues(alpha: 0.18)),
        ),
        child: Icon(icon, color: _accentSoftBlue, size: 20),
      ),
    );
  }
}

class _PremiumActionButton extends StatelessWidget {
  const _PremiumActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: _accentSoftBlue.withValues(
            alpha: _isLight(context) ? 0.18 : 0.14,
          ),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _accentSoftBlue.withValues(alpha: 0.26)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _accentSoftBlue, size: 19),
            const SizedBox(width: 8),
            Text(
              label,
              style: _sharp(
                context,
                Theme.of(context).textTheme.labelLarge,
                color: _textPrimary,
                weight: FontWeight.w700,
                size: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.vehicleModelAsset,
    required this.onVehicleModelChanged,
    required this.vehicleColor,
    required this.onVehicleColorChanged,
    required this.renderQuality,
    required this.onRenderQualityChanged,
    required this.layoutMode,
    required this.onLayoutModeChanged,
    required this.landscapeSidebarPosition,
    required this.onLandscapeSidebarPositionChanged,
    required this.launchNavigationWithLauncher,
    required this.defaultLauncherEnabled,
    required this.hasNavigationApps,
    required this.onLaunchNavigationWithLauncherChanged,
    required this.onDefaultLauncherChanged,
    required this.wallpaperFolderPath,
    required this.wallpaperIntervalSeconds,
    required this.wallpaperImageCount,
    required this.onWallpaperReloadRequested,
    required this.onWallpaperIntervalChanged,
    required this.wallpaperButtonEnabled,
    required this.onWallpaperButtonEnabledChanged,
    required this.lightEffectEnabled,
    required this.radarEffectEnabled,
    required this.debugModeEnabled,
    required this.onLightEffectEnabledChanged,
    required this.onRadarEffectEnabledChanged,
    required this.onDebugModeChanged,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.language,
    required this.onLanguageChanged,
    super.key,
  });

  final String vehicleModelAsset;
  final ValueChanged<String> onVehicleModelChanged;
  final Color vehicleColor;
  final ValueChanged<Color> onVehicleColorChanged;
  final _VehicleRenderQuality renderQuality;
  final ValueChanged<_VehicleRenderQuality> onRenderQualityChanged;
  final _LauncherLayoutMode layoutMode;
  final ValueChanged<_LauncherLayoutMode> onLayoutModeChanged;
  final _LandscapeSidebarPosition landscapeSidebarPosition;
  final ValueChanged<_LandscapeSidebarPosition>
  onLandscapeSidebarPositionChanged;
  final bool launchNavigationWithLauncher;
  final bool defaultLauncherEnabled;
  final bool hasNavigationApps;
  final ValueChanged<bool> onLaunchNavigationWithLauncherChanged;
  final ValueChanged<bool> onDefaultLauncherChanged;
  final String? wallpaperFolderPath;
  final int wallpaperIntervalSeconds;
  final int wallpaperImageCount;
  final VoidCallback onWallpaperReloadRequested;
  final ValueChanged<int> onWallpaperIntervalChanged;
  final bool wallpaperButtonEnabled;
  final ValueChanged<bool> onWallpaperButtonEnabledChanged;
  final bool lightEffectEnabled;
  final bool radarEffectEnabled;
  final bool debugModeEnabled;
  final ValueChanged<bool> onLightEffectEnabledChanged;
  final ValueChanged<bool> onRadarEffectEnabledChanged;
  final ValueChanged<bool> onDebugModeChanged;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final _AppLanguage language;
  final ValueChanged<_AppLanguage>? onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    final mainColumn = _SettingsMainColumn(
      vehicleModelAsset: vehicleModelAsset,
      onVehicleModelChanged: onVehicleModelChanged,
      vehicleColor: vehicleColor,
      onVehicleColorChanged: onVehicleColorChanged,
      renderQuality: renderQuality,
      onRenderQualityChanged: onRenderQualityChanged,
      layoutMode: layoutMode,
      onLayoutModeChanged: onLayoutModeChanged,
      landscapeSidebarPosition: landscapeSidebarPosition,
      onLandscapeSidebarPositionChanged: onLandscapeSidebarPositionChanged,
      launchNavigationWithLauncher: launchNavigationWithLauncher,
      defaultLauncherEnabled: defaultLauncherEnabled,
      hasNavigationApps: hasNavigationApps,
      onLaunchNavigationWithLauncherChanged:
          onLaunchNavigationWithLauncherChanged,
      onDefaultLauncherChanged: onDefaultLauncherChanged,
      wallpaperFolderPath: wallpaperFolderPath,
      wallpaperIntervalSeconds: wallpaperIntervalSeconds,
      wallpaperImageCount: wallpaperImageCount,
      onWallpaperReloadRequested: onWallpaperReloadRequested,
      onWallpaperIntervalChanged: onWallpaperIntervalChanged,
      wallpaperButtonEnabled: wallpaperButtonEnabled,
      onWallpaperButtonEnabledChanged: onWallpaperButtonEnabledChanged,
      lightEffectEnabled: lightEffectEnabled,
      radarEffectEnabled: radarEffectEnabled,
      debugModeEnabled: debugModeEnabled,
      onLightEffectEnabledChanged: onLightEffectEnabledChanged,
      onRadarEffectEnabledChanged: onRadarEffectEnabledChanged,
      onDebugModeChanged: onDebugModeChanged,
      themeMode: themeMode,
      onThemeModeChanged: onThemeModeChanged,
      language: language,
      onLanguageChanged: onLanguageChanged,
    );

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
                    _t(context, 'settings'),
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
                    _t(context, 'settingsSubtitle'),
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 760) {
                  final portraitMainColumn = _SettingsMainColumn(
                    scrollable: false,
                    vehicleModelAsset: vehicleModelAsset,
                    onVehicleModelChanged: onVehicleModelChanged,
                    vehicleColor: vehicleColor,
                    onVehicleColorChanged: onVehicleColorChanged,
                    renderQuality: renderQuality,
                    onRenderQualityChanged: onRenderQualityChanged,
                    layoutMode: layoutMode,
                    onLayoutModeChanged: onLayoutModeChanged,
                    landscapeSidebarPosition: landscapeSidebarPosition,
                    onLandscapeSidebarPositionChanged:
                        onLandscapeSidebarPositionChanged,
                    launchNavigationWithLauncher: launchNavigationWithLauncher,
                    defaultLauncherEnabled: defaultLauncherEnabled,
                    hasNavigationApps: hasNavigationApps,
                    onLaunchNavigationWithLauncherChanged:
                        onLaunchNavigationWithLauncherChanged,
                    onDefaultLauncherChanged: onDefaultLauncherChanged,
                    wallpaperFolderPath: wallpaperFolderPath,
                    wallpaperIntervalSeconds: wallpaperIntervalSeconds,
                    wallpaperImageCount: wallpaperImageCount,
                    onWallpaperReloadRequested: onWallpaperReloadRequested,
                    onWallpaperIntervalChanged: onWallpaperIntervalChanged,
                    wallpaperButtonEnabled: wallpaperButtonEnabled,
                    onWallpaperButtonEnabledChanged:
                        onWallpaperButtonEnabledChanged,
                    lightEffectEnabled: lightEffectEnabled,
                    radarEffectEnabled: radarEffectEnabled,
                    debugModeEnabled: debugModeEnabled,
                    onLightEffectEnabledChanged: onLightEffectEnabledChanged,
                    onRadarEffectEnabledChanged: onRadarEffectEnabledChanged,
                    onDebugModeChanged: onDebugModeChanged,
                    themeMode: themeMode,
                    onThemeModeChanged: onThemeModeChanged,
                    language: language,
                    onLanguageChanged: onLanguageChanged,
                  );

                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 22),
                    child: Column(
                      children: [
                        portraitMainColumn,
                        const SizedBox(height: 14),
                        const _SettingsPermissionColumn(),
                      ],
                    ),
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 11, child: mainColumn),
                    const SizedBox(width: 14),
                    const Expanded(flex: 9, child: _SettingsPermissionColumn()),
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

class _SettingsMainColumn extends StatelessWidget {
  const _SettingsMainColumn({
    this.scrollable = true,
    required this.vehicleModelAsset,
    required this.onVehicleModelChanged,
    required this.vehicleColor,
    required this.onVehicleColorChanged,
    required this.renderQuality,
    required this.onRenderQualityChanged,
    required this.layoutMode,
    required this.onLayoutModeChanged,
    required this.landscapeSidebarPosition,
    required this.onLandscapeSidebarPositionChanged,
    required this.launchNavigationWithLauncher,
    required this.defaultLauncherEnabled,
    required this.hasNavigationApps,
    required this.onLaunchNavigationWithLauncherChanged,
    required this.onDefaultLauncherChanged,
    required this.wallpaperFolderPath,
    required this.wallpaperIntervalSeconds,
    required this.wallpaperImageCount,
    required this.onWallpaperReloadRequested,
    required this.onWallpaperIntervalChanged,
    required this.wallpaperButtonEnabled,
    required this.onWallpaperButtonEnabledChanged,
    required this.lightEffectEnabled,
    required this.radarEffectEnabled,
    required this.debugModeEnabled,
    required this.onLightEffectEnabledChanged,
    required this.onRadarEffectEnabledChanged,
    required this.onDebugModeChanged,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.language,
    required this.onLanguageChanged,
  });

  final bool scrollable;
  final String vehicleModelAsset;
  final ValueChanged<String> onVehicleModelChanged;
  final Color vehicleColor;
  final ValueChanged<Color> onVehicleColorChanged;
  final _VehicleRenderQuality renderQuality;
  final ValueChanged<_VehicleRenderQuality> onRenderQualityChanged;
  final _LauncherLayoutMode layoutMode;
  final ValueChanged<_LauncherLayoutMode> onLayoutModeChanged;
  final _LandscapeSidebarPosition landscapeSidebarPosition;
  final ValueChanged<_LandscapeSidebarPosition>
  onLandscapeSidebarPositionChanged;
  final bool launchNavigationWithLauncher;
  final bool defaultLauncherEnabled;
  final bool hasNavigationApps;
  final ValueChanged<bool> onLaunchNavigationWithLauncherChanged;
  final ValueChanged<bool> onDefaultLauncherChanged;
  final String? wallpaperFolderPath;
  final int wallpaperIntervalSeconds;
  final int wallpaperImageCount;
  final VoidCallback onWallpaperReloadRequested;
  final ValueChanged<int> onWallpaperIntervalChanged;
  final bool wallpaperButtonEnabled;
  final ValueChanged<bool> onWallpaperButtonEnabledChanged;
  final bool lightEffectEnabled;
  final bool radarEffectEnabled;
  final bool debugModeEnabled;
  final ValueChanged<bool> onLightEffectEnabledChanged;
  final ValueChanged<bool> onRadarEffectEnabledChanged;
  final ValueChanged<bool> onDebugModeChanged;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final _AppLanguage language;
  final ValueChanged<_AppLanguage>? onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        _GlassCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: _SettingsInlineControl(
            icon: Icons.directions_car_filled_outlined,
            title: _t(context, 'vehicleModel'),
            subtitle: _t(context, 'vehicleModelSubtitle'),
            child: _VehicleModelPicker(
              selectedAsset: vehicleModelAsset,
              onChanged: onVehicleModelChanged,
            ),
          ),
        ),
        const SizedBox(height: 14),
        _GlassCard(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingsSectionTitle(
                icon: Icons.palette_outlined,
                title: _t(context, 'vehicleColor'),
                subtitle: _t(context, 'vehicleColorSubtitle'),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  const columns = 5;
                  const spacing = 8.0;
                  final swatchWidth =
                      (constraints.maxWidth - spacing * (columns - 1)) /
                      columns;

                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
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
              _SettingsSectionTitle(
                icon: Icons.contrast_outlined,
                title: _t(context, 'appearance'),
                subtitle: _t(context, 'appearanceSubtitle'),
              ),
              const SizedBox(height: 14),
              _ThemeModePicker(
                selectedMode: themeMode,
                onChanged: onThemeModeChanged,
              ),
              const SizedBox(height: 14),
              _SettingsInlineControl(
                icon: Icons.translate_outlined,
                title: _t(context, 'language'),
                subtitle: _t(context, 'languageSubtitle'),
                child: _LanguagePicker(
                  selectedLanguage: language,
                  onChanged: onLanguageChanged,
                ),
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
              _SettingsSectionTitle(
                icon: Icons.speed_outlined,
                title: _t(context, 'renderQuality'),
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
              _SettingsSwitchRow(
                icon: Icons.light_mode_outlined,
                title: _t(context, 'lightEffect'),
                subtitle: _t(context, 'lightEffectSubtitle'),
                value: lightEffectEnabled,
                onChanged: onLightEffectEnabledChanged,
              ),
              const SizedBox(height: 12),
              _SettingsSwitchRow(
                icon: Icons.sensors_rounded,
                title: _t(context, 'radarEffect'),
                subtitle: _t(context, 'radarEffectSubtitle'),
                value: radarEffectEnabled,
                onChanged: onRadarEffectEnabledChanged,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _GlassCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: _WallpaperSettingsCard(
            folderPath: wallpaperFolderPath,
            intervalSeconds: wallpaperIntervalSeconds,
            imageCount: wallpaperImageCount,
            onReload: onWallpaperReloadRequested,
            onIntervalChanged: onWallpaperIntervalChanged,
            buttonEnabled: wallpaperButtonEnabled,
            onButtonEnabledChanged: onWallpaperButtonEnabledChanged,
          ),
        ),
        const SizedBox(height: 14),
        _GlassCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            children: [
              _SettingsSwitchRow(
                icon: Icons.home_outlined,
                title: _t(context, 'defaultLauncher'),
                subtitle: defaultLauncherEnabled
                    ? _t(context, 'defaultLauncherReady')
                    : _t(context, 'defaultLauncherChoose'),
                value: defaultLauncherEnabled,
                onChanged: onDefaultLauncherChanged,
              ),
              const SizedBox(height: 12),
              _SettingsInlineControl(
                icon: Icons.screen_rotation_alt_outlined,
                title: _t(context, 'layout'),
                subtitle: _t(context, 'layoutSubtitle'),
                child: _LayoutModePicker(
                  selectedMode: layoutMode,
                  onChanged: onLayoutModeChanged,
                ),
              ),
              const SizedBox(height: 12),
              _SettingsInlineControl(
                icon: Icons.view_sidebar_outlined,
                title: _t(context, 'sidebarPosition'),
                subtitle: _t(context, 'sidebarPositionSubtitle'),
                child: _LandscapeSidebarPositionPicker(
                  selectedPosition: landscapeSidebarPosition,
                  onChanged: onLandscapeSidebarPositionChanged,
                ),
              ),
              const SizedBox(height: 12),
              _SettingsSwitchRow(
                icon: Icons.map_outlined,
                title: _t(context, 'launchNavigation'),
                subtitle: hasNavigationApps
                    ? _t(context, 'launchNavigationReady')
                    : _t(context, 'launchNavigationMissing'),
                value: launchNavigationWithLauncher,
                onChanged: hasNavigationApps
                    ? onLaunchNavigationWithLauncherChanged
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _GlassCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: _SettingsSwitchRow(
            icon: Icons.bug_report_outlined,
            title: _t(context, 'debugMode'),
            subtitle: _t(context, 'debugModeSubtitle'),
            value: debugModeEnabled,
            onChanged: onDebugModeChanged,
          ),
        ),
      ],
    );

    if (!scrollable) return content;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: content,
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
          _SettingsSectionTitle(
            icon: Icons.admin_panel_settings_outlined,
            title: _t(context, 'systemPermissions'),
            subtitle: _t(context, 'systemPermissionsSubtitle'),
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
                ? _t(context, 'checkingPermissions')
                : allReady
                ? _t(context, 'permissionsReady')
                : _t(context, 'grantAllPermissions'),
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
                      ? _t(context, 'allPermissionsReady')
                      : _tx(context, 'permissionsReadyCount', {
                          'ready': readyCount,
                          'total': totalCount,
                        }),
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
                label: _t(context, 'music'),
                status: statuses['musicAccess']!,
              ),
              _PermissionStatusChip(
                label: _t(context, 'overlay'),
                status: statuses['systemOverlay']!,
              ),
              _PermissionStatusChip(
                label: _t(context, 'vehicle'),
                status: statuses['vehicleData']!,
              ),
              _PermissionStatusChip(
                label: _t(context, 'navigation'),
                status: statuses['navigationEmbed']!,
              ),
              _PermissionStatusChip(
                label: _t(context, 'internet'),
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
      borderRadius: BorderRadius.circular(14),
      onTap: () => onTap(color),
      child: Container(
        height: 62,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: selected ? 0.08 : 0.035),
          borderRadius: BorderRadius.circular(14),
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
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.32),
                    blurRadius: 10,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
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
                size: 9.5,
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

class _SettingsInlineControl extends StatelessWidget {
  const _SettingsInlineControl({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

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
          const SizedBox(width: 10),
          child,
        ],
      ),
    );
  }
}

class _LandscapeSidebarPositionPicker extends StatelessWidget {
  const _LandscapeSidebarPositionPicker({
    required this.selectedPosition,
    required this.onChanged,
  });

  final _LandscapeSidebarPosition selectedPosition;
  final ValueChanged<_LandscapeSidebarPosition> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_LandscapeSidebarPosition>(
      segments: [
        ButtonSegment<_LandscapeSidebarPosition>(
          value: _LandscapeSidebarPosition.left,
          icon: Icon(Icons.keyboard_double_arrow_left_rounded, size: 17),
          label: Text(_t(context, 'sidebarLeft')),
        ),
        ButtonSegment<_LandscapeSidebarPosition>(
          value: _LandscapeSidebarPosition.right,
          icon: Icon(Icons.keyboard_double_arrow_right_rounded, size: 17),
          label: Text(_t(context, 'sidebarRight')),
        ),
      ],
      selected: {selectedPosition},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => onChanged(selection.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(
          _sharp(
            context,
            Theme.of(context).textTheme.labelSmall,
            color: _textPrimary,
            weight: FontWeight.w700,
            size: 11,
          ),
        ),
      ),
    );
  }
}

class _LayoutModePicker extends StatelessWidget {
  const _LayoutModePicker({
    required this.selectedMode,
    required this.onChanged,
  });

  final _LauncherLayoutMode selectedMode;
  final ValueChanged<_LauncherLayoutMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_LauncherLayoutMode>(
      segments: [
        ButtonSegment<_LauncherLayoutMode>(
          value: _LauncherLayoutMode.landscape,
          icon: Icon(Icons.stay_current_landscape_outlined, size: 17),
          label: Text(_t(context, 'landscapeShort')),
        ),
        ButtonSegment<_LauncherLayoutMode>(
          value: _LauncherLayoutMode.portrait,
          icon: Icon(Icons.stay_current_portrait_outlined, size: 17),
          label: Text(_t(context, 'portraitShort')),
        ),
      ],
      selected: {selectedMode},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => onChanged(selection.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(
          _sharp(
            context,
            Theme.of(context).textTheme.labelSmall,
            color: _textPrimary,
            weight: FontWeight.w700,
            size: 11,
          ),
        ),
      ),
    );
  }
}

class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({
    required this.selectedLanguage,
    required this.onChanged,
  });

  final _AppLanguage selectedLanguage;
  final ValueChanged<_AppLanguage>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<_AppLanguage>(
        value: selectedLanguage,
        borderRadius: BorderRadius.circular(16),
        onChanged: (language) {
          if (language != null) onChanged?.call(language);
        },
        items: [
          for (final language in _AppLanguage.values)
            DropdownMenuItem<_AppLanguage>(
              value: language,
              child: Text(
                language.label,
                style: _sharp(
                  context,
                  Theme.of(context).textTheme.labelMedium,
                  color: _textPrimary,
                  weight: FontWeight.w700,
                  size: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VehicleModelPicker extends StatelessWidget {
  const _VehicleModelPicker({
    required this.selectedAsset,
    required this.onChanged,
  });

  final String selectedAsset;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _parseVehicleModelAsset(selectedAsset),
        borderRadius: BorderRadius.circular(16),
        onChanged: (asset) {
          if (asset != null) onChanged(asset);
        },
        items: [
          for (final asset in _vehicleModelAssets)
            DropdownMenuItem<String>(
              value: asset,
              child: Text(
                _vehicleModelLabel(asset),
                style: _sharp(
                  context,
                  Theme.of(context).textTheme.labelMedium,
                  color: _textPrimary,
                  weight: FontWeight.w700,
                  size: 12,
                ),
              ),
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
  const _FloatingVehicleControls({
    required this.view,
    required this.onRear,
    required this.debugModeEnabled,
    required this.lightMode,
    required this.radarLevel,
    required this.radarZone,
    required this.onLightModeChanged,
    required this.onRadarLevelChanged,
    required this.onRadarZoneChanged,
  });

  final _VehicleView view;
  final VoidCallback onRear;
  final bool debugModeEnabled;
  final _DemoLightMode lightMode;
  final _DemoRadarLevel radarLevel;
  final _DemoRadarZone radarZone;
  final ValueChanged<_DemoLightMode> onLightModeChanged;
  final ValueChanged<_DemoRadarLevel> onRadarLevelChanged;
  final ValueChanged<_DemoRadarZone> onRadarZoneChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _QuickActionStrip(
          onRear: onRear,
          debugModeEnabled: debugModeEnabled,
          lightMode: lightMode,
          radarLevel: radarLevel,
          radarZone: radarZone,
          onLightModeChanged: onLightModeChanged,
          onRadarLevelChanged: onRadarLevelChanged,
          onRadarZoneChanged: onRadarZoneChanged,
        ),
      ],
    );
  }
}

class _QuickActionStrip extends StatefulWidget {
  const _QuickActionStrip({
    required this.onRear,
    required this.debugModeEnabled,
    required this.lightMode,
    required this.radarLevel,
    required this.radarZone,
    required this.onLightModeChanged,
    required this.onRadarLevelChanged,
    required this.onRadarZoneChanged,
  });

  final VoidCallback onRear;
  final bool debugModeEnabled;
  final _DemoLightMode lightMode;
  final _DemoRadarLevel radarLevel;
  final _DemoRadarZone radarZone;
  final ValueChanged<_DemoLightMode> onLightModeChanged;
  final ValueChanged<_DemoRadarLevel> onRadarLevelChanged;
  final ValueChanged<_DemoRadarZone> onRadarZoneChanged;

  @override
  State<_QuickActionStrip> createState() => _QuickActionStripState();
}

class _QuickActionStripState extends State<_QuickActionStrip> {
  bool _doorsLocked = false;
  bool _busy = false;

  void _cycleLightMode() {
    final values = _DemoLightMode.values;
    final next = values[(widget.lightMode.index + 1) % values.length];
    widget.onLightModeChanged(next);
  }

  void _cycleRadarLevel() {
    final values = _DemoRadarLevel.values;
    final next = values[(widget.radarLevel.index + 1) % values.length];
    widget.onRadarLevelChanged(next);
  }

  void _cycleRadarZone() {
    final values = _DemoRadarZone.values;
    final next = values[(widget.radarZone.index + 1) % values.length];
    widget.onRadarZoneChanged(next);
  }

  Future<bool> _setDoorLock(bool locked) async {
    try {
      final result = await _vehicleChannel.invokeMapMethod<String, dynamic>(
        'controlDoorLock',
        {'locked': locked},
      );
      return result?['ok'] == true;
    } catch (error) {
      debugPrint('DOORLOCK control failed locked=$locked error=$error');
      return false;
    }
  }

  Future<void> _toggleDoorLock() async {
    if (_busy) return;
    final nextLocked = !_doorsLocked;
    setState(() => _busy = true);

    final ok = await _setDoorLock(nextLocked);

    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _doorsLocked = nextLocked;
    });
    debugPrint('DOORLOCK result ok=$ok locked=$nextLocked');
  }

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
              _MiniAction(
                icon: _doorsLocked
                    ? Icons.lock_rounded
                    : Icons.lock_open_rounded,
                label: _doorsLocked ? 'Unlock' : 'Lock',
                onTap: _busy ? null : _toggleDoorLock,
              ),
              if (widget.debugModeEnabled) ...[
                _MiniAction(
                  icon: Icons.light_mode_rounded,
                  label: _demoLightLabel(widget.lightMode),
                  onTap: _cycleLightMode,
                ),
                _MiniAction(
                  icon: Icons.sensors_rounded,
                  label: _demoRadarLabel(widget.radarLevel),
                  onTap: _cycleRadarLevel,
                ),
                _MiniAction(
                  icon: Icons.explore_rounded,
                  label: _demoRadarZoneLabel(widget.radarZone),
                  onTap: _cycleRadarZone,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _demoLightLabel(_DemoLightMode mode) {
  return switch (mode) {
    _DemoLightMode.off => 'Light Off',
    _DemoLightMode.auto => 'Auto',
    _DemoLightMode.lowBeam => 'Low Beam',
    _DemoLightMode.highBeam => 'High Beam',
    _DemoLightMode.fog => 'Fog',
    _DemoLightMode.turnLeft => 'Signal L',
    _DemoLightMode.turnRight => 'Signal R',
  };
}

String _demoRadarLabel(_DemoRadarLevel level) {
  return switch (level) {
    _DemoRadarLevel.off => 'Radar Off',
    _DemoRadarLevel.safe => 'Safe',
    _DemoRadarLevel.far => 'Far',
    _DemoRadarLevel.medium => 'Medium',
    _DemoRadarLevel.close => 'Close',
    _DemoRadarLevel.veryClose => 'Very Close',
  };
}

String _demoRadarZoneLabel(_DemoRadarZone zone) {
  return switch (zone) {
    _DemoRadarZone.rear => 'Rear',
    _DemoRadarZone.front => 'Front',
    _DemoRadarZone.left => 'Left',
    _DemoRadarZone.right => 'Right',
    _DemoRadarZone.all => 'All',
  };
}

Color _demoRadarColor(_DemoRadarLevel level) {
  return switch (level) {
    _DemoRadarLevel.off => Colors.transparent,
    _DemoRadarLevel.safe => const Color(0xFF18D987),
    _DemoRadarLevel.far => const Color(0xFF5BE878),
    _DemoRadarLevel.medium => const Color(0xFFFFD43B),
    _DemoRadarLevel.close => const Color(0xFFFF8A00),
    _DemoRadarLevel.veryClose => const Color(0xFFFF2D2D),
  };
}

Offset _vehicleEffectAnchor(Size size) {
  return Offset(size.width * 0.505, size.height * 0.650);
}

class _LightStatusOverlay extends StatefulWidget {
  const _LightStatusOverlay({required this.mode});

  final _DemoLightMode mode;

  @override
  State<_LightStatusOverlay> createState() => _LightStatusOverlayState();
}

class _LightStatusOverlayState extends State<_LightStatusOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 920),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == _DemoLightMode.off) return const SizedBox.expand();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _LightStatusPainter(
            mode: widget.mode,
            light: _isLight(context),
            pulse: _controller.value,
          ),
        ),
      ),
    );
  }
}

class _LightStatusPainter extends CustomPainter {
  const _LightStatusPainter({
    required this.mode,
    required this.light,
    required this.pulse,
  });

  final _DemoLightMode mode;
  final bool light;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final anchor = _vehicleEffectAnchor(size);
    final centerX = anchor.dx;
    final rearY = anchor.dy - size.height * 0.015;
    final beamTop = size.height * 0.245;
    final intensity = switch (mode) {
      _DemoLightMode.auto => 0.28,
      _DemoLightMode.lowBeam => 0.38,
      _DemoLightMode.highBeam => 0.58,
      _DemoLightMode.fog => 0.34,
      _DemoLightMode.turnLeft || _DemoLightMode.turnRight => 0.26,
      _DemoLightMode.off => 0.0,
    };

    if (mode != _DemoLightMode.turnLeft && mode != _DemoLightMode.turnRight) {
      final beamColor = mode == _DemoLightMode.fog
          ? const Color(0xFFFFF4C2)
          : light
          ? const Color(0xFFD9ECFF)
          : Colors.white;
      final path = Path()
        ..moveTo(centerX - size.width * 0.16, rearY)
        ..lineTo(centerX - size.width * 0.30, beamTop)
        ..quadraticBezierTo(
          centerX,
          beamTop - 24,
          centerX + size.width * 0.30,
          beamTop,
        )
        ..lineTo(centerX + size.width * 0.16, rearY)
        ..close();
      final paint = Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.78),
          radius: 0.80,
          colors: [
            beamColor.withValues(
              alpha: light ? intensity * 0.46 : intensity * 0.70,
            ),
            beamColor.withValues(
              alpha: light ? intensity * 0.15 : intensity * 0.25,
            ),
            Colors.transparent,
          ],
          stops: const [0, 0.44, 1],
        ).createShader(Offset.zero & size)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
      canvas.drawPath(path, paint);
    }

    if (mode == _DemoLightMode.turnLeft || mode == _DemoLightMode.turnRight) {
      final alpha = (0.42 + pulse * 0.42) * (light ? 0.76 : 1.0);
      final signalCenter = Offset(
        mode == _DemoLightMode.turnLeft
            ? centerX - size.width * 0.12
            : centerX + size.width * 0.12,
        anchor.dy - size.height * 0.09,
      );
      final signalPaint = Paint()
        ..shader =
            RadialGradient(
              colors: [
                const Color(0xFFFF9F0A).withValues(alpha: alpha),
                const Color(0xFFFF9F0A).withValues(alpha: alpha * 0.32),
                Colors.transparent,
              ],
            ).createShader(
              Rect.fromCircle(center: signalCenter, radius: size.width * 0.12),
            );
      canvas.drawCircle(signalCenter, size.width * 0.12, signalPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LightStatusPainter oldDelegate) {
    return oldDelegate.mode != mode ||
        oldDelegate.light != light ||
        oldDelegate.pulse != pulse;
  }
}

class _ParkingRadarOverlay extends StatefulWidget {
  const _ParkingRadarOverlay({required this.level, required this.zone});

  final _DemoRadarLevel level;
  final _DemoRadarZone zone;

  @override
  State<_ParkingRadarOverlay> createState() => _ParkingRadarOverlayState();
}

class _ParkingRadarOverlayState extends State<_ParkingRadarOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 980),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.level == _DemoRadarLevel.off) return const SizedBox.expand();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _ParkingRadarPainter(
            level: widget.level,
            zone: widget.zone,
            light: _isLight(context),
            progress: _controller.value,
          ),
        ),
      ),
    );
  }
}

class _ParkingRadarPainter extends CustomPainter {
  const _ParkingRadarPainter({
    required this.level,
    required this.zone,
    required this.light,
    required this.progress,
  });

  final _DemoRadarLevel level;
  final _DemoRadarZone zone;
  final bool light;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (level == _DemoRadarLevel.off) return;

    final color = _demoRadarColor(level);
    final severity = (level.index / (_DemoRadarLevel.values.length - 1))
        .clamp(0.18, 1.0)
        .toDouble();
    final themeAlphaScale = light ? 0.78 : 1.0;

    // OEM parking radar tuning for the current D/R camera: the anchor is
    // intentionally a little below the visual center of the 3D vehicle so the
    // arcs feel attached to the bumper/side sensors instead of floating.
    final center = Offset(size.width * 0.500, size.height * 0.626);
    final carWidth = size.width * 0.224;
    final carHeight = size.height * 0.405;
    final sideGap = size.width * 0.015;
    final rearGap = size.height * 0.000;
    final frontGap = size.height * 0.006;

    final pulse = level == _DemoRadarLevel.veryClose
        ? math.sin(progress * math.pi * 2).abs()
        : math.sin(progress * math.pi * 2).abs() * 0.22;
    final pulseAlpha = level == _DemoRadarLevel.veryClose
        ? 0.80 + pulse * 0.20
        : 0.92 + pulse * 0.08;
    final pulseOffset = level == _DemoRadarLevel.veryClose ? pulse * 2.2 : 0.0;

    final glowRadius = size.shortestSide * (0.145 + severity * 0.048);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: (light ? 0.030 : 0.050) * severity),
          color.withValues(alpha: (light ? 0.012 : 0.026) * severity),
          Colors.transparent,
        ],
        stops: const [0.0, 0.52, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: glowRadius));
    canvas.drawCircle(center, glowRadius, glowPaint);

    final layerCount = switch (level) {
      _DemoRadarLevel.safe => 2,
      _DemoRadarLevel.far => 3,
      _DemoRadarLevel.medium ||
      _DemoRadarLevel.close ||
      _DemoRadarLevel.veryClose => 4,
      _DemoRadarLevel.off => 0,
    };
    final baseStroke = lerpDouble(1.8, 4.6, severity)!;

    Paint segmentPaint(int layer, double alphaScale) {
      final layerFade = (1.0 - layer * 0.18).clamp(0.34, 1.0).toDouble();
      final alpha =
          (0.42 * severity * layerFade * alphaScale * pulseAlpha * themeAlphaScale)
              .clamp(0.035, light ? 0.54 : 0.66)
              .toDouble();
      return Paint()
        ..color = color.withValues(alpha: alpha)
        ..strokeWidth = (baseStroke - layer * 0.34).clamp(1.45, 4.9).toDouble()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          level == _DemoRadarLevel.veryClose ? 1.05 : 0.62,
        );
    }

    void drawSegments({
      required Rect rect,
      required double startAngle,
      required double sweepAngle,
      required int segments,
      required Paint paint,
    }) {
      final gap = math.pi * 0.036;
      final segmentSweep = (sweepAngle - gap * (segments - 1)) / segments;
      for (var i = 0; i < segments; i++) {
        canvas.drawArc(
          rect,
          startAngle + i * (segmentSweep + gap),
          segmentSweep,
          false,
          paint,
        );
      }
    }

    // A subtle perspective helper: front arcs are tighter and flatter, rear
    // arcs are wider and lower. Side arcs lean slightly with the road plane.
    void withPerspective({
      required Offset pivot,
      required double tilt,
      required VoidCallback draw,
    }) {
      canvas.save();
      canvas.translate(pivot.dx, pivot.dy);
      canvas.rotate(tilt);
      canvas.translate(-pivot.dx, -pivot.dy);
      draw();
      canvas.restore();
    }

    void drawRear([double alphaScale = 1.0]) {
      final pivot = Offset(center.dx, center.dy + carHeight * 0.52);
      withPerspective(
        pivot: pivot,
        tilt: 0.0,
        draw: () {
          for (var layer = 0; layer < layerCount; layer++) {
            final t = layer.toDouble();
            final offset = t * size.height * 0.020 + pulseOffset;
            final rect = Rect.fromCenter(
              center: Offset(
                center.dx,
                center.dy + carHeight * 0.430 + rearGap + offset,
              ),
              width: carWidth * 0.98 + t * size.width * 0.030,
              height: size.height * 0.090 + t * size.height * 0.018,
            );
            drawSegments(
              rect: rect,
              startAngle: math.pi * 0.09,
              sweepAngle: math.pi * 0.82,
              segments: 3,
              paint: segmentPaint(layer, alphaScale * (1.26 - t * 0.070)),
            );
          }
        },
      );
    }

    void drawFront([double alphaScale = 1.0]) {
      final pivot = Offset(center.dx, center.dy - carHeight * 0.54);
      withPerspective(
        pivot: pivot,
        tilt: 0.0,
        draw: () {
          for (var layer = 0; layer < layerCount; layer++) {
            final t = layer.toDouble();
            final offset = t * size.height * 0.017 + pulseOffset;
            final rect = Rect.fromCenter(
              center: Offset(
                center.dx,
                center.dy - carHeight * 0.455 - frontGap - offset,
              ),
              width: carWidth * 0.86 + t * size.width * 0.024,
              height: size.height * 0.074 + t * size.height * 0.016,
            );
            drawSegments(
              rect: rect,
              startAngle: math.pi * 1.10,
              sweepAngle: math.pi * 0.80,
              segments: 3,
              paint: segmentPaint(layer, alphaScale * (1.02 - t * 0.060)),
            );
          }
        },
      );
    }

    void drawLeft([double alphaScale = 1.0]) {
      final pivot = Offset(center.dx - carWidth * 0.53, center.dy);
      withPerspective(
        pivot: pivot,
        tilt: -0.045,
        draw: () {
          for (var layer = 0; layer < layerCount; layer++) {
            final t = layer.toDouble();
            final offset = t * size.width * 0.014 + pulseOffset;
            final rect = Rect.fromCenter(
              center: Offset(
                center.dx - carWidth * 0.50 - sideGap - offset,
                center.dy + size.height * 0.006,
              ),
              width: size.width * 0.086 + t * size.width * 0.021,
              height: carHeight * 0.700 + t * size.height * 0.015,
            );
            drawSegments(
              rect: rect,
              startAngle: math.pi * 0.625,
              sweepAngle: math.pi * 0.750,
              segments: 3,
              paint: segmentPaint(layer, alphaScale * (0.72 - t * 0.028)),
            );
          }
        },
      );
    }

    void drawRight([double alphaScale = 1.0]) {
      final pivot = Offset(center.dx + carWidth * 0.53, center.dy);
      withPerspective(
        pivot: pivot,
        tilt: 0.045,
        draw: () {
          for (var layer = 0; layer < layerCount; layer++) {
            final t = layer.toDouble();
            final offset = t * size.width * 0.014 + pulseOffset;
            final rect = Rect.fromCenter(
              center: Offset(
                center.dx + carWidth * 0.50 + sideGap + offset,
                center.dy + size.height * 0.006,
              ),
              width: size.width * 0.086 + t * size.width * 0.021,
              height: carHeight * 0.700 + t * size.height * 0.015,
            );
            drawSegments(
              rect: rect,
              startAngle: math.pi * -0.375,
              sweepAngle: math.pi * 0.750,
              segments: 3,
              paint: segmentPaint(layer, alphaScale * (0.72 - t * 0.028)),
            );
          }
        },
      );
    }

    switch (zone) {
      case _DemoRadarZone.rear:
        drawRear();
      case _DemoRadarZone.front:
        drawFront();
      case _DemoRadarZone.left:
        drawLeft();
      case _DemoRadarZone.right:
        drawRight();
      case _DemoRadarZone.all:
        // All mode should feel like four sensor groups, not one big speaker
        // waveform. Rear is kept strongest for reverse/parking context; front
        // and side groups are intentionally quieter to keep the vehicle clean.
        drawRear(level == _DemoRadarLevel.veryClose ? 1.15 : 1.02);
        drawFront(level == _DemoRadarLevel.veryClose ? 0.68 : 0.58);
        drawLeft(0.66);
        drawRight(0.66);
    }
  }

  @override
  bool shouldRepaint(covariant _ParkingRadarPainter oldDelegate) {
    return oldDelegate.level != level ||
        oldDelegate.zone != zone ||
        oldDelegate.light != light ||
        oldDelegate.progress != progress;
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
    required this.vehicleModelAsset,
    required this.vehicleColor,
    required this.renderQuality,
    required this.roadMotionActive,
    required this.reverseRoadMotion,
    required this.vehicleSpeedKmh,
    required this.demoLightMode,
    required this.demoRadarLevel,
    required this.demoRadarZone,
  });

  final bool enable3dModel;
  final String cameraOrbit;
  final String vehicleModelAsset;
  final Color vehicleColor;
  final _VehicleRenderQuality renderQuality;
  final bool roadMotionActive;
  final bool reverseRoadMotion;
  final double vehicleSpeedKmh;
  final _DemoLightMode demoLightMode;
  final _DemoRadarLevel demoRadarLevel;
  final _DemoRadarZone demoRadarZone;

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
    if (widget.demoRadarLevel != _DemoRadarLevel.off) {
      _hotspotsVisible = false;
      _selectedHotspot = null;
      _hotspotAutoHideTimer?.cancel();
    }

    if (oldWidget.vehicleColor != widget.vehicleColor ||
        oldWidget.vehicleModelAsset != widget.vehicleModelAsset ||
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
    final radarModeActive = widget.demoRadarLevel != _DemoRadarLevel.off;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: radarModeActive ? null : _showHotspots,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _DrivingRoadLayer(
            active: widget.roadMotionActive,
            reverse: widget.reverseRoadMotion,
            speedKmh: widget.vehicleSpeedKmh,
          ),
          _LightStatusOverlay(mode: widget.demoLightMode),
          _ParkingRadarOverlay(
            level: widget.demoRadarLevel,
            zone: widget.demoRadarZone,
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
                    asset: widget.vehicleModelAsset,
                    cameraOrbit: focusedOrbit,
                    vehicleColor: widget.vehicleColor,
                    renderQuality: widget.renderQuality,
                    drivingMode: widget.roadMotionActive,
                    backgroundColor: sceneBackground,
                  )
                : ModelViewer(
                    src: widget.vehicleModelAsset,
                    alt:
                        '${_vehicleModelLabel(widget.vehicleModelAsset)} 3D model',
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
          if (!radarModeActive)
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
    if (!mounted || widget.demoRadarLevel != _DemoRadarLevel.off) return;
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
    final clampedLevel = level.clamp(0.0, 1.0);
    setState(() {
      _hotspotLevels[hotspot] = clampedLevel;
      _selectedHotspot = hotspot;
      _hotspotsVisible = true;
    });
    if (clampedLevel <= 0.02 || clampedLevel >= 0.98) {
      unawaited(_sendBodyworkHotspotCommand(hotspot, clampedLevel));
    }
    _restartHotspotAutoHideTimer();
  }

  Future<void> _sendBodyworkHotspotCommand(
    _VehicleHotspot hotspot,
    double level,
  ) async {
    final action = level >= 0.5 ? 'open' : 'close';
    String method;
    Map<String, Object?> arguments;

    switch (hotspot) {
      case _VehicleHotspot.frontLeftWindow:
        method = 'controlWindow';
        arguments = {'area': 1, 'action': action};
      case _VehicleHotspot.frontRightWindow:
        method = 'controlWindow';
        arguments = {'area': 2, 'action': action};
      case _VehicleHotspot.rearLeftWindow:
        method = 'controlWindow';
        arguments = {'area': 3, 'action': action};
      case _VehicleHotspot.rearRightWindow:
        method = 'controlWindow';
        arguments = {'area': 4, 'action': action};
      case _VehicleHotspot.sunroof:
        method = 'controlSunroof';
        arguments = {'action': action};
      case _VehicleHotspot.trunk:
        method = 'controlTrunk';
        arguments = {'action': action};
    }

    try {
      final result = await _vehicleChannel.invokeMapMethod<String, dynamic>(
        method,
        arguments,
      );
      debugPrint(
        'BODYWORK $method action=$action ok=${result?['ok']} result=$result',
      );
    } on PlatformException catch (error) {
      debugPrint(
        'BODYWORK $method action=$action failed ${error.code}: ${error.message}',
      );
    } on Object catch (error) {
      debugPrint('BODYWORK $method action=$action failed: $error');
    }
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
            alt: '${_vehicleModelLabel(widget.asset)} 3D model',
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

    return AbsorbPointer(
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
  const _BottomTabs({
    required this.activeTab,
    required this.showWallpaperTab,
    required this.ambientMode,
    required this.compactMode,
    required this.onTabChanged,
  });

  final _LauncherTab activeTab;
  final bool showWallpaperTab;
  final bool ambientMode;
  final bool compactMode;
  final ValueChanged<_LauncherTab> onTabChanged;

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);
    final containerColor = ambientMode
        ? Colors.black.withValues(alpha: light ? 0.10 : 0.14)
        : light
        ? Colors.white.withValues(alpha: 0.88)
        : const Color(0xFF07101A).withValues(alpha: 0.62);
    final borderColor = ambientMode
        ? Colors.white.withValues(alpha: light ? 0.26 : 0.18)
        : light
        ? _premiumLightStroke.withValues(alpha: 0.95)
        : Colors.white.withValues(alpha: 0.07);
    final shadowAlpha = ambientMode
        ? (light ? 0.18 : 0.28)
        : (light ? 0.10 : 0.26);

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: ambientMode ? 8 : 24,
          sigmaY: ambientMode ? 8 : 24,
        ),
        child: Container(
          height: 52,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: containerColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: shadowAlpha),
                blurRadius: ambientMode ? 34 : 30,
                offset: const Offset(0, 14),
              ),
              BoxShadow(
                color: _accentSoftBlue.withValues(
                  alpha: ambientMode ? 0.10 : (light ? 0.10 : 0.05),
                ),
                blurRadius: ambientMode ? 32 : 26,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BottomTab(
                icon: Icons.directions_car_filled_outlined,
                label: _t(context, 'vehicle'),
                selected: activeTab == _LauncherTab.status,
                ambientMode: ambientMode,
                compactMode: compactMode,
                onTap: () => onTabChanged(_LauncherTab.status),
              ),
              _BottomTab(
                icon: Icons.navigation_outlined,
                label: _t(context, 'navigation'),
                compactLabel: _t(context, 'navShort'),
                selected: activeTab == _LauncherTab.map,
                ambientMode: ambientMode,
                compactMode: compactMode,
                onTap: () => onTabChanged(_LauncherTab.map),
              ),
              if (showWallpaperTab)
                _BottomTab(
                  icon: Icons.auto_awesome_outlined,
                  label: _t(context, 'ambient'),
                  selected: activeTab == _LauncherTab.wallpaper,
                  ambientMode: ambientMode,
                  compactMode: compactMode,
                  onTap: () => onTabChanged(_LauncherTab.wallpaper),
                ),
              _BottomTab(
                icon: Icons.settings_outlined,
                label: _t(context, 'settings'),
                selected: activeTab == _LauncherTab.settings,
                ambientMode: ambientMode,
                compactMode: compactMode,
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
    this.compactLabel,
    this.selected = false,
    this.ambientMode = false,
    this.compactMode = false,
  });

  final IconData icon;
  final String label;
  final String? compactLabel;
  final VoidCallback onTap;
  final bool selected;
  final bool ambientMode;
  final bool compactMode;

  @override
  Widget build(BuildContext context) {
    final light = _isLight(context);
    final color = ambientMode
        ? (selected ? Colors.white : Colors.white.withValues(alpha: 0.74))
        : selected
        ? (light ? const Color(0xFF1D4F86) : _tone(context, Colors.white))
        : _tone(context, const Color(0xFF9FAEBE));

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: compactMode ? (selected ? 98 : 82) : (selected ? 132 : 116),
        height: 42,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: ambientMode
                      ? [
                          Colors.white.withValues(alpha: 0.12),
                          Colors.white.withValues(alpha: 0.03),
                        ]
                      : light
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
                  color: ambientMode
                      ? Colors.white.withValues(alpha: 0.24)
                      : light
                      ? const Color(0xFF78B7FF).withValues(alpha: 0.38)
                      : Colors.white.withValues(alpha: 0.08),
                  width: 1,
                )
              : null,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFF78B7FF).withValues(
                      alpha: ambientMode ? 0.10 : (light ? 0.20 : 0.12),
                    ),
                    blurRadius: ambientMode ? 22 : 18,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: ambientMode ? 0.22 : (light ? 0.06 : 0.18),
                    ),
                    blurRadius: ambientMode ? 18 : (light ? 16 : 12),
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
                if (!compactMode || selected)
                  Text(
                    compactMode ? (compactLabel ?? label) : label,
                    style: _sharp(
                      context,
                      Theme.of(context).textTheme.titleMedium,
                      color: color,
                      weight: selected ? FontWeight.w600 : FontWeight.w500,
                      size: compactMode ? 12.5 : 14.5,
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

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(const BydLauncherApp());
}

class BydLauncherApp extends StatelessWidget {
  const BydLauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BYD Launcher',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF45A3FF)),
        fontFamily: 'sans-serif',
        useMaterial3: true,
        visualDensity: VisualDensity.standard,
        textTheme: Typography.material2021(
          platform: TargetPlatform.android,
        ).white.apply(bodyColor: _textPrimary, displayColor: _textPrimary),
      ),
      home: const LauncherHomePage(),
    );
  }
}

enum _VehicleView { status, rear }

enum _LauncherTab { status, map, settings }

const Color _textPrimary = Color(0xFFF6FAFF);
const Color _textSecondary = Color(0xFFE5ECF5);
const Color _textMuted = Color(0xFFB7C2CF);
const Color _accentSoftBlue = Color(0xFF78B7FF);

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
    color: color,
    fontWeight: weight,
    fontSize: size,
    height: height,
    letterSpacing: letterSpacing,
    leadingDistribution: TextLeadingDistribution.even,
  );
}

class LauncherHomePage extends StatefulWidget {
  const LauncherHomePage({super.key, this.enable3dModel = true});

  final bool enable3dModel;

  @override
  State<LauncherHomePage> createState() => _LauncherHomePageState();
}

class _LauncherHomePageState extends State<LauncherHomePage> {
  _VehicleView _view = _VehicleView.status;
  _LauncherTab _activeTab = _LauncherTab.status;
  int _vehicleReplayKey = 0;

  String get _cameraOrbit {
    return switch (_view) {
      _VehicleView.rear => '148deg 70deg 105%',
      _VehicleView.status => '38deg 70deg 98%',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B12),
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.40, -0.25),
              radius: 1.18,
              colors: [Color(0xFF202A38), Color(0xFF0B111A), Color(0xFF05070C)],
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
                        child: const _LeftDashboard(),
                      ),
                      Expanded(
                        child: _VehicleCanvas(
                          enable3dModel: widget.enable3dModel,
                          cameraOrbit: _cameraOrbit,
                          view: _view,
                          activeTab: _activeTab,
                          vehicleReplayKey: _vehicleReplayKey,
                          onViewChanged: (view) => setState(() => _view = view),
                          onTabChanged: _handleTabChanged,
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
    setState(() {
      if (tab == _LauncherTab.status) {
        _vehicleReplayKey++;
      }
      _activeTab = tab;
    });
  }
}

class _LeftDashboard extends StatelessWidget {
  const _LeftDashboard();

  @override
  Widget build(BuildContext context) {
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
                colors: [
                  const Color(0xFF101824).withValues(alpha: 0.94),
                  const Color(0xFF070D15).withValues(alpha: 0.90),
                ],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.065),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
                BoxShadow(
                  color: _accentSoftBlue.withValues(alpha: 0.035),
                  blurRadius: 34,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Padding(
              padding: EdgeInsets.fromLTRB(18, 20, 18, 18),
              child: Column(
                children: [
                  _StatusBar(),
                  SizedBox(height: 14),
                  _SpeedCluster(),
                  SizedBox(height: 30),
                  SizedBox(height: 184, child: _MediaWidget()),
                  SizedBox(height: 14),
                  _EnergyStrip(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '10:30',
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
            color: Colors.white.withValues(alpha: 0.055),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.055)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wb_sunny_outlined,
                color: _textSecondary,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                '28°C',
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

class _SpeedCluster extends StatelessWidget {
  const _SpeedCluster();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '0',
          style: _sharp(
            context,
            Theme.of(context).textTheme.displayLarge,
            color: Colors.white,
            weight: FontWeight.w300,
            size: 106,
            height: 0.82,
            letterSpacing: -4.0,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'km/h',
          style: _sharp(
            context,
            Theme.of(context).textTheme.titleMedium,
            color: _textSecondary,
            weight: FontWeight.w500,
            size: 15,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.055)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _GearText('P', active: true),
              _GearText('R'),
              _GearText('N'),
              _GearText('D'),
              const SizedBox(width: 10),
              Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: Color(0xFF25D366),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'READY',
                style: _sharp(
                  context,
                  Theme.of(context).textTheme.labelMedium,
                  color: const Color(0xFF25D366),
                  weight: FontWeight.w600,
                  size: 12,
                  letterSpacing: 0.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GearText extends StatelessWidget {
  const _GearText(this.label, {this.active = false});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
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
    );
  }
}

class _TpmsCluster extends StatelessWidget {
  const _TpmsCluster();

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
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
                  Theme.of(context).textTheme.titleSmall,
                  color: _textPrimary,
                  weight: FontWeight.w700,
                  size: 13,
                  letterSpacing: 0.45,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Normal',
                  style: _sharp(
                    context,
                    Theme.of(context).textTheme.labelSmall,
                    color: const Color(0xFF64E58A),
                    weight: FontWeight.w600,
                    size: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: Center(
                        child: SizedBox(
                          width: 82,
                          height: constraints.maxHeight * 0.94,
                          child: Image.asset(
                            'assets/images/sealion6_tpms_top_view.png',
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                    ),

                    Positioned(
                      left: 0,
                      top: 16,
                      child: _PressureBlock(value: '2.6 bar', temp: '28°C'),
                    ),
                    Positioned(
                      right: 0,
                      top: 16,
                      child: _PressureBlock(
                        value: '2.6 bar',
                        temp: '28°C',
                        alignRight: true,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      bottom: 16,
                      child: _PressureBlock(value: '2.6 bar', temp: '27°C'),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 16,
                      child: _PressureBlock(
                        value: '2.6 bar',
                        temp: '27°C',
                        alignRight: true,
                      ),
                    ),

                    const Positioned(
                      left: 62,
                      top: 44,
                      child: _TpmsLine(width: 32),
                    ),
                    const Positioned(
                      right: 62,
                      top: 44,
                      child: _TpmsLine(width: 32, flip: true),
                    ),
                    const Positioned(
                      left: 62,
                      bottom: 44,
                      child: _TpmsLine(width: 32),
                    ),
                    const Positioned(
                      right: 62,
                      bottom: 44,
                      child: _TpmsLine(width: 32, flip: true),
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

class _MediaWidget extends StatelessWidget {
  const _MediaWidget();

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 66,
                height: 66,
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
                child: const Icon(
                  Icons.music_note_rounded,
                  color: Color(0xFFFFD36E),
                  size: 32,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Blinding Lights',
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
                      'The Weeknd',
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
              const Icon(Icons.bluetooth, color: _accentSoftBlue, size: 20),
            ],
          ),
          const Spacer(),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: const LinearProgressIndicator(
              value: 0.42,
              minHeight: 3,
              color: _accentSoftBlue,
              backgroundColor: Color(0xFF293241),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.skip_previous_rounded,
                color: _textSecondary,
                size: 26,
              ),
              const SizedBox(width: 22),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.07),
                  ),
                ),
                child: const Icon(
                  Icons.pause_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 22),
              const Icon(
                Icons.skip_next_rounded,
                color: _textSecondary,
                size: 26,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EnergyStrip extends StatelessWidget {
  const _EnergyStrip();

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
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
                '840',
                style: _sharp(
                  context,
                  Theme.of(context).textTheme.headlineMedium,
                  color: _textPrimary,
                  weight: FontWeight.w500,
                  size: 30,
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
          const SizedBox(height: 13),
          const Row(
            children: [
              Expanded(
                child: _EnergyLevel(
                  icon: Icons.local_gas_station,
                  label: 'Fuel',
                  value: '80%',
                  color: Color(0xFF25D366),
                  progress: 0.80,
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: _EnergyLevel(
                  icon: Icons.battery_5_bar,
                  label: 'Battery',
                  value: '68%',
                  color: _accentSoftBlue,
                  progress: 0.68,
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
            Icon(icon, color: _textSecondary, size: 16),
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
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            color: color,
            backgroundColor: const Color(0xFF293241),
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
    required this.vehicleReplayKey,
    required this.onViewChanged,
    required this.onTabChanged,
  });

  final bool enable3dModel;
  final String cameraOrbit;
  final _VehicleView view;
  final _LauncherTab activeTab;
  final int vehicleReplayKey;
  final ValueChanged<_VehicleView> onViewChanged;
  final ValueChanged<_LauncherTab> onTabChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 28, 38, 28),
      child: Stack(
        children: [
          Positioned.fill(
            left: 0,
            top: 12,
            right: 0,
            bottom: 68,
            child: Offstage(
              offstage: activeTab != _LauncherTab.status,
              child: IgnorePointer(
                ignoring: activeTab != _LauncherTab.status,
                child: _VehicleStage(
                  key: ValueKey('vehicle-stage-$vehicleReplayKey'),
                  enable3dModel: enable3dModel,
                  cameraOrbit: cameraOrbit,
                ),
              ),
            ),
          ),
          if (activeTab != _LauncherTab.status)
            Positioned.fill(
              left: 0,
              top: 12,
              right: 0,
              bottom: 68,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeOutCubic,
                child: activeTab == _LauncherTab.settings
                    ? const _SettingsPanel(key: ValueKey('settings'))
                    : const _NavigationPanel(key: ValueKey('navigation')),
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
            const Positioned(
              top: 12,
              right: 0,
              width: 212,
              height: 172,
              child: _TpmsCluster(),
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
    super.key,
    required this.enable3dModel,
    required this.cameraOrbit,
  });

  final bool enable3dModel;
  final String cameraOrbit;

  @override
  Widget build(BuildContext context) {
    return _VehicleReveal(
      child: _VehicleEntrance(
        child: _VehicleHero(
          enable3dModel: enable3dModel,
          cameraOrbit: cameraOrbit,
        ),
      ),
    );
  }
}

class _NavigationPanel extends StatelessWidget {
  const _NavigationPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
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
          const Positioned(top: 16, left: 18, child: _NavigationAppPicker()),
          Positioned(
            top: 22,
            right: 22,
            child: _MapStatusPill(icon: Icons.gps_fixed, label: 'GPS Ready'),
          ),
          Center(
            child: Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: _accentSoftBlue.withValues(alpha: 0.14),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _accentSoftBlue.withValues(alpha: 0.34),
                ),
                boxShadow: [
                  BoxShadow(
                    color: _accentSoftBlue.withValues(alpha: 0.20),
                    blurRadius: 28,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(
                Icons.navigation_rounded,
                color: _textPrimary,
                size: 34,
              ),
            ),
          ),
          Positioned(
            left: 26,
            right: 26,
            bottom: 28,
            child: _GlassCard(
              padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
              child: Row(
                children: [
                  const Icon(
                    Icons.place_outlined,
                    color: _accentSoftBlue,
                    size: 22,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Navigation',
                          style: _sharp(
                            context,
                            Theme.of(context).textTheme.titleMedium,
                            color: _textPrimary,
                            weight: FontWeight.w700,
                            size: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Choose your preferred map app from the floating picker.',
                          maxLines: 1,
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
                  const SizedBox(width: 12),
                  const _MapStatusPill(
                    icon: Icons.route_outlined,
                    label: 'No route',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigationAppPicker extends StatelessWidget {
  const _NavigationAppPicker();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF07101A).withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.apps_outlined, color: _accentSoftBlue, size: 19),
              const SizedBox(width: 8),
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
              const SizedBox(width: 10),
              const _NavigationAppChip(label: 'BYD'),
              const SizedBox(width: 7),
              const _NavigationAppChip(label: 'Google'),
              const SizedBox(width: 7),
              const _NavigationAppChip(label: 'Waze'),
              const SizedBox(width: 6),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: _textSecondary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavigationAppChip extends StatelessWidget {
  const _NavigationAppChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final selected = label == 'BYD';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: selected
            ? _accentSoftBlue.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected
              ? _accentSoftBlue.withValues(alpha: 0.30)
              : Colors.white.withValues(alpha: 0.055),
        ),
      ),
      child: Text(
        label,
        style: _sharp(
          context,
          Theme.of(context).textTheme.labelSmall,
          color: selected ? _textPrimary : _textMuted,
          weight: selected ? FontWeight.w700 : FontWeight.w500,
          size: 11.5,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF07101A).withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
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
  const _SettingsPanel({super.key});

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
              children: const [
                Expanded(flex: 11, child: _SettingsMainColumn()),
                SizedBox(width: 14),
                Expanded(flex: 9, child: _SettingsPermissionColumn()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsMainColumn extends StatelessWidget {
  const _SettingsMainColumn();

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
                const Row(
                  children: [
                    _VehicleColorSwatch(
                      label: 'Arctic',
                      color: Color(0xFFE9EEF4),
                      selected: true,
                    ),
                    SizedBox(width: 10),
                    _VehicleColorSwatch(
                      label: 'Azure',
                      color: Color(0xFF1687FF),
                    ),
                    SizedBox(width: 10),
                    _VehicleColorSwatch(
                      label: 'Graphite',
                      color: Color(0xFF4D5661),
                    ),
                    SizedBox(width: 10),
                    _VehicleColorSwatch(
                      label: 'Onyx',
                      color: Color(0xFF10141B),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _GlassCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _SettingsSectionTitle(
                  icon: Icons.contrast_outlined,
                  title: 'Appearance',
                  subtitle:
                      'Choose a light theme, dark theme, or follow the system setting.',
                ),
                SizedBox(height: 14),
                _ThemeModePicker(),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _GlassCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              children: const [
                _SettingsSwitchRow(
                  icon: Icons.home_outlined,
                  title: 'Default launcher',
                  subtitle:
                      'Open this launcher when the vehicle head unit starts.',
                  value: true,
                ),
                SizedBox(height: 12),
                _SettingsSwitchRow(
                  icon: Icons.screen_rotation_alt_outlined,
                  title: 'Force landscape',
                  subtitle:
                      'Keep the launcher optimized for the 15.6 inch display.',
                  value: true,
                ),
                SizedBox(height: 12),
                _SettingsSwitchRow(
                  icon: Icons.motion_photos_auto_outlined,
                  title: 'Vehicle animation',
                  subtitle:
                      'Animate the vehicle preview when the launcher opens.',
                  value: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsPermissionColumn extends StatelessWidget {
  const _SettingsPermissionColumn();

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _SettingsSectionTitle(
            icon: Icons.admin_panel_settings_outlined,
            title: 'System permissions',
            subtitle:
                'Required for overlay, bridge, vehicle data and launcher behavior.',
          ),
          SizedBox(height: 16),
          _PermissionRow(
            icon: Icons.layers_outlined,
            title: 'System overlay',
            status: 'Needed',
            highlighted: true,
          ),
          SizedBox(height: 10),
          _PermissionRow(
            icon: Icons.directions_car_outlined,
            title: 'Vehicle bridge',
            status: 'Ready',
          ),
          SizedBox(height: 10),
          _PermissionRow(
            icon: Icons.usb_outlined,
            title: 'ADB bridge',
            status: 'Optional',
          ),
          SizedBox(height: 10),
          _PermissionRow(
            icon: Icons.network_check_outlined,
            title: 'Internet',
            status: 'Granted',
          ),
          Spacer(),
          _SettingsActionButton(),
        ],
      ),
    );
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
    this.selected = false,
  });

  final String label;
  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Expanded(
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
                color: selected ? _textPrimary : _textMuted,
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
  const _ThemeModePicker();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: const Row(
        children: [
          _ThemeModeOption(icon: Icons.light_mode_outlined, label: 'Light'),
          _ThemeModeOption(
            icon: Icons.dark_mode_outlined,
            label: 'Dark',
            selected: true,
          ),
          _ThemeModeOption(
            icon: Icons.brightness_auto_outlined,
            label: 'System',
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
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? _textPrimary : _textMuted;
    return Expanded(
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
    );
  }
}

class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.045)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _textSecondary, size: 21),
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
            onChanged: (_) {},
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
  });

  final IconData icon;
  final String title;
  final String status;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: highlighted
            ? const Color(0xFF78B7FF).withValues(alpha: 0.09)
            : Colors.black.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted
              ? _accentSoftBlue.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.045),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: highlighted ? _accentSoftBlue : _textSecondary,
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
        ],
      ),
    );
  }
}

class _SettingsActionButton extends StatelessWidget {
  const _SettingsActionButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: _accentSoftBlue.withValues(alpha: 0.18),
          foregroundColor: _textPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: () {},
        icon: const Icon(Icons.open_in_new_outlined, size: 18),
        label: Text(
          'Open system settings',
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0B111A).withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.075),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: const Color(0xFF78B7FF).withValues(alpha: 0.055),
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
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFFEAF1F8), size: 17),
            const SizedBox(width: 7),
            Text(
              label,
              style: _sharp(
                context,
                Theme.of(context).textTheme.labelSmall,
                color: const Color(0xFFD8E2ED),
                weight: FontWeight.w500,
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
  late final Animation<double> _blurOpacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 980),
    );

    final runCurve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuart,
    );

    final fadeCurve = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.02, 0.55, curve: Curves.easeOutCubic),
    );

    final trailCurve = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.00, 0.82, curve: Curves.easeOutCubic),
    );

    _opacity = Tween<double>(begin: 0.15, end: 1).animate(fadeCurve);
    _blurOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 32),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 68),
    ]).animate(trailCurve);

    // Chỉ trượt toàn bộ khung model vào vị trí, không scale model nên xe không bị nhỏ lại.
    _offset = Tween<Offset>(
      begin: const Offset(520, -70),
      end: Offset.zero,
    ).animate(runCurve);

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
        return Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: Opacity(
                opacity: _blurOpacity.value,
                child: Transform.translate(
                  offset: _offset.value * 0.62,
                  child: const _VehicleRunInPreview(),
                ),
              ),
            ),
            Opacity(
              opacity: _opacity.value,
              child: Transform.translate(
                offset: _offset.value,
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _VehicleRunInPreview extends StatelessWidget {
  const _VehicleRunInPreview();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.52,
        heightFactor: 0.86,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Positioned(
              left: 28,
              right: 28,
              bottom: 90,
              child: _VehicleMotionTrail(),
            ),
            Positioned(
              left: 62,
              right: 62,
              bottom: 78,
              child: Container(
                height: 24,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.30),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VehicleMotionTrail extends StatelessWidget {
  const _VehicleMotionTrail();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 86,
      child: Stack(
        children: const [
          Positioned(
            left: 0,
            right: 80,
            top: 18,
            child: _MotionLine(width: 280),
          ),
          Positioned(
            left: 38,
            right: 118,
            top: 42,
            child: _MotionLine(width: 210),
          ),
          Positioned(
            left: 88,
            right: 168,
            top: 66,
            child: _MotionLine(width: 150),
          ),
        ],
      ),
    );
  }
}

class _MotionLine extends StatelessWidget {
  const _MotionLine({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: width,
        height: 2,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.transparent,
              _accentSoftBlue.withValues(alpha: 0.18),
              Colors.white.withValues(alpha: 0.30),
            ],
          ),
        ),
      ),
    );
  }
}

class _VehicleHero extends StatelessWidget {
  const _VehicleHero({required this.enable3dModel, required this.cameraOrbit});

  final bool enable3dModel;
  final String cameraOrbit;

  @override
  Widget build(BuildContext context) {
    if (!enable3dModel) {
      return const _VehicleModelPlaceholder();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: ModelViewer(
        src: 'assets/models/2024_byd_seal_u_dm-i2.glb',
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
        cameraOrbit: cameraOrbit,
        minCameraOrbit: 'auto 42deg 74%',
        maxCameraOrbit: 'auto 86deg 142%',
        fieldOfView: '22deg',
        minFieldOfView: '22deg',
        maxFieldOfView: '22deg',
        exposure: 0.78,
        shadowIntensity: 0.30,
        relatedCss: ':root { --poster-color: transparent; }',
      ),
    );
  }
}

class _VehicleModelPlaceholder extends StatelessWidget {
  const _VehicleModelPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 520,
        height: 300,
        decoration: BoxDecoration(
          color: const Color(0xFF111923),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF263241)),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          height: 52,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: const Color(0xFF07101A).withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.07),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.26),
                blurRadius: 30,
                offset: const Offset(0, 14),
              ),
              BoxShadow(
                color: const Color(0xFF78B7FF).withValues(alpha: 0.06),
                blurRadius: 28,
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
    final color = selected ? Colors.white : const Color(0xFF9FAEBE);
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
                  colors: [
                    const Color(0xFF233040).withValues(alpha: 0.96),
                    const Color(0xFF121C28).withValues(alpha: 0.96),
                  ],
                )
              : null,
          border: selected
              ? Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1,
                )
              : null,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFF78B7FF).withValues(alpha: 0.12),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 12,
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
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.060),
                Colors.white.withValues(alpha: 0.030),
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.065),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.13),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

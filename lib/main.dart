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
                          onViewChanged: (view) => setState(() => _view = view),
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
    required this.onViewChanged,
  });

  final bool enable3dModel;
  final String cameraOrbit;
  final _VehicleView view;
  final ValueChanged<_VehicleView> onViewChanged;

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
            child: _VehicleReveal(
              child: _VehicleEntrance(
                child: _VehicleHero(
                  enable3dModel: enable3dModel,
                  cameraOrbit: cameraOrbit,
                ),
              ),
            ),
          ),
          Positioned(
            left: 4,
            top: 12,
            right: 430,
            child: _FloatingVehicleControls(
              view: view,
              onRear: () => onViewChanged(_VehicleView.rear),
            ),
          ),
          const Positioned(
            top: 12,
            right: 0,
            width: 212,
            height: 172,
            child: _TpmsCluster(),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 4,
            child: Center(child: _BottomTabs()),
          ),
        ],
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
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(curve);
    _offset = Tween<Offset>(
      begin: const Offset(120, 0),
      end: Offset.zero,
    ).animate(curve);
    _controller.forward();
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
        return Opacity(
          opacity: _opacity.value,
          child: Transform.translate(offset: _offset.value, child: child),
        );
      },
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
        src: 'assets/models/2024_byd_seal_u_dm-i.glb',
        alt: '2024 BYD Seal U DM-i 3D model',
        backgroundColor: Colors.transparent,
        cameraControls: true,
        autoRotate: false,
        disableZoom: true,
        interactionPrompt: InteractionPrompt.none,
        cameraOrbit: cameraOrbit,
        minCameraOrbit: 'auto 42deg 74%',
        maxCameraOrbit: 'auto 86deg 142%',
        fieldOfView: '22deg',
        exposure: 0.78,
        shadowIntensity: 0.30,
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
  const _BottomTabs();

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
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BottomTab(
                icon: Icons.directions_car_filled_outlined,
                label: 'Status',
                selected: true,
              ),
              _BottomTab(icon: Icons.navigation_outlined, label: 'Map'),
              _BottomTab(icon: Icons.settings_outlined, label: 'Settings'),
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
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : const Color(0xFF9FAEBE);
    return AnimatedContainer(
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
            ? Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1)
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

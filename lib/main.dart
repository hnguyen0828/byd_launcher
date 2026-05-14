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
              final sidebarWidth = compact ? 292.0 : 360.0;

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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF090E16).withValues(alpha: 0.96),
        border: const Border(right: BorderSide(color: Color(0xFF222B37))),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 30, 18, 24),
        child: Column(
          children: [
            const _StatusBar(),
            const SizedBox(height: 10),
            const _SpeedCluster(),
            const SizedBox(height: 10),
            const _SoftDivider(),
            const SizedBox(height: 10),
            const Expanded(child: _TpmsCluster()),
            const SizedBox(height: 10),
            const _SoftDivider(),
            const SizedBox(height: 10),
            const _MediaWidget(),
            const SizedBox(height: 8),
            const _EnergyStrip(),
          ],
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
          '10:30 AM',
          style: _sharp(
            context,
            Theme.of(context).textTheme.bodyLarge,
            color: _textPrimary,
            weight: FontWeight.w500,
            size: 17,
            letterSpacing: 0.1,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wb_sunny_outlined,
              color: Color(0xFFE6EBF2),
              size: 20,
            ),
            const SizedBox(width: 6),
            Text(
              '28°C',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: const Color(0xFFE6EBF2),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SoftDivider extends StatelessWidget {
  const _SoftDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            const Color(0xFF2A3544).withValues(alpha: 0.85),
            Colors.transparent,
          ],
        ),
      ),
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
            weight: FontWeight.w400,
            size: 80,
            height: 0.88,
            letterSpacing: -2.4,
          ),
        ),
        Text(
          'km/h',
          style: _sharp(
            context,
            Theme.of(context).textTheme.titleMedium,
            color: _textSecondary,
            weight: FontWeight.w500,
            size: 17,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _GearText('P', active: true),
            _GearText('R'),
            _GearText('N'),
            _GearText('D'),
            const SizedBox(width: 14),
            Text(
              'READY',
              style: _sharp(
                context,
                Theme.of(context).textTheme.bodyMedium,
                color: const Color(0xFF25D366),
                weight: FontWeight.w700,
                size: 15,
                letterSpacing: 0.5,
              ),
            ),
          ],
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        label,
        style: _sharp(
          context,
          Theme.of(context).textTheme.bodyMedium,
          color: active ? const Color(0xFF45A3FF) : _textMuted,
          weight: FontWeight.w600,
          size: 15,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _TpmsCluster extends StatelessWidget {
  const _TpmsCluster();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const Icon(
              Icons.tire_repair_outlined,
              color: Color(0xFF45A3FF),
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'TPMS',
              style: _sharp(
                context,
                Theme.of(context).textTheme.titleSmall,
                color: _textPrimary,
                weight: FontWeight.w700,
                size: 15,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Center(
            child: SizedBox(
              width: 300,
              height: 230,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Positioned(
                    top: 74,
                    left: 76,
                    child: _TpmsLine(width: 45),
                  ),
                  const Positioned(
                    top: 74,
                    right: 76,
                    child: _TpmsLine(width: 45, flip: true),
                  ),
                  const Positioned(
                    bottom: 62,
                    left: 76,
                    child: _TpmsLine(width: 45),
                  ),
                  const Positioned(
                    bottom: 62,
                    right: 76,
                    child: _TpmsLine(width: 45, flip: true),
                  ),
                  const Positioned(
                    top: 42,
                    left: 0,
                    child: _PressureBlock(value: '2.6 bar', temp: '28°C'),
                  ),
                  const Positioned(
                    top: 42,
                    right: 0,
                    child: _PressureBlock(
                      value: '2.6 bar',
                      temp: '28°C',
                      alignRight: true,
                    ),
                  ),
                  const Positioned(
                    bottom: 34,
                    left: 0,
                    child: _PressureBlock(value: '2.6 bar', temp: '27°C'),
                  ),
                  const Positioned(
                    bottom: 34,
                    right: 0,
                    child: _PressureBlock(
                      value: '2.6 bar',
                      temp: '27°C',
                      alignRight: true,
                    ),
                  ),
                  Positioned.fill(
                    child: Center(
                      child: SizedBox(
                        width: 88,
                        height: 224,
                        child: Image.asset(
                          'assets/images/sealion6_tpms_top_view.png',
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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
      width: 74,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: alignRight
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: _sharp(
              context,
              Theme.of(context).textTheme.bodyMedium,
              color: _textPrimary,
              weight: FontWeight.w600,
              size: 14,
              height: 1.05,
              letterSpacing: 0.05,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            temp,
            style: _sharp(
              context,
              Theme.of(context).textTheme.bodySmall,
              color: _textSecondary,
              weight: FontWeight.w500,
              size: 12,
              height: 1,
              letterSpacing: 0.05,
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
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: const Color(0xFF3B1118),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.music_note,
                color: Color(0xFFFFC857),
                size: 38,
              ),
            ),
            const SizedBox(width: 16),
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
                      size: 17,
                      letterSpacing: 0.05,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'The Weeknd',
                    style: _sharp(
                      context,
                      Theme.of(context).textTheme.bodyMedium,
                      color: _textSecondary,
                      weight: FontWeight.w500,
                      size: 14,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.bluetooth, color: Color(0xFF45A3FF)),
          ],
        ),
        const SizedBox(height: 14),
        const LinearProgressIndicator(
          value: 0.42,
          minHeight: 4,
          color: Color(0xFF45A3FF),
          backgroundColor: Color(0xFF313944),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: const [
            Icon(Icons.skip_previous, color: Colors.white, size: 30),
            Icon(Icons.pause, color: Colors.white, size: 34),
            Icon(Icons.skip_next, color: Colors.white, size: 30),
          ],
        ),
      ],
    );
  }
}

class _EnergyStrip extends StatelessWidget {
  const _EnergyStrip();

  @override
  Widget build(BuildContext context) {
    return const Row(
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
            color: Color(0xFF45A3FF),
            progress: 0.68,
          ),
        ),
      ],
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
            Icon(icon, color: const Color(0xFFD9E0EA), size: 19),
            const SizedBox(width: 7),
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
                  size: 13,
                  letterSpacing: 0.1,
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
                size: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        LinearProgressIndicator(
          value: progress,
          minHeight: 5,
          color: color,
          backgroundColor: const Color(0xFF313944),
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
              const _MiniAction(icon: Icons.window_outlined, label: 'Windows'),
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
                label: 'Vehicle',
                selected: true,
              ),
              _BottomTab(icon: Icons.navigation_outlined, label: 'Navigation'),
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
      width: selected ? 156 : 138,
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
    );
  }
}

class _DarkPanel extends StatelessWidget {
  const _DarkPanel({
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF101721).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF202A36)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

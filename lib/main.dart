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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF369CFF)),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const LauncherHomePage(),
    );
  }
}

enum _VehicleView { status, rear }

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
        color: const Color(0xFF090E16).withValues(alpha: 0.78),
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
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: const Color(0xFFE6EBF2),
            fontWeight: FontWeight.w700,
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
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
            color: Colors.white,
            fontSize: 74,
            height: 0.95,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          'km/h',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: const Color(0xFFE1E7EF),
            fontWeight: FontWeight.w600,
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
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF25D366),
                fontWeight: FontWeight.w800,
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
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: active ? const Color(0xFF45A3FF) : const Color(0xFF98A4B3),
          fontWeight: FontWeight.w800,
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
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Center(
            child: FittedBox(
              fit: BoxFit.contain,
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
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            temp,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFFE0E7F0),
              fontWeight: FontWeight.w600,
              fontSize: 10,
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
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'The Weeknd',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFFD2D9E3),
                      fontWeight: FontWeight.w700,
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
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: const Color(0xFFD2D9E3),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
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
            left: 0,
            top: 10,
            right: 430,
            child: _FloatingVehicleControls(
              view: view,
              onRear: () => onViewChanged(_VehicleView.rear),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
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
    return _DarkPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _MiniAction(icon: Icons.lock_outline, label: 'Lock'),
          _MiniAction(
            icon: Icons.airport_shuttle_outlined,
            label: 'Trunk',
            onTap: onRear,
          ),
          const _MiniAction(icon: Icons.no_crash_outlined, label: 'Win Lock'),
          const _MiniAction(
            icon: Icons.flip_to_front_outlined,
            label: 'Mirrors',
          ),
        ],
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
      borderRadius: BorderRadius.circular(11),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFFDCE6F2), size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: const Color(0xFFC9D3DF),
                fontWeight: FontWeight.w800,
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
                    const Color(0xFF45A3FF).withValues(alpha: 0.18),
                    const Color(0xFF45A3FF).withValues(alpha: 0.055),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        _BottomTab(
          icon: Icons.directions_car_filled_outlined,
          label: 'Status',
          selected: true,
        ),
        SizedBox(width: 14),
        _BottomTab(icon: Icons.navigation_outlined, label: 'Map'),
        SizedBox(width: 14),
        _BottomTab(icon: Icons.settings, label: 'Settings'),
      ],
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
    final color = selected ? Colors.white : const Color(0xFFC1CAD6);
    return SizedBox(
      width: 150,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF202A36).withValues(alpha: 0.94)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected ? const Color(0xFF3D5068) : Colors.transparent,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
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
                Icon(icon, size: 24, color: color),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
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
        color: const Color(0xFF101721).withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF202A36)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: child,
    );
  }
}

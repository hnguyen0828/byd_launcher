import 'dart:async';

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

enum _VehicleView { status, doors, windows, sunroof, rear }

class LauncherHomePage extends StatefulWidget {
  const LauncherHomePage({super.key, this.enable3dModel = true});

  final bool enable3dModel;

  @override
  State<LauncherHomePage> createState() => _LauncherHomePageState();
}

class _LauncherHomePageState extends State<LauncherHomePage> {
  _VehicleView _view = _VehicleView.status;
  bool _doorsOpen = true;
  bool _sunroofOpen = true;

  String get _cameraOrbit {
    return switch (_view) {
      _VehicleView.doors => '-35deg 68deg 96%',
      _VehicleView.windows => '22deg 72deg 100%',
      _VehicleView.sunroof => '0deg 46deg 112%',
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
                          doorsOpen: _doorsOpen,
                          sunroofOpen: _sunroofOpen,
                          onViewChanged: (view) => setState(() => _view = view),
                          onDoorsToggle: () {
                            setState(() {
                              _doorsOpen = !_doorsOpen;
                              _view = _VehicleView.doors;
                            });
                          },
                          onSunroofToggle: () {
                            setState(() {
                              _sunroofOpen = !_sunroofOpen;
                              _view = _VehicleView.sunroof;
                            });
                          },
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
            const _SpeedCluster(),
            const SizedBox(height: 22),
            const Expanded(child: _TpmsCluster()),
            const SizedBox(height: 18),
            const _MediaWidget(),
            const SizedBox(height: 14),
            const _EnergyStrip(),
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
            color: const Color(0xFFC5CCD8),
            fontWeight: FontWeight.w500,
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
          color: active ? const Color(0xFF45A3FF) : const Color(0xFF6C7480),
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
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: 320,
        height: 280,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Positioned(
              top: 26,
              left: 0,
              child: _PressureBlock(value: '2.6 bar', temp: '28 C'),
            ),
            const Positioned(
              top: 26,
              right: 0,
              child: _PressureBlock(value: '2.6 bar', temp: '28 C'),
            ),
            const Positioned(
              bottom: 34,
              left: 0,
              child: _PressureBlock(value: '2.6 bar', temp: '27 C'),
            ),
            const Positioned(
              bottom: 34,
              right: 0,
              child: _PressureBlock(value: '2.6 bar', temp: '27 C'),
            ),
            SizedBox(
              width: 132,
              height: 238,
              child: Image.asset(
                'assets/images/sealion6_tpms_top_view.png',
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PressureBlock extends StatelessWidget {
  const _PressureBlock({required this.value, required this.temp});

  final String value;
  final String temp;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            temp,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFFC5CCD8),
              fontWeight: FontWeight.w600,
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
    return _DarkPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
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
                        color: const Color(0xFFB9C1CC),
                        fontWeight: FontWeight.w600,
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
      ),
    );
  }
}

class _EnergyStrip extends StatelessWidget {
  const _EnergyStrip();

  @override
  Widget build(BuildContext context) {
    return _DarkPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: const Row(
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
            Icon(icon, color: const Color(0xFFD9E0EA), size: 19),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: const Color(0xFFB9C1CC),
                  fontWeight: FontWeight.w700,
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
    required this.doorsOpen,
    required this.sunroofOpen,
    required this.onViewChanged,
    required this.onDoorsToggle,
    required this.onSunroofToggle,
  });

  final bool enable3dModel;
  final String cameraOrbit;
  final _VehicleView view;
  final bool doorsOpen;
  final bool sunroofOpen;
  final ValueChanged<_VehicleView> onViewChanged;
  final VoidCallback onDoorsToggle;
  final VoidCallback onSunroofToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(34, 34, 46, 30),
      child: Stack(
        children: [
          const Positioned(
            top: 0,
            right: 0,
            child: SizedBox(width: 290, child: _TopRightStatus()),
          ),
          Positioned.fill(
            left: 0,
            top: 0,
            right: 0,
            bottom: 34,
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
              doorsOpen: doorsOpen,
              sunroofOpen: sunroofOpen,
              onDoorsToggle: onDoorsToggle,
              onSunroofToggle: onSunroofToggle,
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

class _TopRightStatus extends StatelessWidget {
  const _TopRightStatus();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '10:30 AM',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: const Color(0xFFE6EBF2),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 18),
        const Icon(Icons.wb_sunny_outlined, color: Color(0xFFE6EBF2), size: 21),
        const SizedBox(width: 7),
        Text(
          '28 C',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: const Color(0xFFE6EBF2),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _FloatingVehicleControls extends StatelessWidget {
  const _FloatingVehicleControls({
    required this.view,
    required this.doorsOpen,
    required this.sunroofOpen,
    required this.onDoorsToggle,
    required this.onSunroofToggle,
    required this.onRear,
  });

  final _VehicleView view;
  final bool doorsOpen;
  final bool sunroofOpen;
  final VoidCallback onDoorsToggle;
  final VoidCallback onSunroofToggle;
  final VoidCallback onRear;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _FloatingControlButton(
          icon: Icons.door_front_door_outlined,
          title: 'Doors',
          value: doorsOpen ? '2 Open' : 'Closed',
          selected: view == _VehicleView.doors,
          onTap: onDoorsToggle,
        ),
        _FloatingControlButton(
          icon: Icons.wb_sunny_outlined,
          title: 'Sunroof',
          value: sunroofOpen ? 'Open' : 'Closed',
          selected: view == _VehicleView.sunroof,
          onTap: onSunroofToggle,
        ),
        _FloatingControlButton(
          icon: Icons.lock_outline,
          title: 'Lock All',
          value: 'Ready',
          onTap: onDoorsToggle,
        ),
        _FloatingControlButton(
          icon: Icons.airport_shuttle_outlined,
          title: 'Trunk',
          value: 'Closed',
          selected: view == _VehicleView.rear,
          onTap: onRear,
        ),
        _FloatingControlButton(
          icon: Icons.no_crash_outlined,
          title: 'Window Lock',
          value: 'On',
          onTap: () {},
        ),
        _FloatingControlButton(
          icon: Icons.flip_to_front_outlined,
          title: 'Fold Mirrors',
          value: 'Auto',
          onTap: () {},
        ),
      ],
    );
  }
}

class _FloatingControlButton extends StatelessWidget {
  const _FloatingControlButton({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 126,
      height: 52,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: _DarkPanel(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          selected: selected,
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF45A3FF),
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
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

class _VehicleReveal extends StatefulWidget {
  const _VehicleReveal({required this.child});

  final Widget child;

  @override
  State<_VehicleReveal> createState() => _VehicleRevealState();
}

class _VehicleRevealState extends State<_VehicleReveal> {
  bool _showPreview = true;
  Timer? _previewTimer;

  @override
  void initState() {
    super.initState();
    _previewTimer = Timer(const Duration(milliseconds: 1150), () {
      if (mounted) {
        setState(() => _showPreview = false);
      }
    });
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedOpacity(
          opacity: _showPreview ? 0 : 1,
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: _showPreview ? 1 : 0,
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            child: const _VehicleLoadingPreview(),
          ),
        ),
      ],
    );
  }
}

class _VehicleLoadingPreview extends StatelessWidget {
  const _VehicleLoadingPreview();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.92, end: 1.0),
        duration: const Duration(milliseconds: 1150),
        curve: Curves.easeOutCubic,
        builder: (context, scale, child) {
          return Transform.scale(scale: scale, child: child);
        },
        child: Image.asset(
          'assets/images/sealion6_tpms_top_view.png',
          fit: BoxFit.contain,
          width: 600,
          color: Colors.white.withValues(alpha: 0.20),
          colorBlendMode: BlendMode.srcATop,
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
        src: 'assets/models/2024_byd_seal_u_dm-i.glb',
        alt: '2024 BYD Seal U DM-i 3D model',
        poster: 'assets/images/sealion6_tpms_top_view.png',
        loading: Loading.eager,
        reveal: Reveal.auto,
        backgroundColor: Colors.transparent,
        cameraControls: true,
        autoRotate: false,
        disableZoom: true,
        interactionPrompt: InteractionPrompt.none,
        cameraOrbit: cameraOrbit,
        minCameraOrbit: 'auto 42deg 66%',
        maxCameraOrbit: 'auto 86deg 132%',
        fieldOfView: '18deg',
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
    final color = selected ? Colors.white : const Color(0xFF8E98A6);
    return SizedBox(
      width: 128,
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
    this.selected = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xFF151D28).withValues(alpha: 0.92)
            : const Color(0xFF101721).withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? const Color(0xFF33465C) : const Color(0xFF202A36),
        ),
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

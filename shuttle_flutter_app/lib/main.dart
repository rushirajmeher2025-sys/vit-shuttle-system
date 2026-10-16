import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;

// Supabase live configuration
const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://yaypinidsnhmcoccvqco.supabase.co');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlheXBpbmlkc25obWNvY2N2cWNvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE5NTU1OTMsImV4cCI6MjEwNzUzMTU5M30.PDzKPv4lTEISGBPq6pacG9aueBtUoRV-sqk_JZN_vpU');

// Cloud WebSocket URL (configurable at build time via --dart-define=WS_URL=wss://...)
const String customWsUrl = String.fromEnvironment('WS_URL', defaultValue: '');

String getWsUrl(String params) {
  if (customWsUrl.isNotEmpty) {
    final separator = customWsUrl.contains('?') ? '&' : '?';
    return '$customWsUrl$separator$params';
  }
  if (kIsWeb) {
    final host = Uri.base.host.isNotEmpty && Uri.base.host != 'localhost' ? Uri.base.host : '10.172.147.61';
    if (Uri.base.scheme == 'https' || host.contains('vercel.app')) {
      return 'wss://vit-shuttle-backend.onrender.com?$params';
    }
    return 'ws://$host:8080?$params';
  }
  return 'ws://10.172.147.61:8080?$params';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const MyApp());
}

final supabase = Supabase.instance.client;

enum UserRole { student, faculty, driver }

// ─── Design Tokens ───────────────────────────────────────────────────────────
const kBg        = Color(0xFF07090F);
const kSurface   = Color(0xFF0F1420);
const kSurface2  = Color(0xFF161D2E);
const kBorder    = Color(0xFF1E2A40);
const kBlue      = Color(0xFF3B82F6);
const kBlueDim   = Color(0xFF1D4ED8);
const kGreen     = Color(0xFF10B981);
const kGreenDim  = Color(0xFF065F46);
const kPink      = Color(0xFFEC4899);
const kAmber     = Color(0xFFF59E0B);
const kRed       = Color(0xFFEF4444);
const kText      = Color(0xFFF1F5F9);
const kTextMuted = Color(0xFF64748B);
const kTextDim   = Color(0xFF334155);

// ─── Data Model ──────────────────────────────────────────────────────────────
class ShuttleData {
  final String shuttleId;
  final String name;
  final String shuttleType;
  final double fare;
  final LatLng location;
  final double speed;
  final double heading;
  final List<dynamic> stopETAs;
  final String crowding;
  final DateTime lastUpdated;

  ShuttleData({
    required this.shuttleId,
    required this.name,
    required this.shuttleType,
    required this.fare,
    required this.location,
    required this.speed,
    required this.heading,
    required this.stopETAs,
    this.crowding = 'Low',
    required this.lastUpdated,
  });

  bool get isFaculty => shuttleType == 'faculty' || shuttleId.contains('faculty');

  ShuttleData copyWith({
    String? name, String? shuttleType, double? fare, LatLng? location,
    double? speed, double? heading, List<dynamic>? stopETAs, String? crowding, DateTime? lastUpdated,
  }) {
    return ShuttleData(
      shuttleId: shuttleId, name: name ?? this.name, shuttleType: shuttleType ?? this.shuttleType,
      fare: fare ?? this.fare, location: location ?? this.location, speed: speed ?? this.speed,
      heading: heading ?? this.heading, stopETAs: stopETAs ?? this.stopETAs,
      crowding: crowding ?? this.crowding, lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

// ─── App Root ─────────────────────────────────────────────────────────────────
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VIT Shuttle',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: ColorScheme.dark(
          primary: kBlue,
          surface: kSurface,
          background: kBg,
        ),
        fontFamily: 'Roboto',
        splashFactory: InkRipple.splashFactory,
      ),
      home: const Scaffold(
        backgroundColor: kBg,
        body: RoleSelectionScreen(),
      ),
    );
  }
}

// ─── Shared Widgets ──────────────────────────────────────────────────────────

/// A tappable pill / button with a quick scale animation on press.
class SnapButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  final BorderRadius? borderRadius;
  final EdgeInsets? padding;
  final Border? border;
  final List<BoxShadow>? boxShadow;

  const SnapButton({
    super.key,
    required this.child,
    this.onTap,
    this.color,
    this.borderRadius,
    this.padding,
    this.border,
    this.boxShadow,
  });

  @override
  State<SnapButton> createState() => _SnapButtonState();
}

class _SnapButtonState extends State<SnapButton> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 90));
    _scale = Tween(begin: 1.0, end: 0.94).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) { _ctrl.reverse(); widget.onTap?.call(); },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: widget.borderRadius ?? BorderRadius.circular(14),
            border: widget.border,
            boxShadow: widget.boxShadow,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Glass surface container
Widget glassBox({
  required Widget child,
  EdgeInsets? padding,
  BorderRadius? borderRadius,
  Color? color,
  Border? border,
  List<BoxShadow>? boxShadow,
}) {
  return Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? kSurface,
      borderRadius: borderRadius ?? BorderRadius.circular(18),
      border: border ?? Border.all(color: kBorder, width: 1),
      boxShadow: boxShadow,
    ),
    child: child,
  );
}

// ============================================================================
// 1. ROLE SELECTION SCREEN
// ============================================================================
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  void _selectRole(BuildContext context, UserRole role) {
    final session = supabase.auth.currentSession;
    Widget dest;
    if (session != null) {
      if (role == UserRole.driver) {
        dest = const DriverModeScreen();
      } else {
        dest = PassengerMapScreen(
          userRole: role,
          userEmail: session.user.email ?? (role == UserRole.faculty ? 'faculty@vit.ac.in' : 'student@vitstudent.ac.in'),
        );
      }
    } else {
      dest = AuthScreen(role: role);
    }
    Navigator.push(context, _slide(dest));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: size.height - 80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header
              Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [kBlue, kBlueDim], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: [BoxShadow(color: kBlue.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 6))],
                    ),
                    child: const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('VIT Shuttle', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kText)),
                      Text('Vellore Campus Transit', style: TextStyle(fontSize: 11, color: kTextMuted, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const Spacer(),
                  _LiveDot(),
                ],
              ),

              const SizedBox(height: 32),

              // ── Fleet Status Row
              Row(
                children: [
                  _StatusChip(label: 'General', sublabel: '₹20', color: kBlue),
                  const SizedBox(width: 8),
                  _StatusChip(label: 'Faculty', sublabel: 'FREE', color: kGreen),
                  const SizedBox(width: 8),
                  _StatusChip(label: '3', sublabel: 'Active', color: kAmber),
                ],
              ),

              const SizedBox(height: 28),

              const Text('Choose Portal', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kText, letterSpacing: -0.3)),
              const SizedBox(height: 4),
              const Text('Your role determines access & fare', style: TextStyle(fontSize: 13, color: kTextMuted)),
              const SizedBox(height: 20),

              // ── Role Cards
              _RoleCard(
                icon: Icons.school_rounded,
                title: 'Student',
                subtitle: 'Ride campus buses, QR boarding pass',
                fare: '₹20 / trip',
                fareColor: kBlue,
                accentColor: kBlue,
                badge: 'General Bus #101 & #102',
                onTap: () => _selectRole(context, UserRole.student),
              ),
              const SizedBox(height: 12),
              _RoleCard(
                icon: Icons.badge_rounded,
                title: 'Faculty',
                subtitle: 'Exclusive shuttle, VIP transit pass',
                fare: '100% FREE',
                fareColor: kGreen,
                accentColor: kGreen,
                badge: 'Faculty Shuttle #201',
                onTap: () => _selectRole(context, UserRole.faculty),
              ),
              const SizedBox(height: 12),
              _RoleCard(
                icon: Icons.drive_eta_rounded,
                title: 'Driver',
                subtitle: 'Broadcast GPS, operate shift console',
                fare: 'Fleet Staff',
                fareColor: kAmber,
                accentColor: kAmber,
                badge: 'Driver Console',
                onTap: () => _selectRole(context, UserRole.driver),
              ),

              const SizedBox(height: 28),

              // ── Footer note
              Center(
                child: Text(
                  'VIT Vellore • Campus Fleet Online',
                  style: TextStyle(fontSize: 11, color: kTextMuted.withOpacity(0.6), letterSpacing: 0.3),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Color.lerp(kGreen.withOpacity(0.12), kGreen.withOpacity(0.24), _ctrl.value),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kGreen.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: kGreen, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            const Text('LIVE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: kGreen, letterSpacing: 0.8)),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final String sublabel;
  final Color color;
  const _StatusChip({required this.label, required this.sublabel, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 1),
            Text(sublabel, style: const TextStyle(fontSize: 10, color: kTextMuted, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String fare;
  final Color fareColor;
  final Color accentColor;
  final String badge;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon, required this.title, required this.subtitle,
    required this.fare, required this.fareColor, required this.accentColor,
    required this.badge, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SnapButton(
      onTap: onTap,
      color: kSurface,
      padding: const EdgeInsets.all(16),
      border: Border.all(color: kBorder),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accentColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kText)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: accentColor.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                      child: Text(badge, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: accentColor)),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: kTextMuted)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(fare, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: fareColor)),
              const SizedBox(height: 2),
              Icon(Icons.chevron_right_rounded, color: kTextMuted, size: 18),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 2. AUTHENTICATION SCREEN
// ============================================================================
class AuthScreen extends StatefulWidget {
  final UserRole role;
  const AuthScreen({super.key, required this.role});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLoading    = false;
  bool _isLogin      = true;
  bool _obscure      = true;

  bool get isStudent => widget.role == UserRole.student;
  bool get isFaculty => widget.role == UserRole.faculty;
  bool get isDriver  => widget.role == UserRole.driver;

  Color get roleColor => isStudent ? kBlue : (isFaculty ? kGreen : kAmber);
  IconData get roleIcon => isStudent ? Icons.school_rounded : (isFaculty ? Icons.badge_rounded : Icons.drive_eta_rounded);
  String get roleName => isStudent ? 'Student' : (isFaculty ? 'Faculty' : 'Driver');
  String get emailDomain => isStudent ? '@vitstudent.ac.in' : '@vit.ac.in';

  @override
  void dispose() { _emailCtrl.dispose(); _passwordCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final email    = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _snack('Please fill in all fields', isError: true); return;
    }
    if (isStudent && !email.endsWith('@vitstudent.ac.in')) {
      _snack('Student email must end with @vitstudent.ac.in', isError: true); return;
    }
    if (isFaculty && (!email.endsWith('@vit.ac.in') || email.endsWith('@vitstudent.ac.in'))) {
      _snack('Faculty email must end with @vit.ac.in', isError: true); return;
    }

    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        await supabase.auth.signInWithPassword(email: email, password: password);
      } else {
        await supabase.auth.signUp(email: email, password: password);
        _snack('Account created! Signing in...', isError: false);
      }
      if (mounted) _navigateAfterAuth(email);
    } on AuthException catch (e) {
      _snack(e.message, isError: true);
    } catch (_) {
      _snack('Unexpected error. Please try again.', isError: true);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _navigateAfterAuth(String email) {
    final dest = isDriver
        ? const DriverModeScreen()
        : PassengerMapScreen(userRole: widget.role, userEmail: email);
    Navigator.pushReplacement(context, _slide(dest));
  }

  Future<void> _completeGoogleLogin(String email) async {
    Navigator.pop(context);
    setState(() => _isLoading = true);
    try {
      await supabase.auth.signUp(email: email, password: 'VIT_SSO_SECURE_PASS_2026', data: {'role': roleName.toLowerCase(), 'provider': 'google'});
    } catch (_) {
      try { await supabase.auth.signInWithPassword(email: email, password: 'VIT_SSO_SECURE_PASS_2026'); } catch (_) {}
    }
    if (mounted) { setState(() => _isLoading = false); _navigateAfterAuth(email); }
  }

  void _showGooglePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final accounts = isStudent
            ? [('Rushi Raj Meher', 'rushi.meher2023@vitstudent.ac.in', '🎓 Verified • 21BCE1042', kBlue, 'R'),
               ('Arjun Kumar',     'arjun.k2024@vitstudent.ac.in',     '🎓 Verified • 22BCE2410', const Color(0xFF6366F1), 'A')]
            : (isFaculty
                ? [('Dr. C. Raman',      'c.raman@vit.ac.in',      '⭐ Faculty • VIT-FAC-4091', kGreen, 'C'),
                   ('Prof. Ananya Iyer', 'ananya.iyer@vit.ac.in',  '⭐ Faculty • VIT-FAC-1102', const Color(0xFF0D9488), 'A')]
                : [('Rajesh Driver',  'driver.raj@vit.ac.in',    '🚖 Driver • Bus #101', kAmber, 'R'),
                   ('Murugan Driver', 'driver.murugan@vit.ac.in', '🚖 Driver • Bus #102', const Color(0xFFEA580C), 'M')]);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                const Text('Sign in with Google', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kText)),
                const SizedBox(height: 3),
                Text(
                  isStudent ? 'Choose @vitstudent.ac.in account' : (isFaculty ? 'Choose @vit.ac.in account' : 'Choose authorized driver account'),
                  style: const TextStyle(fontSize: 12, color: kTextMuted),
                ),
                const SizedBox(height: 16),
                ...accounts.map((acc) => _GoogleTile(
                  name: acc.$1, email: acc.$2, badge: acc.$3,
                  color: acc.$4, letter: acc.$5,
                  onTap: () => _completeGoogleLogin(acc.$2),
                )),
                _GoogleTile(
                  name: 'Use another account',
                  email: isStudent ? 'name@vitstudent.ac.in' : (isFaculty ? 'faculty@vit.ac.in' : 'driver@vit.ac.in'),
                  badge: 'Enter email manually',
                  color: kTextMuted, letter: '+',
                  onTap: () {
                    Navigator.pop(ctx);
                    _emailCtrl.text = isStudent ? 'student@vitstudent.ac.in' : (isFaculty ? 'faculty@vit.ac.in' : 'driver@vit.ac.in');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _snack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: kText, fontWeight: FontWeight.w600)),
      backgroundColor: isError ? kRed.withOpacity(0.85) : kGreen.withOpacity(0.85),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(12),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: kText),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: roleColor.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(roleIcon, size: 13, color: roleColor),
                        const SizedBox(width: 5),
                        Text(roleName.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: roleColor, letterSpacing: 0.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),

                    // ── Hero
                    Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        color: roleColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: roleColor.withOpacity(0.3)),
                      ),
                      child: Icon(roleIcon, color: roleColor, size: 30),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '$roleName Portal',
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: kText, letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isStudent ? 'Access campus shuttles with @vitstudent.ac.in'
                          : (isFaculty ? 'Free faculty shuttle with @vit.ac.in' : 'Authorized VIT drivers only'),
                      style: const TextStyle(fontSize: 13, color: kTextMuted),
                    ),
                    const SizedBox(height: 24),

                    // ── Tab Toggle
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(color: kSurface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
                      child: Row(
                        children: [
                          _AuthTab(label: 'Sign In', active: _isLogin, color: roleColor, onTap: () => setState(() => _isLogin = true)),
                          _AuthTab(label: 'Register', active: !_isLogin, color: roleColor, onTap: () => setState(() => _isLogin = false)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Google SSO Button
                    SnapButton(
                      onTap: _showGooglePicker,
                      color: kSurface2,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                      border: Border.all(color: kBorder),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 24, height: 24,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.08)),
                            child: const Icon(Icons.account_circle_outlined, color: Colors.white, size: 16),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${_isLogin ? 'Sign in' : 'Sign up'} with Google ($emailDomain)',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Divider
                    Row(children: [
                      const Expanded(child: Divider(color: kBorder)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('OR WITH EMAIL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kTextMuted.withOpacity(0.6), letterSpacing: 0.5)),
                      ),
                      const Expanded(child: Divider(color: kBorder)),
                    ]),
                    const SizedBox(height: 16),

                    // ── Email Field
                    _InputLabel(label: isStudent ? 'VIT Student Email' : (isFaculty ? 'VIT Faculty Email' : 'Driver Email')),
                    const SizedBox(height: 6),
                    _InputField(
                      controller: _emailCtrl,
                      hint: isStudent ? 'name@vitstudent.ac.in' : (isFaculty ? 'faculty@vit.ac.in' : 'driver@vit.ac.in'),
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      accentColor: roleColor,
                    ),
                    const SizedBox(height: 14),

                    // ── Password Field
                    const _InputLabel(label: 'Password'),
                    const SizedBox(height: 6),
                    _InputField(
                      controller: _passwordCtrl,
                      hint: '••••••••',
                      icon: Icons.lock_outline_rounded,
                      obscureText: _obscure,
                      accentColor: roleColor,
                      suffix: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: kTextMuted),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Submit Button
                    SizedBox(
                      width: double.infinity,
                      child: SnapButton(
                        onTap: _isLoading ? null : _submit,
                        color: roleColor,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: roleColor.withOpacity(0.3), blurRadius: 18, offset: const Offset(0, 6))],
                        child: Center(
                          child: _isLoading
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                              : Text(
                                  _isLogin ? 'Sign in to $roleName Portal' : 'Create $roleName Account',
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Center(
                      child: Text(
                        isStudent ? '₹20 flat fare on General Campus Shuttles'
                            : (isFaculty ? '100% FREE on Faculty Exclusive Shuttle'
                                : 'VIT Vellore authorized drivers only'),
                        style: const TextStyle(fontSize: 11, color: kTextMuted),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthTab extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  const _AuthTab({required this.label, required this.active, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? color.withOpacity(0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: active ? Border.all(color: color.withOpacity(0.4)) : null,
          ),
          child: Center(
            child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: active ? color : kTextMuted)),
          ),
        ),
      ),
    );
  }
}

class _InputLabel extends StatelessWidget {
  final String label;
  const _InputLabel({required this.label});
  @override
  Widget build(BuildContext context) => Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kTextMuted, letterSpacing: 0.3));
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType keyboardType;
  final Color accentColor;
  final Widget? suffix;

  const _InputField({
    required this.controller, required this.hint, required this.icon,
    this.obscureText = false, this.keyboardType = TextInputType.text,
    required this.accentColor, this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(color: kText, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: kTextMuted, fontSize: 13),
        prefixIcon: Icon(icon, color: kTextMuted, size: 18),
        suffixIcon: suffix,
        filled: true,
        fillColor: kSurface2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: accentColor, width: 1.5)),
      ),
    );
  }
}

class _GoogleTile extends StatelessWidget {
  final String name, email, badge, letter;
  final Color color;
  final VoidCallback onTap;
  const _GoogleTile({required this.name, required this.email, required this.badge, required this.letter, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SnapButton(
      onTap: onTap,
      color: kSurface2,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      border: Border.all(color: kBorder),
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18, backgroundColor: color.withOpacity(0.2),
            child: Text(letter, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kText)),
                Text(email, style: const TextStyle(fontSize: 10, color: kTextMuted)),
                Text(badge, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_ios_rounded, size: 12, color: kTextMuted),
        ],
      ),
    );
  }
}

// ============================================================================
// 3. PASSENGER MAP SCREEN
// ============================================================================
class PassengerMapScreen extends StatefulWidget {
  final UserRole userRole;
  final String userEmail;
  const PassengerMapScreen({super.key, required this.userRole, required this.userEmail});

  @override
  State<PassengerMapScreen> createState() => _PassengerMapScreenState();
}

class _PassengerMapScreenState extends State<PassengerMapScreen> with TickerProviderStateMixin {
  late WebSocketChannel _channel;
  bool _isConnected = false;
  Timer? _reconnectTimer;

  final Map<String, ShuttleData> _activeShuttles = {
    'vit_general_bus_101': ShuttleData(
      shuttleId: 'vit_general_bus_101', name: "General Campus Bus #101 (Men's Hostels)",
      shuttleType: 'general', fare: 20.0, location: const LatLng(12.9723, 79.1627),
      speed: 22.0, heading: 45.0, lastUpdated: DateTime.now(),
      stopETAs: [
        {'stopName': 'Vajpayee / Q & R-Block', 'etaMinutes': 1, 'distanceKm': 0.1},
        {'stopName': 'L, M, N, P Block Cluster', 'etaMinutes': 3, 'distanceKm': 0.5},
        {'stopName': 'MH Food Court', 'etaMinutes': 5, 'distanceKm': 0.9},
        {'stopName': 'GD Naidu Block', 'etaMinutes': 7, 'distanceKm': 1.3},
        {'stopName': 'TT / Central Library', 'etaMinutes': 10, 'distanceKm': 1.8},
        {'stopName': 'SJT', 'etaMinutes': 12, 'distanceKm': 2.3},
      ],
    ),
    'vit_general_bus_102': ShuttleData(
      shuttleId: 'vit_general_bus_102', name: "General Campus Bus #102 (Women's Hostel)",
      shuttleType: 'general', fare: 20.0, location: const LatLng(12.9675, 79.1595),
      speed: 21.0, heading: 90.0, lastUpdated: DateTime.now(),
      stopETAs: [
        {'stopName': "Ladies' Hostel (LH) Gate", 'etaMinutes': 1, 'distanceKm': 0.1},
        {'stopName': 'LH G Block', 'etaMinutes': 3, 'distanceKm': 0.4},
        {'stopName': 'Periyar EVR Library', 'etaMinutes': 6, 'distanceKm': 1.0},
        {'stopName': 'SMV / MB Block', 'etaMinutes': 8, 'distanceKm': 1.4},
        {'stopName': 'SJT', 'etaMinutes': 11, 'distanceKm': 2.0},
      ],
    ),
    'vit_faculty_shuttle_201': ShuttleData(
      shuttleId: 'vit_faculty_shuttle_201', name: 'Faculty Exclusive Shuttle #201',
      shuttleType: 'faculty', fare: 0.0, location: const LatLng(12.9682, 79.1542),
      speed: 19.5, heading: 180.0, lastUpdated: DateTime.now(),
      stopETAs: [
        {'stopName': 'Main Gate 1', 'etaMinutes': 1, 'distanceKm': 0.1},
        {'stopName': 'Main Gate 2', 'etaMinutes': 3, 'distanceKm': 0.5},
        {'stopName': 'M.G.R. Admin Block', 'etaMinutes': 5, 'distanceKm': 0.9},
        {'stopName': 'Faculty Quarters', 'etaMinutes': 8, 'distanceKm': 1.4},
        {'stopName': 'TT (Tech Tower)', 'etaMinutes': 10, 'distanceKm': 1.9},
        {'stopName': 'SJT', 'etaMinutes': 12, 'distanceKm': 2.4},
      ],
    ),
  };

  String _selectedShuttleId = 'vit_general_bus_101';
  bool _isDrawerExpanded = false;
  LatLng? _userLocation;
  String? _nearestStopName;
  double? _nearestStopDistanceMeters;
  int? _nearestStopWalkMinutes;
  bool _isLocatingUser = false;
  bool _isDirectionsMode = false;
  List<LatLng> _walkingRoutePoints = [];
  List<Map<String, dynamic>> _walkingSteps = [];
  int _currentStepIndex = 0;
  bool _isItineraryExpanded = false;
  StreamSubscription<Position>? _walkingPositionSub;
  List<Map<String, dynamic>> _allRoutes = [];
  String _selectedRouteId = 'all';
  final MapController _mapController = MapController();
  double _trackpadStartZoom = 16.2;

  // Animation controller for bottom drawer expansion
  late AnimationController _drawerAnim;
  late Animation<double> _drawerCurve;

  final Map<String, LatLng> _campusStops = {
    'Vajpayee / Q & R-Block': const LatLng(12.9723, 79.1627),
    'L, M, N, P Block': const LatLng(12.9712, 79.1612),
    'MH Food Court': const LatLng(12.9701, 79.1601),
    'GD Naidu Block': const LatLng(12.9692, 79.1588),
    'TT / Central Library': const LatLng(12.9691, 79.1560),
    "Ladies' Hostel (LH) Gate": const LatLng(12.9675, 79.1595),
    'LH G Block': const LatLng(12.9668, 79.1602),
    'Periyar EVR Library': const LatLng(12.9688, 79.1561),
    'SMV / MB Block': const LatLng(12.9698, 79.1552),
    'SJT (Silver Jubilee Tower)': const LatLng(12.9708, 79.1558),
    'Main Gate 1': const LatLng(12.9682, 79.1542),
    'Main Gate 2': const LatLng(12.9665, 79.1551),
    'M.G.R. Admin Block': const LatLng(12.9688, 79.1550),
    'Faculty Quarters': const LatLng(12.9658, 79.1578),
    'TT (Tech Tower)': const LatLng(12.9695, 79.1563),
    'Gandhi / Netaji Block': const LatLng(12.9715, 79.1548),
  };

  bool get isFacultyUser => widget.userRole == UserRole.faculty;

  @override
  void initState() {
    super.initState();
    _drawerAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
    _drawerCurve = CurvedAnimation(parent: _drawerAnim, curve: Curves.easeOutCubic);
    if (isFacultyUser) _selectedShuttleId = 'vit_faculty_shuttle_201';
    _connectWebSocket();
    _fetchRoutesFromSupabase();
    _requestLocationAndFindNearestStop(manual: false);
  }

  @override
  void dispose() {
    _walkingPositionSub?.cancel();
    _reconnectTimer?.cancel();
    _channel.sink.close();
    _drawerAnim.dispose();
    super.dispose();
  }

  void _toggleDrawer() {
    setState(() => _isDrawerExpanded = !_isDrawerExpanded);
    if (_isDrawerExpanded) {
      _drawerAnim.forward();
    } else {
      _drawerAnim.reverse();
    }
  }

  Future<void> _requestLocationAndFindNearestStop({bool manual = false}) async {
    setState(() => _isLocatingUser = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _isLocatingUser = false);
        return;
      }
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 8));
      final userPos = LatLng(position.latitude, position.longitude);
      String closestStop = _campusStops.keys.first;
      double minDistance = double.infinity;
      for (var entry in _campusStops.entries) {
        final dist = Geolocator.distanceBetween(userPos.latitude, userPos.longitude, entry.value.latitude, entry.value.longitude);
        if (dist < minDistance) { minDistance = dist; closestStop = entry.key; }
      }
      final walkMinutes = (minDistance / 75).ceil().clamp(1, 120);
      if (mounted) {
        setState(() {
          _userLocation = userPos;
          _nearestStopName = closestStop;
          _nearestStopDistanceMeters = minDistance;
          _nearestStopWalkMinutes = walkMinutes;
          _isLocatingUser = false;
        });
        if (manual || minDistance <= 3000) {
          final stopPos = _campusStops[closestStop]!;
          _mapController.move(LatLng((userPos.latitude + stopPos.latitude) / 2, (userPos.longitude + stopPos.longitude) / 2), 16.5);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLocatingUser = false);
    }
  }

  void _startDirectionsMode() {
    if (_userLocation == null || _nearestStopName == null || !_campusStops.containsKey(_nearestStopName)) {
      _requestLocationAndFindNearestStop(manual: true); return;
    }
    final stopPos = _campusStops[_nearestStopName!]!;
    final directDist = Geolocator.distanceBetween(_userLocation!.latitude, _userLocation!.longitude, stopPos.latitude, stopPos.longitude);
    final midLat = (_userLocation!.latitude + stopPos.latitude) / 2;
    final midLng = (_userLocation!.longitude + stopPos.longitude) / 2;
    final steps = <Map<String, dynamic>>[
      {'icon': Icons.arrow_upward_rounded, 'instruction': 'Head along campus pedestrian way', 'sub': 'In ${(directDist * 0.4).round()}m', 'distance': (directDist * 0.4).round()},
      {'icon': Icons.turn_right_rounded, 'instruction': 'Turn towards $_nearestStopName', 'sub': 'In ${(directDist * 0.6).round()}m', 'distance': (directDist * 0.6).round()},
      {'icon': Icons.sports_score_rounded, 'instruction': 'Arrive at $_nearestStopName', 'sub': 'Destination reached', 'distance': 0},
    ];
    setState(() {
      _isDirectionsMode = true;
      _walkingRoutePoints = [_userLocation!, LatLng(midLat, midLng), stopPos];
      _walkingSteps = steps;
      _currentStepIndex = 0;
      _isItineraryExpanded = false;
    });
    _mapController.move(LatLng(midLat, midLng), 17.0);
    _walkingPositionSub?.cancel();
    _walkingPositionSub = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 3)).listen((pos) {
      if (!mounted || !_isDirectionsMode) return;
      final newPos = LatLng(pos.latitude, pos.longitude);
      final remaining = Geolocator.distanceBetween(newPos.latitude, newPos.longitude, stopPos.latitude, stopPos.longitude);
      setState(() {
        _userLocation = newPos;
        _nearestStopDistanceMeters = remaining;
        _nearestStopWalkMinutes = (remaining / 75).ceil().clamp(1, 120);
        _walkingRoutePoints = [newPos, LatLng(midLat, midLng), stopPos];
        if (remaining <= 15 && _walkingSteps.isNotEmpty) _currentStepIndex = _walkingSteps.length - 1;
      });
    });
  }

  void _exitDirectionsMode() {
    _walkingPositionSub?.cancel();
    _walkingPositionSub = null;
    setState(() { _isDirectionsMode = false; _walkingRoutePoints = []; _walkingSteps = []; _isItineraryExpanded = false; });
  }

  Future<void> _fetchRoutesFromSupabase() async {
    try {
      final response = await supabase.from('routes').select('*');
      setState(() => _allRoutes = List<Map<String, dynamic>>.from(response));
    } catch (e) { debugPrint('Failed to fetch routes: $e'); }
  }

  void _connectWebSocket() {
    _reconnectTimer?.cancel();
    try {
      final roleParam = isFacultyUser ? 'role=faculty' : 'role=student';
      _channel = WebSocketChannel.connect(Uri.parse(getWsUrl(roleParam)));
      setState(() => _isConnected = true);
      _channel.stream.listen(
        (message) {
          final data = jsonDecode(message);
          if (data['type'] == 'ALL_SHUTTLES' && data['shuttles'] is List) {
            setState(() {
              for (var s in data['shuttles']) {
                final sId = s['shuttleId'] ?? 'vit_general_bus_101';
                _activeShuttles[sId] = ShuttleData(
                  shuttleId: sId, name: s['name'] ?? sId,
                  shuttleType: s['shuttleType'] ?? (sId.contains('faculty') ? 'faculty' : 'general'),
                  fare: s['fare'] != null ? (s['fare'] as num).toDouble() : (sId.contains('faculty') ? 0.0 : 20.0),
                  location: LatLng((s['lat'] as num).toDouble(), (s['lng'] as num).toDouble()),
                  speed: s['speed'] != null ? (s['speed'] as num).toDouble() : 18.0,
                  heading: s['heading'] != null ? (s['heading'] as num).toDouble() : 0.0,
                  stopETAs: s['stopETAs'] ?? [], crowding: s['crowding'] ?? 'Low', lastUpdated: DateTime.now(),
                );
              }
            });
          } else if (data['type'] == 'SHUTTLE_MOVED' || data['type'] == 'LOCATION_UPDATE') {
            final sId = data['shuttleId'] ?? 'vit_general_bus_101';
            setState(() {
              final existing = _activeShuttles[sId];
              final sType = data['shuttleType'] ?? existing?.shuttleType ?? (sId.contains('faculty') ? 'faculty' : 'general');
              _activeShuttles[sId] = ShuttleData(
                shuttleId: sId, name: data['name'] ?? existing?.name ?? sId, shuttleType: sType,
                fare: data['fare'] != null ? (data['fare'] as num).toDouble() : (sType == 'faculty' ? 0.0 : 20.0),
                location: LatLng((data['lat'] as num).toDouble(), (data['lng'] as num).toDouble()),
                speed: data['speed'] != null ? (data['speed'] as num).toDouble() : 18.0,
                heading: data['heading'] != null ? (data['heading'] as num).toDouble() : 0.0,
                stopETAs: data['stopETAs'] ?? existing?.stopETAs ?? [],
                crowding: existing?.crowding ?? 'Low', lastUpdated: DateTime.now(),
              );
            });
          } else if (data['type'] == 'REPORT_CROWDING') {
            final sId = data['shuttleId'];
            if (sId != null && _activeShuttles.containsKey(sId)) {
              setState(() => _activeShuttles[sId] = _activeShuttles[sId]!.copyWith(crowding: data['level']));
            }
          }
        },
        onDone: () { if (mounted) { setState(() => _isConnected = false); _scheduleReconnect(); } },
        onError: (_) { if (mounted) { setState(() => _isConnected = false); _scheduleReconnect(); } },
      );
    } catch (_) { if (mounted) { setState(() => _isConnected = false); _scheduleReconnect(); } }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () { if (mounted) _connectWebSocket(); });
  }

  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return kBlue;
    try { return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16)); } catch (_) { return kBlue; }
  }

  void _reportCrowding(String level) {
    if (_isConnected) {
      _channel.sink.add(jsonEncode({
        'type': 'REPORT_CROWDING', 'shuttleId': _selectedShuttleId,
        'level': level, 'timestamp': DateTime.now().toIso8601String(),
      }));
      _snack('Crowd reported: $level', isError: false);
    }
  }

  void _snack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: kText, fontWeight: FontWeight.w600)),
      backgroundColor: isError ? kRed.withOpacity(0.85) : kGreen.withOpacity(0.85),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(12),
    ));
  }

  Future<void> _logout() async {
    _reconnectTimer?.cancel();
    await supabase.auth.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(context, _slide(const RoleSelectionScreen()), (r) => false);
    }
  }

  void _showTicketModal(ShuttleData shuttle) {
    final isFac = shuttle.isFaculty;
    showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 36, height: 4, decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Text(isFac ? 'Faculty VIP Transit Pass' : 'VIT Digital Boarding Pass',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kText)),
              const SizedBox(height: 18),

              // Ticket Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isFac ? [const Color(0xFF065F46), const Color(0xFF047857)] : [kBlueDim, kBlue],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: isFac ? Border.all(color: kAmber, width: 1.5) : null,
                  boxShadow: [BoxShadow(color: (isFac ? kGreen : kBlue).withOpacity(0.35), blurRadius: 20, offset: const Offset(0, 8))],
                ),
                child: Column(
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(isFac ? 'VIT FACULTY PRIVILEGE' : 'GENERAL CAMPUS BUS',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: isFac ? kAmber : Colors.white70, letterSpacing: 0.6)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: isFac ? kAmber : kGreen, borderRadius: BorderRadius.circular(10)),
                        child: Text(isFac ? 'FREE (₹0)' : 'PAID ₹20', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: isFac ? const Color(0xFF065F46) : Colors.white)),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    Text(shuttle.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white), textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    Text(widget.userEmail, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                    const SizedBox(height: 18),
                    Container(
                      width: 130, height: 130, padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(isFac ? Icons.stars_rounded : Icons.qr_code_2_rounded, size: 80, color: isFac ? kGreen : const Color(0xFF0F172A)),
                          const SizedBox(height: 4),
                          Text(isFac ? 'VERIFIED FACULTY' : 'TKT-${math.Random().nextInt(90000) + 10000}',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: isFac ? kGreen : const Color(0xFF64748B))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.check_circle_rounded, size: 14, color: isFac ? kAmber : const Color(0xFF4ADE80)),
                      const SizedBox(width: 6),
                      Text(
                        isFac ? 'Complimentary Faculty Transit Privilege' : 'Valid for current trip • ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: SnapButton(
                  onTap: () => Navigator.pop(context),
                  color: isFac ? kGreen : kBlue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  borderRadius: BorderRadius.circular(14),
                  child: const Center(child: Text('Ready to Board', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedShuttle = _activeShuttles[_selectedShuttleId] ?? _activeShuttles.values.first;
    final visibleShuttles = _activeShuttles.values.toList();
    final roleColor = isFacultyUser ? kGreen : kBlue;

    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        children: [

          // ── 1. MAP
          Listener(
            onPointerPanZoomStart: (e) { _trackpadStartZoom = _mapController.camera.zoom; },
            onPointerPanZoomUpdate: (e) {
              if (e.scale != 1.0 && e.scale > 0) {
                final newZoom = (_trackpadStartZoom + math.log(e.scale) / math.ln2).clamp(3.0, 20.0);
                _mapController.move(_mapController.camera.center, newZoom);
              }
            },
            onPointerSignal: (sig) {
              if (sig is PointerScrollEvent && sig.scrollDelta.dy != 0) {
                _mapController.move(_mapController.camera.center, (_mapController.camera.zoom - sig.scrollDelta.dy * 0.003).clamp(3.0, 20.0));
              }
            },
            child: FlutterMap(
              mapController: _mapController,
              options: const MapOptions(
                initialCenter: LatLng(12.9715, 79.1595), initialZoom: 16.2, minZoom: 3.0, maxZoom: 20.0,
                interactionOptions: InteractionOptions(
                  flags: InteractiveFlag.drag | InteractiveFlag.flingAnimation | InteractiveFlag.pinchMove |
                      InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom | InteractiveFlag.doubleTapDragZoom |
                      InteractiveFlag.scrollWheelZoom,
                  pinchZoomThreshold: 0.05, enableMultiFingerGestureRace: true,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                  subdomains: const ['mt0', 'mt1', 'mt2', 'mt3'],
                  userAgentPackageName: 'com.example.shuttle_flutter_app', maxZoom: 20,
                ),
                PolylineLayer(polylines: [
                  ..._allRoutes.where((r) => _selectedRouteId == 'all' || r['id'].toString() == _selectedRouteId).map((r) {
                    List<LatLng> pts = [];
                    final raw = r['points'];
                    if (raw is List) { for (var p in raw) { if (p is Map) pts.add(LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble())); } }
                    return Polyline(points: pts, strokeWidth: 6.5, color: Colors.white.withOpacity(0.8));
                  }),
                  ..._allRoutes.where((r) => _selectedRouteId == 'all' || r['id'].toString() == _selectedRouteId).map((r) {
                    List<LatLng> pts = [];
                    final raw = r['points'];
                    if (raw is List) { for (var p in raw) { if (p is Map) pts.add(LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble())); } }
                    return Polyline(points: pts, strokeWidth: 4.0, color: _parseColor(r['color']));
                  }),
                  if (_isDirectionsMode && _walkingRoutePoints.isNotEmpty) ...[
                    Polyline(points: _walkingRoutePoints, strokeWidth: 8.0, color: const Color(0x6606B6D4)),
                    Polyline(points: _walkingRoutePoints, strokeWidth: 4.0, color: const Color(0xFF38BDF8)),
                  ] else if (_userLocation != null && _nearestStopName != null && _campusStops.containsKey(_nearestStopName))
                    Polyline(points: [_userLocation!, _campusStops[_nearestStopName!]!], strokeWidth: 3.0, color: const Color(0x8038BDF8)),
                ]),
                MarkerLayer(markers: [
                  if (_isDirectionsMode && _nearestStopName != null && _campusStops.containsKey(_nearestStopName))
                    Marker(
                      point: _campusStops[_nearestStopName!]!, width: 110, height: 32,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF38BDF8))),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Text('🏁', style: TextStyle(fontSize: 11)),
                          const SizedBox(width: 4),
                          Expanded(child: Text(_nearestStopName!, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: kText), overflow: TextOverflow.ellipsis)),
                        ]),
                      ),
                    ),
                  if (_userLocation != null)
                    Marker(
                      point: _userLocation!, width: 44, height: 44,
                      child: Stack(alignment: Alignment.center, children: [
                        Container(width: 38, height: 38, decoration: BoxDecoration(shape: BoxShape.circle, color: kBlue.withOpacity(0.2))),
                        Container(width: 14, height: 14, decoration: BoxDecoration(shape: BoxShape.circle, color: kBlue, border: Border.all(color: Colors.white, width: 2.5), boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6)])),
                      ]),
                    ),
                  ..._campusStops.entries.map((entry) {
                    final n = entry.key;
                    final isMh = n.contains('Block') || n.contains('MH') || n.contains('GD') || n.contains('Vajpayee');
                    final isLh = n.contains('Ladies') || n.contains('LH');
                    final isFac = n.contains('Faculty') || n.contains('Gate') || n.contains('Quarters') || n.contains('Admin');
                    final pinColor = isMh ? kBlue : (isLh ? kPink : (isFac ? kGreen : const Color(0xFF8B5CF6)));
                    return Marker(
                      point: entry.value, width: 100, height: 48,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(6), border: Border.all(color: pinColor, width: 1.1), boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2))]),
                          child: Text(n, style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: kText), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(height: 1),
                        Container(width: 10, height: 10, decoration: BoxDecoration(color: pinColor, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2), boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3)])),
                      ]),
                    );
                  }),
                  ...visibleShuttles.map((shuttle) {
                    final isF = shuttle.isFaculty;
                    final isW = shuttle.shuttleId.contains('102');
                    final isSel = shuttle.shuttleId == _selectedShuttleId;
                    final tc = isF ? kGreen : (isW ? kPink : kBlue);
                    return Marker(
                      point: shuttle.location, width: 80, height: 80,
                      child: GestureDetector(
                        onTap: () { setState(() => _selectedShuttleId = shuttle.shuttleId); _mapController.move(shuttle.location, 16.5); },
                        child: Stack(alignment: Alignment.center, children: [
                          Container(width: isSel ? 72 : 58, height: isSel ? 72 : 58, decoration: BoxDecoration(shape: BoxShape.circle, color: tc.withOpacity(isSel ? 0.25 : 0.12))),
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: isF ? [kGreen, kGreenDim] : (isW ? [kPink, const Color(0xFFBE185D)] : [kBlue, kBlueDim]), begin: Alignment.topLeft, end: Alignment.bottomRight),
                              shape: BoxShape.circle,
                              border: Border.all(color: isF ? kAmber : Colors.white, width: isSel ? 3.0 : 2.0),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 3))],
                            ),
                            child: Icon(isF ? Icons.stars_rounded : Icons.directions_bus_rounded, color: Colors.white, size: 18),
                          ),
                          Positioned(
                            top: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(5), border: Border.all(color: isF ? kAmber : Colors.white70, width: 0.8)),
                              child: Text(isF ? 'FAC•FREE' : (isW ? 'LH•₹20' : 'MH•₹20'), style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.w800, color: isF ? kAmber : Colors.white)),
                            ),
                          ),
                        ]),
                      ),
                    );
                  }),
                ]),
              ],
            ),
          ),

          // ── 2. TOP BAR
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 14, right: 14,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Main nav bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: kSurface.withOpacity(0.96), borderRadius: BorderRadius.circular(18), border: Border.all(color: kBorder), boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, 4))]),
                  child: Row(
                    children: [
                      // Role Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(color: roleColor.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(isFacultyUser ? Icons.badge_rounded : Icons.school_rounded, color: roleColor, size: 12),
                          const SizedBox(width: 4),
                          Text(isFacultyUser ? 'Faculty' : 'Student', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: roleColor)),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      // Route selector
                      Expanded(
                        child: Container(
                          height: 30,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(color: kSurface2, borderRadius: BorderRadius.circular(8)),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedRouteId, isDense: true, isExpanded: true,
                              dropdownColor: kSurface2, icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kTextMuted, size: 15),
                              style: const TextStyle(color: kText, fontWeight: FontWeight.w600, fontSize: 11),
                              onChanged: (val) { if (val != null) setState(() => _selectedRouteId = val); },
                              items: [
                                const DropdownMenuItem(value: 'all', child: Text('All Routes', style: TextStyle(color: kText))),
                                ..._allRoutes.map((r) => DropdownMenuItem(value: r['id'].toString(), child: Text(r['route_name'] ?? 'Route', style: const TextStyle(color: kText)))),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Status dot
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: _isConnected ? kGreen.withOpacity(0.12) : kRed.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _isConnected ? kGreen.withOpacity(0.35) : kRed.withOpacity(0.35)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(width: 5, height: 5, decoration: BoxDecoration(color: _isConnected ? kGreen : kRed, shape: BoxShape.circle)),
                          const SizedBox(width: 4),
                          Text(_isConnected ? 'LIVE' : 'OFF', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: _isConnected ? kGreen : kRed)),
                        ]),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: _logout,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(Icons.logout_rounded, size: 15, color: kRed.withOpacity(0.8)),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 6),

                // Nearest stop / directions row
                if (_isDirectionsMode)
                  _DirectionsHud(
                    steps: _walkingSteps, currentIndex: _currentStepIndex,
                    distanceM: (_nearestStopDistanceMeters ?? 0).round(),
                    walkMins: _nearestStopWalkMinutes ?? 0,
                    stopName: _nearestStopName ?? '',
                    isItineraryExpanded: _isItineraryExpanded,
                    onToggleItinerary: () => setState(() => _isItineraryExpanded = !_isItineraryExpanded),
                    onExit: _exitDirectionsMode,
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: kSurface.withOpacity(0.96), borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _nearestStopName != null ? const Color(0xFF38BDF8).withOpacity(0.3) : kBorder),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 3))],
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.place_rounded, size: 14, color: _nearestStopName != null ? const Color(0xFF38BDF8) : kTextMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _requestLocationAndFindNearestStop(manual: true),
                            child: Text(
                              _isLocatingUser ? 'Locating nearest stop...'
                                  : (_nearestStopName != null ? 'Nearest: $_nearestStopName · ${(_nearestStopDistanceMeters!).toStringAsFixed(0)}m (~$_nearestStopWalkMinutes min)'
                                      : 'Tap to enable location'),
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _nearestStopName != null ? kText : kTextMuted),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        if (_nearestStopName != null) ...[
                          const SizedBox(width: 6),
                          SnapButton(
                            onTap: _startDirectionsMode,
                            color: kBlue.withOpacity(0.2), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            border: Border.all(color: kBlue.withOpacity(0.4)), borderRadius: BorderRadius.circular(7),
                            child: const Text('Walk', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kBlue)),
                          ),
                        ],
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => _requestLocationAndFindNearestStop(manual: true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                            decoration: BoxDecoration(color: kSurface2, borderRadius: BorderRadius.circular(7), border: Border.all(color: kBorder)),
                            child: Text(_nearestStopName != null ? 'Focus' : 'GPS', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kTextMuted)),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // ── 3. RIGHT SIDE CONTROLS
          Positioned(
            right: 14,
            bottom: 170,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MapControl(
                  child: Column(children: [
                    _ZoomBtn(icon: Icons.add, onTap: () { _mapController.move(_mapController.camera.center, (_mapController.camera.zoom + 1).clamp(3.0, 20.0)); }),
                    Container(height: 1, color: kBorder),
                    _ZoomBtn(icon: Icons.remove, onTap: () { _mapController.move(_mapController.camera.center, (_mapController.camera.zoom - 1).clamp(3.0, 20.0)); }),
                  ]),
                ),
                const SizedBox(height: 8),
                _MapControl(child: _ZoomBtn(icon: Icons.gps_fixed_rounded, iconColor: const Color(0xFF38BDF8), onTap: () => _requestLocationAndFindNearestStop(manual: true))),
                const SizedBox(height: 8),
                _MapControl(child: _ZoomBtn(icon: Icons.my_location_rounded, iconColor: roleColor, onTap: () { _mapController.move(selectedShuttle.location, 16.5); })),
              ],
            ),
          ),

          // ── 4. BOTTOM TRAY
          Positioned(
            left: 14, right: 14, bottom: 14,
            child: Container(
              decoration: BoxDecoration(
                color: kSurface.withOpacity(0.97),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: kBorder),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 8))],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [

                    // ── Shuttle Switcher Row
                    Row(
                      children: [
                        _ShuttlePill(label: 'MH 101', emoji: '🚌', fare: '₹20', color: kBlue, selected: _selectedShuttleId == 'vit_general_bus_101',
                            onTap: () { setState(() => _selectedShuttleId = 'vit_general_bus_101'); final s = _activeShuttles['vit_general_bus_101']; if (s != null) _mapController.move(s.location, 16.5); }),
                        const SizedBox(width: 6),
                        _ShuttlePill(label: 'LH 102', emoji: '🌸', fare: '₹20', color: kPink, selected: _selectedShuttleId == 'vit_general_bus_102',
                            onTap: () { setState(() => _selectedShuttleId = 'vit_general_bus_102'); final s = _activeShuttles['vit_general_bus_102']; if (s != null) _mapController.move(s.location, 16.5); }),
                        const SizedBox(width: 6),
                        _ShuttlePill(label: 'Faculty', emoji: '⭐', fare: 'FREE', color: kGreen, selected: _selectedShuttleId == 'vit_faculty_shuttle_201',
                            onTap: () { setState(() => _selectedShuttleId = 'vit_faculty_shuttle_201'); final s = _activeShuttles['vit_faculty_shuttle_201']; if (s != null) _mapController.move(s.location, 16.5); }),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // ── Telemetry + Action Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (selectedShuttle.stopETAs.isNotEmpty)
                                Row(children: [
                                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: kRed, shape: BoxShape.circle)),
                                  const SizedBox(width: 5),
                                  Flexible(child: Text('Next: ${selectedShuttle.stopETAs[0]['stopName']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kText), overflow: TextOverflow.ellipsis)),
                                  const SizedBox(width: 4),
                                  Text('${selectedShuttle.stopETAs[0]['etaMinutes']}m', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: selectedShuttle.isFaculty ? kGreen : kBlue)),
                                ]),
                              const SizedBox(height: 2),
                              Text('${selectedShuttle.speed.toStringAsFixed(0)} km/h · Live GPS', style: const TextStyle(fontSize: 10, color: kTextMuted)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Pass / Ticket button
                        SnapButton(
                          onTap: () {
                            if (selectedShuttle.isFaculty && !isFacultyUser) {
                              _snack('Faculty shuttle is restricted to @vit.ac.in faculty members', isError: true);
                            } else {
                              _showTicketModal(selectedShuttle);
                            }
                          },
                          color: selectedShuttle.isFaculty ? kGreen : kBlue,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          borderRadius: BorderRadius.circular(11),
                          boxShadow: [BoxShadow(color: (selectedShuttle.isFaculty ? kGreen : kBlue).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
                          child: Text(
                            selectedShuttle.isFaculty ? '⭐ VIP Pass' : '🎫 Pass ₹20',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    // ── Expand toggle
                    GestureDetector(
                      onTap: _toggleDrawer,
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(_isDrawerExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 16, color: kTextMuted),
                        const SizedBox(width: 4),
                        Text(_isDrawerExpanded ? 'Hide details' : 'Stops & crowd info', style: const TextStyle(fontSize: 10, color: kTextMuted, fontWeight: FontWeight.w600)),
                      ]),
                    ),

                    // ── Expandable: Stops + Crowding
                    SizeTransition(
                      sizeFactor: _drawerCurve,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 10),
                          if (selectedShuttle.stopETAs.isNotEmpty)
                            SizedBox(
                              height: 50,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: selectedShuttle.stopETAs.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 6),
                                itemBuilder: (ctx, i) {
                                  final stop = selectedShuttle.stopETAs[i];
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(color: kSurface2, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                                      Text(stop['stopName'] ?? 'Stop', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kText)),
                                      Text('${stop['etaMinutes']} min', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: selectedShuttle.isFaculty ? kGreen : kBlue)),
                                    ]),
                                  );
                                },
                              ),
                            ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text('Crowd: ', style: TextStyle(fontSize: 10, color: kTextMuted, fontWeight: FontWeight.w600)),
                              const SizedBox(width: 6),
                              _CrowdChip(label: '🟢 Low', color: kGreen, onTap: () => _reportCrowding('Low'), selected: selectedShuttle.crowding == 'Low'),
                              const SizedBox(width: 5),
                              _CrowdChip(label: '🟡 Med', color: kAmber, onTap: () => _reportCrowding('Moderate'), selected: selectedShuttle.crowding == 'Moderate'),
                              const SizedBox(width: 5),
                              _CrowdChip(label: '🔴 Full', color: kRed, onTap: () => _reportCrowding('Full'), selected: selectedShuttle.crowding == 'Full'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShuttlePill extends StatelessWidget {
  final String label, emoji, fare;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _ShuttlePill({required this.label, required this.emoji, required this.fare, required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SnapButton(
        onTap: onTap,
        color: selected ? color.withOpacity(0.18) : kSurface2,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        border: Border.all(color: selected ? color : kBorder, width: selected ? 1.5 : 1),
        borderRadius: BorderRadius.circular(10),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: selected ? color : kTextMuted)),
          ]),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(color: selected ? color : kTextDim, borderRadius: BorderRadius.circular(5)),
            child: Text(fare, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Colors.white)),
          ),
        ]),
      ),
    );
  }
}

class _CrowdChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _CrowdChip({required this.label, required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SnapButton(
        onTap: onTap,
        color: selected ? color.withOpacity(0.18) : kSurface2,
        padding: const EdgeInsets.symmetric(vertical: 5),
        border: Border.all(color: selected ? color.withOpacity(0.6) : kBorder, width: selected ? 1.5 : 1),
        borderRadius: BorderRadius.circular(7),
        child: Center(child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: selected ? color : kTextMuted))),
      ),
    );
  }
}

class _MapControl extends StatelessWidget {
  final Widget child;
  const _MapControl({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: kSurface.withOpacity(0.95), borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2))]),
      child: child,
    );
  }
}

class _ZoomBtn extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  const _ZoomBtn({required this.icon, this.iconColor = kTextMuted, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(padding: const EdgeInsets.all(9), child: Icon(icon, color: iconColor, size: 17)),
    );
  }
}

class _DirectionsHud extends StatelessWidget {
  final List<Map<String, dynamic>> steps;
  final int currentIndex;
  final int distanceM, walkMins;
  final String stopName;
  final bool isItineraryExpanded;
  final VoidCallback onToggleItinerary, onExit;

  const _DirectionsHud({
    required this.steps, required this.currentIndex, required this.distanceM,
    required this.walkMins, required this.stopName, required this.isItineraryExpanded,
    required this.onToggleItinerary, required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    final step = steps.isNotEmpty && currentIndex < steps.length ? steps[currentIndex] : null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kSurface.withOpacity(0.96), borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 14, offset: Offset(0, 4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              const Text('🚶', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Text('Walking to $stopName', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kText)),
            ]),
            SnapButton(
              onTap: onExit, color: kRed.withOpacity(0.12),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              border: Border.all(color: kRed.withOpacity(0.3)), borderRadius: BorderRadius.circular(7),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.close_rounded, size: 12, color: kRed),
                SizedBox(width: 3),
                Text('Exit', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kRed)),
              ]),
            ),
          ]),
          if (step != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: kSurface2, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
              child: Row(children: [
                Container(width: 30, height: 30, decoration: const BoxDecoration(gradient: LinearGradient(colors: [kBlueDim, kBlue]), shape: BoxShape.circle),
                    child: Icon(step['icon'] as IconData? ?? Icons.navigation_rounded, color: Colors.white, size: 16)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(step['instruction'].toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kText), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(step['sub'].toString(), style: const TextStyle(fontSize: 9, color: kTextMuted)),
                ])),
              ]),
            ),
          ],
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              const Icon(Icons.timer_outlined, size: 12, color: Color(0xFF38BDF8)),
              const SizedBox(width: 3),
              Text('$walkMins min', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF38BDF8))),
              const SizedBox(width: 8),
              Text('·', style: TextStyle(color: kTextMuted)),
              const SizedBox(width: 8),
              const Icon(Icons.straighten_rounded, size: 12, color: Color(0xFF38BDF8)),
              const SizedBox(width: 3),
              Text(distanceM < 1000 ? '${distanceM}m' : '${(distanceM / 1000).toStringAsFixed(1)}km', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF38BDF8))),
            ]),
            GestureDetector(
              onTap: onToggleItinerary,
              child: Row(children: [
                Text('Steps (${steps.length})', style: const TextStyle(fontSize: 10, color: kTextMuted, fontWeight: FontWeight.w600)),
                Icon(isItineraryExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 14, color: kTextMuted),
              ]),
            ),
          ]),
          if (isItineraryExpanded) ...[
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 100),
              decoration: BoxDecoration(color: kSurface2, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder)),
              child: ListView.separated(
                shrinkWrap: true, padding: const EdgeInsets.all(6),
                itemCount: steps.length,
                separatorBuilder: (_, __) => const Divider(color: kBorder, height: 6),
                itemBuilder: (ctx, i) {
                  final s = steps[i]; final isCur = i == currentIndex;
                  return Row(children: [
                    Icon(s['icon'] as IconData? ?? Icons.arrow_upward_rounded, size: 12, color: isCur ? const Color(0xFF38BDF8) : kTextMuted),
                    const SizedBox(width: 6),
                    Expanded(child: Text(s['instruction'].toString(), style: TextStyle(fontSize: 10, fontWeight: isCur ? FontWeight.w700 : FontWeight.normal, color: isCur ? const Color(0xFF38BDF8) : kTextMuted), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if ((s['distance'] as num) > 0) Text('${s['distance']}m', style: const TextStyle(fontSize: 9, color: kTextMuted)),
                  ]);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// 4. DRIVER MODE SCREEN
// ============================================================================
class DriverModeScreen extends StatefulWidget {
  const DriverModeScreen({super.key});
  @override
  State<DriverModeScreen> createState() => _DriverModeScreenState();
}

class _DriverModeScreenState extends State<DriverModeScreen> {
  late WebSocketChannel _channel;
  bool _isTracking = false;
  StreamSubscription<Position>? _positionStream;
  double _currentSpeed = 0.0;
  String _coords = 'Ready to start shift';
  final MapController _mapController = MapController();
  LatLng _driverLocation = const LatLng(12.9715, 79.1595);
  String _selectedShuttleType = 'general';

  String get currentShuttleId   => _selectedShuttleType == 'faculty' ? 'vit_faculty_shuttle_201' : 'vit_general_bus_101';
  String get currentVehicleName => _selectedShuttleType == 'faculty' ? 'Faculty Exclusive Shuttle #201' : 'General Campus Bus #101';
  double get currentFare        => _selectedShuttleType == 'faculty' ? 0.0 : 20.0;
  bool   get isFaculty          => _selectedShuttleType == 'faculty';
  Color  get themeColor         => isFaculty ? kGreen : kBlue;

  @override
  void initState() {
    super.initState();
    _channel = WebSocketChannel.connect(Uri.parse(getWsUrl('role=driver&shuttleId=$currentShuttleId')));
  }

  @override
  void dispose() { _positionStream?.cancel(); _channel.sink.close(); super.dispose(); }

  Future<void> _toggleTracking() async {
    if (_isTracking) {
      _positionStream?.cancel();
      setState(() { _isTracking = false; _currentSpeed = 0.0; _coords = 'Shift ended'; });
    } else {
      final status = await Permission.locationWhenInUse.request();
      if (status.isGranted) {
        setState(() => _isTracking = true);
        _positionStream = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 2)).listen((pos) {
          final speedKmH = (pos.speed * 3.6).clamp(0.0, 80.0);
          setState(() {
            _currentSpeed = speedKmH;
            _coords = '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
            _driverLocation = LatLng(pos.latitude, pos.longitude);
          });
          _mapController.move(_driverLocation, 16.5);
          _channel.sink.add(jsonEncode({
            'type': 'LOCATION_UPDATE', 'shuttleId': currentShuttleId, 'name': currentVehicleName,
            'shuttleType': _selectedShuttleType, 'fare': currentFare,
            'lat': pos.latitude, 'lng': pos.longitude, 'speed': speedKmH, 'heading': pos.heading,
            'timestamp': DateTime.now().toIso8601String(),
          }));
        });
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permission required')));
      }
    }
  }

  Future<void> _logout() async {
    _positionStream?.cancel();
    _channel.sink.close();
    await supabase.auth.signOut();
    if (mounted) Navigator.pushAndRemoveUntil(context, _slide(const RoleSelectionScreen()), (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        children: [
          // MAP
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: _driverLocation, initialZoom: 16.5),
            children: [
              TileLayer(urlTemplate: 'https://{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}', subdomains: const ['mt0', 'mt1', 'mt2', 'mt3'], userAgentPackageName: 'com.example.shuttle_flutter_app', maxZoom: 20),
              MarkerLayer(markers: [
                Marker(
                  point: _driverLocation, width: 52, height: 52,
                  child: Stack(alignment: Alignment.center, children: [
                    Container(width: 52, height: 52, decoration: BoxDecoration(shape: BoxShape.circle, color: themeColor.withOpacity(0.2))),
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: themeColor, border: Border.all(color: Colors.white, width: 2.5), boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 3))]),
                      child: Icon(isFaculty ? Icons.stars_rounded : Icons.directions_bus_rounded, color: Colors.white, size: 18),
                    ),
                  ]),
                ),
              ]),
            ],
          ),

          // TOP BAR
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 14, right: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: kSurface.withOpacity(0.97), borderRadius: BorderRadius.circular(18), border: Border.all(color: kBorder), boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 14, offset: Offset(0, 4))]),
              child: Row(children: [
                GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: kText)),
                const SizedBox(width: 12),
                Container(width: 28, height: 28, decoration: BoxDecoration(color: themeColor.withOpacity(0.15), borderRadius: BorderRadius.circular(8)), child: Icon(Icons.drive_eta_rounded, color: themeColor, size: 15)),
                const SizedBox(width: 8),
                const Text('Driver Console', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: kText)),
                const Spacer(),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _isTracking ? kGreen.withOpacity(0.12) : kRed.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _isTracking ? kGreen.withOpacity(0.35) : kRed.withOpacity(0.25)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: _isTracking ? kGreen : kRed)),
                    const SizedBox(width: 5),
                    Text(_isTracking ? 'BROADCASTING' : 'OFFLINE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: _isTracking ? kGreen : kRed, letterSpacing: 0.4)),
                  ]),
                ),
                const SizedBox(width: 8),
                GestureDetector(onTap: _logout, child: Icon(Icons.logout_rounded, size: 16, color: kRed.withOpacity(0.8))),
              ]),
            ),
          ),

          // BOTTOM PANEL
          Positioned(
            left: 14, right: 14, bottom: 14,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: kSurface.withOpacity(0.97), borderRadius: BorderRadius.circular(22), border: Border.all(color: kBorder), boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 8))]),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Vehicle Selector
                  Row(children: [
                    Expanded(
                      child: SnapButton(
                        onTap: _isTracking ? null : () => setState(() => _selectedShuttleType = 'general'),
                        color: !isFaculty ? kBlue.withOpacity(0.18) : kSurface2,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        border: Border.all(color: !isFaculty ? kBlue : kBorder, width: !isFaculty ? 1.5 : 1),
                        borderRadius: BorderRadius.circular(12),
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          const Text('🚌 General Bus', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kBlue)),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: kBlue.withOpacity(0.2), borderRadius: BorderRadius.circular(6), border: Border.all(color: kBlue.withOpacity(0.4))),
                              child: const Text('₹20', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: kBlue))),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SnapButton(
                        onTap: _isTracking ? null : () => setState(() => _selectedShuttleType = 'faculty'),
                        color: isFaculty ? kGreen.withOpacity(0.18) : kSurface2,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        border: Border.all(color: isFaculty ? kGreen : kBorder, width: isFaculty ? 1.5 : 1),
                        borderRadius: BorderRadius.circular(12),
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          const Text('⭐ Faculty', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kGreen)),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: kGreen.withOpacity(0.2), borderRadius: BorderRadius.circular(6), border: Border.all(color: kGreen.withOpacity(0.4))),
                              child: const Text('FREE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: kGreen))),
                        ]),
                      ),
                    ),
                  ]),

                  const SizedBox(height: 14),

                  // Speedometer + Coords + Start/End
                  Row(children: [
                    // Speedometer
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(color: themeColor.withOpacity(0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: themeColor.withOpacity(0.4))),
                      child: Column(
                        children: [
                          Text(_currentSpeed.toStringAsFixed(0), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: themeColor, height: 1.0)),
                          Text('KM/H', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: themeColor.withOpacity(0.7), letterSpacing: 0.5)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_isTracking ? 'Broadcasting GPS' : currentVehicleName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kText)),
                          const SizedBox(height: 2),
                          Text(_coords, style: const TextStyle(fontSize: 10, color: kTextMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Start/End Shift Button
                    SnapButton(
                      onTap: _toggleTracking,
                      color: _isTracking ? kRed : themeColor,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: (_isTracking ? kRed : themeColor).withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 5))],
                      child: Text(_isTracking ? 'END' : 'START', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5)),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Navigation Helper ────────────────────────────────────────────────────────
Route _slide(Widget page) {
  return PageRouteBuilder(
    pageBuilder: (_, __, ___) => Scaffold(backgroundColor: kBg, body: page),
    transitionsBuilder: (_, anim, __, child) {
      final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return SlideTransition(
        position: Tween(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(curve),
        child: child,
      );
    },
    transitionDuration: const Duration(milliseconds: 280),
  );
}

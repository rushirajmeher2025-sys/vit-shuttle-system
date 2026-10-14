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

// Automatically resolves PC's local IP (10.172.147.61), local dev host, or production cloud WebSocket
String getWsUrl(String params) {
  if (customWsUrl.isNotEmpty) {
    final separator = customWsUrl.contains('?') ? '&' : '?';
    return '$customWsUrl$separator$params';
  }
  if (kIsWeb) {
    final host = Uri.base.host.isNotEmpty && Uri.base.host != 'localhost' ? Uri.base.host : '10.172.147.61';
    // If hosted on https (like *.vercel.app), use secure wss:// and target cloud backend
    if (Uri.base.scheme == 'https' || host.contains('vercel.app')) {
      return 'wss://vit-shuttle-backend.onrender.com?$params';
    }
    return 'ws://$host:8080?$params';
  }
  return 'ws://10.172.147.61:8080?$params';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  runApp(const MyApp());
}

final supabase = Supabase.instance.client;

enum UserRole { student, faculty, driver }

// Data model for active campus shuttles
class ShuttleData {
  final String shuttleId;
  final String name;
  final String shuttleType; // 'general' | 'faculty'
  final double fare; // 20.0 or 0.0
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
    String? name,
    String? shuttleType,
    double? fare,
    LatLng? location,
    double? speed,
    double? heading,
    List<dynamic>? stopETAs,
    String? crowding,
    DateTime? lastUpdated,
  }) {
    return ShuttleData(
      shuttleId: shuttleId,
      name: name ?? this.name,
      shuttleType: shuttleType ?? this.shuttleType,
      fare: fare ?? this.fare,
      location: location ?? this.location,
      speed: speed ?? this.speed,
      heading: heading ?? this.heading,
      stopETAs: stopETAs ?? this.stopETAs,
      crowding: crowding ?? this.crowding,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VIT Shuttle Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0284C7),
          primary: const Color(0xFF0284C7),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        fontFamily: 'Roboto',
      ),
      home: const MobileShell(child: RoleSelectionScreen()),
    );
  }
}

// ============================================================================
// MOBILE SHELL: Renders a smartphone viewport on desktop, full-screen on mobile
// ============================================================================
class MobileShell extends StatelessWidget {
  final Widget child;

  const MobileShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      body: child,
    );
  }
}

// ============================================================================
// 1. ROLE SELECTION SCREEN (Student vs Faculty vs Driver)
// ============================================================================
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  void _selectRole(BuildContext context, UserRole role) {
    final session = supabase.auth.currentSession;
    if (session != null) {
      // If already authenticated, route directly to the respective portal
      if (role == UserRole.student) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => MobileShell(child: PassengerMapScreen(userRole: UserRole.student, userEmail: session.user.email ?? 'student@vitstudent.ac.in'))),
        );
      } else if (role == UserRole.faculty) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => MobileShell(child: PassengerMapScreen(userRole: UserRole.faculty, userEmail: session.user.email ?? 'faculty@vit.ac.in'))),
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MobileShell(child: DriverModeScreen())),
        );
      }
    } else {
      // If not logged in, proceed to role-tailored authentication
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MobileShell(child: AuthScreen(role: role))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          // App Logo
          Center(
            child: Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0284C7).withOpacity(0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  )
                ],
              ),
              child: const Icon(Icons.directions_bus_rounded, size: 40, color: Colors.white),
            ),
          ),
          const SizedBox(height: 14),
          const Center(
            child: Text(
              'VIT Shuttle Tracker',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            ),
          ),
          const Center(
            child: Text(
              'Campus Fleet: General (₹20) & Faculty (Free)',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: 24),

          const Text(
            'Select Your Portal',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 4),
          const Text(
            'Choose your role to access campus shuttle services',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 16),

          // 1. Student Portal Card
          _buildRoleCard(
            context: context,
            title: 'I am a Student',
            subtitle: 'Ride General Campus Bus (₹20), live GPS tracking, stop ETAs & crowd reporting',
            icon: Icons.school_rounded,
            badge: 'GENERAL BUS • ₹20',
            badgeBg: const Color(0xFF0284C7),
            gradient: const [Color(0xFF0284C7), Color(0xFF0369A1)],
            onTap: () => _selectRole(context, UserRole.student),
          ),
          const SizedBox(height: 14),

          // 2. Faculty Portal Card
          _buildRoleCard(
            context: context,
            title: 'I am a Faculty Member',
            subtitle: 'Exclusive Faculty Shuttle (100% FREE), digital faculty pass & campus routes',
            icon: Icons.badge_rounded,
            badge: 'FACULTY • FREE SHUTTLE',
            badgeBg: const Color(0xFF059669),
            gradient: const [Color(0xFF059669), Color(0xFF047857)],
            onTap: () => _selectRole(context, UserRole.faculty),
          ),
          const SizedBox(height: 14),

          // 3. Driver Portal Card
          _buildRoleCard(
            context: context,
            title: 'I am a Shuttle Driver',
            subtitle: 'Operate General Bus (₹20) or Faculty Shuttle (Free), broadcast GPS & speedometer',
            icon: Icons.drive_eta_rounded,
            badge: 'DRIVER CONSOLE',
            badgeBg: const Color(0xFFD97706),
            gradient: const [Color(0xFFD97706), Color(0xFFB45309)],
            onTap: () => _selectRole(context, UserRole.driver),
          ),

          const SizedBox(height: 24),

          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                const Text('Vellore Campus Fleet Online', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildRoleCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required String badge,
    required Color badgeBg,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: gradient[0].withOpacity(0.35),
              blurRadius: 14,
              offset: const Offset(0, 6),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, size: 26, color: Colors.white),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.88), height: 1.35)),
            const SizedBox(height: 10),
            Row(
              children: [
                Text('Proceed to Portal', style: TextStyle(color: Colors.white.withOpacity(0.95), fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_rounded, size: 15, color: Colors.white),
              ],
            )
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 2. AUTHENTICATION SCREEN (Tailored for Student / Faculty / Driver)
// ============================================================================
class AuthScreen extends StatefulWidget {
  final UserRole role;

  const AuthScreen({super.key, required this.role});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isLogin = true;
  bool _obscurePassword = true;

  bool get isStudent => widget.role == UserRole.student;
  bool get isFaculty => widget.role == UserRole.faculty;
  bool get isDriver => widget.role == UserRole.driver;

  Color get primaryColor {
    if (isStudent) return const Color(0xFF0284C7);
    if (isFaculty) return const Color(0xFF059669);
    return const Color(0xFFD97706);
  }

  String get roleName {
    if (isStudent) return 'Student';
    if (isFaculty) return 'Faculty';
    return 'Driver';
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields'), backgroundColor: Colors.red),
      );
      return;
    }

    // Role-specific email domain validation
    if (isStudent && !email.endsWith('@vitstudent.ac.in')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Student email must end with @vitstudent.ac.in'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (isFaculty && (!email.endsWith('@vit.ac.in') || email.endsWith('@vitstudent.ac.in'))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Faculty email must end with @vit.ac.in (not @vitstudent.ac.in)'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        await supabase.auth.signInWithPassword(email: email, password: password);
      } else {
        await supabase.auth.signUp(email: email, password: password);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registration successful! Logging in...'), backgroundColor: Colors.green),
        );
      }
      
      if (mounted) {
        if (isDriver) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const MobileShell(child: DriverModeScreen())),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => MobileShell(
                child: PassengerMapScreen(userRole: widget.role, userEmail: email),
              ),
            ),
          );
        }
      }
    } on AuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('An unexpected error occurred'), backgroundColor: Colors.red),
      );
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Back Button to change role
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 4),
              Text(
                'Change Portal',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  roleName.toUpperCase(),
                  style: TextStyle(color: primaryColor, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Role Icon & Heading
          Center(
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isStudent
                    ? Icons.school_rounded
                    : (isFaculty ? Icons.badge_rounded : Icons.drive_eta_rounded),
                size: 36,
                color: primaryColor,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              '$roleName Portal',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            ),
          ),
          Center(
            child: Text(
              isStudent
                  ? 'Access General Shuttles (₹20) with @vitstudent.ac.in'
                  : (isFaculty
                      ? 'Access Free Faculty Shuttles with @vit.ac.in'
                      : 'Authorized shuttle driver login'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),

          // Sign In / Register Tab Toggle
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _isLogin = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _isLogin ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: _isLogin
                            ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          'Sign In',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _isLogin ? primaryColor : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _isLogin = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: !_isLogin ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: !_isLogin
                            ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          'Register',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: !_isLogin ? primaryColor : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Email Input
          Text(
            isStudent ? 'VIT Student Email' : (isFaculty ? 'VIT Faculty Email' : 'Driver Email'),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF334155)),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: isStudent
                  ? 'name@vitstudent.ac.in'
                  : (isFaculty ? 'faculty@vit.ac.in' : 'driver@vit.ac.in'),
              hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF64748B), size: 20),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: primaryColor, width: 1.5)),
            ),
          ),
          const SizedBox(height: 14),

          // Password Input
          const Text('Password', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF334155))),
          const SizedBox(height: 6),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              hintText: '••••••••••••',
              hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
              prefixIcon: const Icon(Icons.lock_outline_rounded, color: Color(0xFF64748B), size: 20),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: const Color(0xFF64748B), size: 20),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: primaryColor, width: 1.5)),
            ),
          ),
          const SizedBox(height: 22),

          // Submit Button
          ElevatedButton(
            onPressed: _isLoading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_isLogin ? 'Sign In to $roleName Portal' : 'Create $roleName Account', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 14),

          Center(
            child: Text(
              isStudent
                  ? 'Fare: ₹20 per trip on General Campus Shuttles'
                  : (isFaculty
                      ? 'Fare: 100% FREE on Faculty Exclusive Shuttles'
                      : 'Authorized VIT Vellore drivers only'),
              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 3. PASSENGER MAP SCREEN (Student & Faculty live tracking & ticketing)
// ============================================================================
class PassengerMapScreen extends StatefulWidget {
  final UserRole userRole;
  final String userEmail;

  const PassengerMapScreen({
    super.key,
    required this.userRole,
    required this.userEmail,
  });

  @override
  State<PassengerMapScreen> createState() => _PassengerMapScreenState();
}

class _PassengerMapScreenState extends State<PassengerMapScreen> {
  late WebSocketChannel _channel;
  bool _isConnected = false;
  Timer? _reconnectTimer;

  // Active shuttles tracked in real-time
  final Map<String, ShuttleData> _activeShuttles = {
    'vit_general_bus_101': ShuttleData(
      shuttleId: 'vit_general_bus_101',
      name: "General Campus Bus #101 (Men's Hostels)",
      shuttleType: 'general',
      fare: 20.0,
      location: const LatLng(12.9723, 79.1627),
      speed: 22.0,
      heading: 45.0,
      stopETAs: [
        {'stopName': 'Vajpayee / Q & R-Block Cluster', 'etaMinutes': 1, 'distanceKm': 0.1},
        {'stopName': 'L, M, N, P Block Cluster', 'etaMinutes': 3, 'distanceKm': 0.5},
        {'stopName': 'MH Food Court & All Maart Area', 'etaMinutes': 5, 'distanceKm': 0.9},
        {'stopName': 'GD Naidu Block / A-G Blocks', 'etaMinutes': 7, 'distanceKm': 1.3},
        {'stopName': 'TT / Central Library Junction', 'etaMinutes': 10, 'distanceKm': 1.8},
        {'stopName': 'SJT (Silver Jubilee Tower)', 'etaMinutes': 12, 'distanceKm': 2.3},
      ],
      lastUpdated: DateTime.now(),
    ),
    'vit_general_bus_102': ShuttleData(
      shuttleId: 'vit_general_bus_102',
      name: "General Campus Bus #102 (Women's Hostel)",
      shuttleType: 'general',
      fare: 20.0,
      location: const LatLng(12.9675, 79.1595),
      speed: 21.0,
      heading: 90.0,
      stopETAs: [
        {'stopName': "Main Ladies' Hostel (LH) Gate", 'etaMinutes': 1, 'distanceKm': 0.1},
        {'stopName': 'LH G Block', 'etaMinutes': 3, 'distanceKm': 0.4},
        {'stopName': 'Periyar EVR Central Library', 'etaMinutes': 6, 'distanceKm': 1.0},
        {'stopName': 'SMV / MB Block Portico', 'etaMinutes': 8, 'distanceKm': 1.4},
        {'stopName': 'SJT (Silver Jubilee Tower)', 'etaMinutes': 11, 'distanceKm': 2.0},
      ],
      lastUpdated: DateTime.now(),
    ),
    'vit_faculty_shuttle_201': ShuttleData(
      shuttleId: 'vit_faculty_shuttle_201',
      name: 'Faculty Exclusive Shuttle #201',
      shuttleType: 'faculty',
      fare: 0.0,
      location: const LatLng(12.9682, 79.1542),
      speed: 19.5,
      heading: 180.0,
      stopETAs: [
        {'stopName': 'Main Gate 1 Entrance', 'etaMinutes': 1, 'distanceKm': 0.1},
        {'stopName': 'Main Gate 2 Entrance', 'etaMinutes': 3, 'distanceKm': 0.5},
        {'stopName': 'Dr. M.G.R. Central Admin Block', 'etaMinutes': 5, 'distanceKm': 0.9},
        {'stopName': 'Staff & Faculty Quarters Zone', 'etaMinutes': 8, 'distanceKm': 1.4},
        {'stopName': 'TT (Technology Tower)', 'etaMinutes': 10, 'distanceKm': 1.9},
        {'stopName': 'SJT (Silver Jubilee Tower)', 'etaMinutes': 12, 'distanceKm': 2.4},
        {'stopName': 'Gandhi Block / Netaji Block', 'etaMinutes': 14, 'distanceKm': 2.8},
      ],
      lastUpdated: DateTime.now(),
    ),
  };

  String _selectedShuttleId = 'vit_general_bus_101';
  String _shuttleFilter = 'all'; // 'all', 'general', 'faculty'
  bool _isDrawerExpanded = false;

  // Passenger GPS Location & Nearest Campus Stop
  LatLng? _userLocation;
  String? _nearestStopName;
  double? _nearestStopDistanceMeters;
  int? _nearestStopWalkMinutes;
  bool _isLocatingUser = false;
  
  // Passenger In-App Walking Directions
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

  final Map<String, LatLng> _campusStops = {
    // 1. Men's Hostels Shuttle Stops
    'Vajpayee / Q & R-Block Cluster': const LatLng(12.9723, 79.1627),
    'L, M, N, P Block Cluster': const LatLng(12.9712, 79.1612),
    'MH Food Court & All Maart Area': const LatLng(12.9701, 79.1601),
    'GD Naidu Block / A-G Blocks': const LatLng(12.9692, 79.1588),
    'TT / Central Library Junction': const LatLng(12.9691, 79.1560),

    // 2. Women's Hostel Shuttle Stops
    "Main Ladies' Hostel (LH) Gate": const LatLng(12.9675, 79.1595),
    'LH G Block': const LatLng(12.9668, 79.1602),
    'Periyar EVR Central Library': const LatLng(12.9688, 79.1561),
    'SMV / MB Block Portico': const LatLng(12.9698, 79.1552),

    // 3. Faculty Shuttle Stops & Shared Academic Hubs
    'SJT (Silver Jubilee Tower)': const LatLng(12.9708, 79.1558),
    'Main Gate 1 Entrance': const LatLng(12.9682, 79.1542),
    'Main Gate 2 Entrance': const LatLng(12.9665, 79.1551),
    'Dr. M.G.R. Central Admin Block': const LatLng(12.9688, 79.1550),
    'Staff & Faculty Quarters Zone': const LatLng(12.9658, 79.1578),
    'TT (Technology Tower)': const LatLng(12.9695, 79.1563),
    'Gandhi Block / Netaji Block': const LatLng(12.9715, 79.1548),
  };

  bool get isFacultyUser => widget.userRole == UserRole.faculty;

  @override
  void initState() {
    super.initState();
    // Default to faculty shuttle if faculty logged in, otherwise general bus
    if (isFacultyUser) {
      _selectedShuttleId = 'vit_faculty_shuttle_201';
    }
    _connectWebSocket();
    _fetchRoutesFromSupabase();
    _requestLocationAndFindNearestStop(manual: false);
  }

  Future<void> _requestLocationAndFindNearestStop({bool manual = false}) async {
    setState(() => _isLocatingUser = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _isLocatingUser = false);
          if (manual) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permission is required to find your nearest stop.')),
            );
          }
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );

      final userPos = LatLng(position.latitude, position.longitude);

      String closestStop = _campusStops.keys.first;
      double minDistance = double.infinity;

      for (var entry in _campusStops.entries) {
        final dist = Geolocator.distanceBetween(
          userPos.latitude,
          userPos.longitude,
          entry.value.latitude,
          entry.value.longitude,
        );
        if (dist < minDistance) {
          minDistance = dist;
          closestStop = entry.key;
        }
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
          final midLat = (userPos.latitude + stopPos.latitude) / 2;
          final midLng = (userPos.longitude + stopPos.longitude) / 2;
          _mapController.move(LatLng(midLat, midLng), 16.5);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLocatingUser = false);
      }
    }
  }

  void _startDirectionsMode() {
    if (_userLocation == null || _nearestStopName == null || !_campusStops.containsKey(_nearestStopName)) {
      _requestLocationAndFindNearestStop(manual: true);
      return;
    }

    final stopPos = _campusStops[_nearestStopName!]!;
    final directDist = Geolocator.distanceBetween(
      _userLocation!.latitude,
      _userLocation!.longitude,
      stopPos.latitude,
      stopPos.longitude,
    );

    // Compute campus walkway waypoint
    final midLat = (_userLocation!.latitude + stopPos.latitude) / 2;
    final midLng = (_userLocation!.longitude + stopPos.longitude) / 2;

    final steps = <Map<String, dynamic>>[
      {
        'icon': Icons.arrow_upward_rounded,
        'instruction': 'Head along campus pedestrian way',
        'sub': 'In ${(directDist * 0.4).round()}m',
        'distance': (directDist * 0.4).round(),
      },
      {
        'icon': Icons.turn_right_rounded,
        'instruction': 'Turn towards $_nearestStopName',
        'sub': 'In ${(directDist * 0.6).round()}m',
        'distance': (directDist * 0.6).round(),
      },
      {
        'icon': Icons.sports_score_rounded,
        'instruction': 'Arrive at $_nearestStopName stop',
        'sub': 'Destination at stop marker',
        'distance': 0,
      },
    ];

    setState(() {
      _isDirectionsMode = true;
      _walkingRoutePoints = [_userLocation!, LatLng(midLat, midLng), stopPos];
      _walkingSteps = steps;
      _currentStepIndex = 0;
      _isItineraryExpanded = false;
    });

    // Smoothly focus map on the route
    _mapController.move(LatLng(midLat, midLng), 17.0);

    // Listen to real-time walking movement
    _walkingPositionSub?.cancel();
    _walkingPositionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      ),
    ).listen((position) {
      if (!mounted || !_isDirectionsMode) return;
      final newPos = LatLng(position.latitude, position.longitude);
      final remaining = Geolocator.distanceBetween(
        newPos.latitude,
        newPos.longitude,
        stopPos.latitude,
        stopPos.longitude,
      );

      setState(() {
        _userLocation = newPos;
        _nearestStopDistanceMeters = remaining;
        _nearestStopWalkMinutes = (remaining / 75).ceil().clamp(1, 120);
        _walkingRoutePoints = [newPos, LatLng(midLat, midLng), stopPos];
        if (remaining <= 15 && _walkingSteps.isNotEmpty) {
          _currentStepIndex = _walkingSteps.length - 1;
        }
      });
    });
  }

  void _exitDirectionsMode() {
    _walkingPositionSub?.cancel();
    _walkingPositionSub = null;
    setState(() {
      _isDirectionsMode = false;
      _walkingRoutePoints = [];
      _walkingSteps = [];
      _isItineraryExpanded = false;
    });
  }

  Widget _buildDirectionsHud() {
    final currentStep = _walkingSteps.isNotEmpty && _currentStepIndex < _walkingSteps.length
        ? _walkingSteps[_currentStepIndex]
        : {
            'icon': Icons.arrow_upward_rounded,
            'instruction': 'Head towards $_nearestStopName',
            'sub': 'In 30m',
            'distance': 30,
          };

    final totalM = (_nearestStopDistanceMeters ?? 0).round();
    final totalMins = _nearestStopWalkMinutes ?? 1;

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFA0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x6638BDF8)),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 18, offset: Offset(0, 6)),
          BoxShadow(color: Color(0x3338BDF8), blurRadius: 10),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with destination & exit button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text('🚶', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text(
                    'Walking to $_nearestStopName',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              InkWell(
                onTap: _exitDirectionsMode,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0x33EF4444),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0x66EF4444)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.close_rounded, size: 12, color: Color(0xFFF87171)),
                      SizedBox(width: 3),
                      Text('Exit', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFF87171))),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Primary Current Step Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF0284C7), Color(0xFF38BDF8)]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    currentStep['icon'] as IconData? ?? Icons.navigation_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentStep['instruction'].toString(),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        currentStep['sub'].toString(),
                        style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Meta row: ETA + Distance + Expand toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 13, color: Color(0xFF38BDF8)),
                  const SizedBox(width: 4),
                  Text('$totalMins min', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8))),
                  const SizedBox(width: 8),
                  const Text('•', style: TextStyle(color: Colors.white38)),
                  const SizedBox(width: 8),
                  const Icon(Icons.straighten_rounded, size: 13, color: Color(0xFF38BDF8)),
                  const SizedBox(width: 4),
                  Text(totalM < 1000 ? '$totalM m' : '${(totalM / 1000).toStringAsFixed(1)} km',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8))),
                ],
              ),
              InkWell(
                onTap: () => setState(() => _isItineraryExpanded = !_isItineraryExpanded),
                child: Row(
                  children: [
                    Text(
                      'Steps (${_walkingSteps.length})',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70),
                    ),
                    Icon(
                      _isItineraryExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      color: Colors.white70,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Expandable Itinerary Steps
          if (_isItineraryExpanded) ...[
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(6),
                itemCount: _walkingSteps.length,
                separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 8),
                itemBuilder: (context, index) {
                  final s = _walkingSteps[index];
                  final isCur = index == _currentStepIndex;
                  return Row(
                    children: [
                      Icon(s['icon'] as IconData? ?? Icons.arrow_upward_rounded,
                          size: 14, color: isCur ? const Color(0xFF38BDF8) : Colors.white60),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s['instruction'].toString(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isCur ? FontWeight.bold : FontWeight.normal,
                            color: isCur ? const Color(0xFF38BDF8) : Colors.white70,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if ((s['distance'] as num) > 0)
                        Text('${s['distance']}m', style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8))),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _fetchRoutesFromSupabase() async {
    try {
      final response = await supabase.from('routes').select('*');
      setState(() {
        _allRoutes = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      debugPrint("Failed to fetch routes: $e");
    }
  }

  void _connectWebSocket() {
    _reconnectTimer?.cancel();
    try {
      final roleParam = isFacultyUser ? 'role=faculty' : 'role=student';
      _channel = WebSocketChannel.connect(
        Uri.parse(getWsUrl(roleParam)),
      );
      
      setState(() => _isConnected = true);

      _channel.stream.listen(
        (message) {
          final data = jsonDecode(message);
          if (data['type'] == 'ALL_SHUTTLES' && data['shuttles'] is List) {
            setState(() {
              for (var s in data['shuttles']) {
                final sId = s['shuttleId'] ?? 'vit_general_bus_101';
                _activeShuttles[sId] = ShuttleData(
                  shuttleId: sId,
                  name: s['name'] ?? (sId.contains('faculty') ? 'Faculty Exclusive Shuttle #201' : 'General Campus Bus #101'),
                  shuttleType: s['shuttleType'] ?? (sId.contains('faculty') ? 'faculty' : 'general'),
                  fare: s['fare'] != null ? (s['fare'] as num).toDouble() : (sId.contains('faculty') ? 0.0 : 20.0),
                  location: LatLng((s['lat'] as num).toDouble(), (s['lng'] as num).toDouble()),
                  speed: s['speed'] != null ? (s['speed'] as num).toDouble() : 18.0,
                  heading: s['heading'] != null ? (s['heading'] as num).toDouble() : 0.0,
                  stopETAs: s['stopETAs'] ?? [],
                  crowding: s['crowding'] ?? 'Low',
                  lastUpdated: DateTime.now(),
                );
              }
            });
          } else if (data['type'] == 'SHUTTLE_MOVED' || data['type'] == 'LOCATION_UPDATE') {
            final sId = data['shuttleId'] ?? 'vit_general_bus_101';
            setState(() {
              final existing = _activeShuttles[sId];
              final sType = data['shuttleType'] ?? existing?.shuttleType ?? (sId.contains('faculty') ? 'faculty' : 'general');
              final sFare = data['fare'] != null
                  ? (data['fare'] as num).toDouble()
                  : (sType == 'faculty' ? 0.0 : 20.0);
              final sName = data['name'] ?? existing?.name ?? (sType == 'faculty' ? 'Faculty Exclusive Shuttle #201' : 'General Campus Bus #101');

              _activeShuttles[sId] = ShuttleData(
                shuttleId: sId,
                name: sName,
                shuttleType: sType,
                fare: sFare,
                location: LatLng((data['lat'] as num).toDouble(), (data['lng'] as num).toDouble()),
                speed: data['speed'] != null ? (data['speed'] as num).toDouble() : 18.0,
                heading: data['heading'] != null ? (data['heading'] as num).toDouble() : 0.0,
                stopETAs: data['stopETAs'] ?? existing?.stopETAs ?? [],
                crowding: existing?.crowding ?? 'Low',
                lastUpdated: DateTime.now(),
              );
            });
          } else if (data['type'] == 'REPORT_CROWDING') {
            final sId = data['shuttleId'];
            if (sId != null && _activeShuttles.containsKey(sId)) {
              setState(() {
                _activeShuttles[sId] = _activeShuttles[sId]!.copyWith(crowding: data['level']);
              });
            }
          }
        },
        onDone: () {
          if (mounted) {
            setState(() => _isConnected = false);
            _scheduleReconnect();
          }
        },
        onError: (e) {
          if (mounted) {
            setState(() => _isConnected = false);
            _scheduleReconnect();
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isConnected = false);
        _scheduleReconnect();
      }
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) _connectWebSocket();
    });
  }

  Color _parseColor(String? colorHex) {
    if (colorHex == null || colorHex.isEmpty) return const Color(0xFF0284C7);
    try {
      final hex = colorHex.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (e) {
      return const Color(0xFF0284C7);
    }
  }

  void _reportCrowding(String level) {
    if (_isConnected) {
      _channel.sink.add(jsonEncode({
        'type': 'REPORT_CROWDING',
        'shuttleId': _selectedShuttleId,
        'level': level,
        'timestamp': DateTime.now().toIso8601String(),
      }));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Crowding reported as $level for ${_activeShuttles[_selectedShuttleId]?.name ?? "Shuttle"}'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _logout() async {
    _reconnectTimer?.cancel();
    await supabase.auth.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MobileShell(child: RoleSelectionScreen())),
        (route) => false,
      );
    }
  }

  // Dialog / BottomSheet to show paid ₹20 General Bus ticket
  void _showGeneralBusTicketModal(ShuttleData shuttle) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 48, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: const Color(0xFF0284C7).withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.confirmation_number_rounded, color: Color(0xFF0284C7), size: 24),
                ),
                const SizedBox(width: 10),
                const Text(
                  'VIT Digital Transit Pass',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Realistic Ticket Card with QR Code
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF0284C7).withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 8)),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('GENERAL CAMPUS BUS', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xFF22C55E), borderRadius: BorderRadius.circular(12)),
                        child: const Text('PAID ₹20', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(shuttle.name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Passenger: ${widget.userEmail}', style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12)),
                  const SizedBox(height: 16),
                  
                  // Mock QR Code Box
                  Container(
                    width: 140,
                    height: 140,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.qr_code_2_rounded, size: 90, color: Color(0xFF0F172A)),
                        Text('TKT-${math.Random().nextInt(90000) + 10000}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF4ADE80)),
                      const SizedBox(width: 6),
                      Text('Valid for current trip • ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Done / Ready to Board', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // Dialog / BottomSheet to show Free Faculty Transit Pass
  void _showFacultyPassModal(ShuttleData shuttle) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 48, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: const Color(0xFF059669).withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.verified_user_rounded, color: Color(0xFF059669), size: 24),
                ),
                const SizedBox(width: 10),
                const Text(
                  'VIT Faculty VIP Transit Pass',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Prestigious Faculty Pass Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF065F46), Color(0xFF047857)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFDE047), width: 1.5),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF059669).withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 8)),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('VIT VELLORE FACULTY PRIVILEGE', style: TextStyle(color: Color(0xFFFDE047), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xFFFDE047), borderRadius: BorderRadius.circular(12)),
                        child: const Text('FREE (₹0)', style: TextStyle(color: Color(0xFF065F46), fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('Faculty Exclusive Shuttle', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Faculty Member: ${widget.userEmail}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 16),
                  
                  // Mock VIP Faculty Barcode Box
                  Container(
                    width: 140,
                    height: 140,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.stars_rounded, size: 70, color: Color(0xFF059669)),
                        SizedBox(height: 4),
                        Text('VERIFIED FACULTY', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF059669))),
                        Text('ACCESS: FREE VIP', style: TextStyle(fontSize: 8, color: Color(0xFF64748B))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.verified_rounded, size: 16, color: Color(0xFFFDE047)),
                      SizedBox(width: 6),
                      Text('Complimentary Faculty Transit Privilege', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Verified • Ready to Board', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _walkingPositionSub?.cancel();
    _reconnectTimer?.cancel();
    _channel.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedShuttle = _activeShuttles[_selectedShuttleId] ?? _activeShuttles.values.first;

    // Filter shuttles for map markers
    final visibleShuttles = _activeShuttles.values.where((s) {
      if (_shuttleFilter == 'general') return !s.isFaculty;
      if (_shuttleFilter == 'faculty') return s.isFaculty;
      return true;
    }).toList();

    return Stack(
      children: [
        // 1. Campus Map with Trackpad & Touch Gesture Zoom
        Listener(
          onPointerPanZoomStart: (event) {
            _trackpadStartZoom = _mapController.camera.zoom;
          },
          onPointerPanZoomUpdate: (event) {
            if (event.scale != 1.0 && event.scale > 0) {
              final logScale = math.log(event.scale) / math.ln2;
              final newZoom = (_trackpadStartZoom + logScale).clamp(3.0, 20.0);
              _mapController.move(_mapController.camera.center, newZoom);
            }
          },
          onPointerSignal: (pointerSignal) {
            if (pointerSignal is PointerScrollEvent && pointerSignal.scrollDelta.dy != 0) {
              final currentZoom = _mapController.camera.zoom;
              final newZoom = (currentZoom - pointerSignal.scrollDelta.dy * 0.003).clamp(3.0, 20.0);
              _mapController.move(_mapController.camera.center, newZoom);
            }
          },
          child: FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(12.9715, 79.1595),
              initialZoom: 16.2,
              minZoom: 3.0,
              maxZoom: 20.0,
              interactionOptions: InteractionOptions(
                flags: InteractiveFlag.drag |
                    InteractiveFlag.flingAnimation |
                    InteractiveFlag.pinchMove |
                    InteractiveFlag.pinchZoom |
                    InteractiveFlag.doubleTapZoom |
                    InteractiveFlag.doubleTapDragZoom |
                    InteractiveFlag.scrollWheelZoom,
                pinchZoomThreshold: 0.05,
                enableMultiFingerGestureRace: true,
              ),
            ),
            children: [
              // Google Maps Standard Road Tiles
              TileLayer(
                urlTemplate: 'https://{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                subdomains: const ['mt0', 'mt1', 'mt2', 'mt3'],
                userAgentPackageName: 'com.example.shuttle_flutter_app',
                maxZoom: 20,
              ),
              
              // Campus Polyline Routes
              PolylineLayer(
                polylines: [
                  ..._allRoutes.where((route) {
                    return _selectedRouteId == 'all' || route['id'].toString() == _selectedRouteId;
                  }).map((route) {
                    var rawPoints = route['points'];
                    List<LatLng> points = [];
                    if (rawPoints != null && rawPoints is List) {
                      for (var p in rawPoints) {
                        if (p is Map) {
                          points.add(LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()));
                        }
                      }
                    }
                    return Polyline(
                      points: points,
                      strokeWidth: 6.5,
                      color: Colors.white.withOpacity(0.9),
                    );
                  }),
                  ..._allRoutes.where((route) {
                    return _selectedRouteId == 'all' || route['id'].toString() == _selectedRouteId;
                  }).map((route) {
                    var rawPoints = route['points'];
                    List<LatLng> points = [];
                    if (rawPoints != null && rawPoints is List) {
                      for (var p in rawPoints) {
                        if (p is Map) {
                          points.add(LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()));
                        }
                      }
                    }
                    return Polyline(
                      points: points,
                      strokeWidth: 4.5,
                      color: _parseColor(route['color']),
                    );
                  }),
                  if (_isDirectionsMode && _walkingRoutePoints.isNotEmpty) ...[
                    Polyline(
                      points: _walkingRoutePoints,
                      strokeWidth: 8.0,
                      color: const Color(0x6606B6D4),
                    ),
                    Polyline(
                      points: _walkingRoutePoints,
                      strokeWidth: 4.5,
                      color: const Color(0xFF38BDF8),
                    ),
                  ] else if (_userLocation != null && _nearestStopName != null && _campusStops.containsKey(_nearestStopName)) ...[
                    Polyline(
                      points: [_userLocation!, _campusStops[_nearestStopName!]!],
                      strokeWidth: 3.5,
                      color: const Color(0xFF38BDF8),
                    ),
                  ],
                ],
              ),

              // Markers: Campus Stops, Destination Flag and Live Moving Shuttles
              MarkerLayer(
                markers: [
                  if (_isDirectionsMode && _nearestStopName != null && _campusStops.containsKey(_nearestStopName))
                    Marker(
                      point: _campusStops[_nearestStopName!]!,
                      width: 120,
                      height: 34,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF38BDF8), width: 1.5),
                          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🏁', style: TextStyle(fontSize: 12)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _nearestStopName!,
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Passenger Live Location Marker
                  if (_userLocation != null)
                    Marker(
                      point: _userLocation!,
                      width: 44,
                      height: 44,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF0284C7).withOpacity(0.25),
                            ),
                          ),
                          Container(
                            width: 15,
                            height: 15,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF0284C7),
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6)],
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Campus Stop Markers
                  ..._campusStops.entries.map((entry) {
                    final name = entry.key;
                    final isMh = name.contains('Block') || name.contains('MH') || name.contains('GD Naidu') || name.contains('Vajpayee');
                    final isLh = name.contains('Ladies') || name.contains('LH');
                    final isFac = name.contains('Faculty') || name.contains('Main Gate') || name.contains('Quarters') || name.contains('Admin');
                    final pinColor = isMh
                        ? const Color(0xFF0284C7)
                        : (isLh
                            ? const Color(0xFFEC4899)
                            : (isFac ? const Color(0xFF059669) : const Color(0xFF8B5CF6)));

                    return Marker(
                      point: entry.value,
                      width: 110,
                      height: 52,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: pinColor, width: 1.2),
                              boxShadow: const [
                                BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 2)),
                              ],
                            ),
                            child: Text(
                              entry.key,
                              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Colors.white),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: pinColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  // All Shuttles (Men's Hostels #101 vs Women's Hostel #102 vs Faculty #201)
                  ...visibleShuttles.map((shuttle) {
                    final isFaculty = shuttle.isFaculty;
                    final isWomen = shuttle.shuttleId.contains('102') || shuttle.name.toLowerCase().contains('women');
                    final isSelected = shuttle.shuttleId == _selectedShuttleId;
                    final themeColor = isFaculty
                        ? const Color(0xFF059669)
                        : (isWomen ? const Color(0xFFEC4899) : const Color(0xFF0284C7));
                    final badgeText = isFaculty
                        ? 'FACULTY • FREE'
                        : (isWomen ? 'LH 102 • ₹20' : 'MH 101 • ₹20');

                    return Marker(
                      point: shuttle.location,
                      width: 82,
                      height: 82,
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _selectedShuttleId = shuttle.shuttleId);
                          _mapController.move(shuttle.location, 16.5);
                        },
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Radar pulse outer glow
                            Container(
                              width: isSelected ? 76 : 64,
                              height: isSelected ? 76 : 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: themeColor.withOpacity(isSelected ? 0.28 : 0.16),
                              ),
                            ),
                            // Inner Bus Avatar
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: isFaculty
                                      ? [const Color(0xFF059669), const Color(0xFF047857)]
                                      : (isWomen
                                          ? [const Color(0xFFDB2777), const Color(0xFFBE185D)]
                                          : [const Color(0xFF0284C7), const Color(0xFF0369A1)]),
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isFaculty ? const Color(0xFFFDE047) : Colors.white,
                                  width: isSelected ? 3.0 : 2.0,
                                ),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 3)),
                                ],
                              ),
                              child: Icon(
                                isFaculty ? Icons.stars_rounded : Icons.directions_bus_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            // Top live badge
                            Positioned(
                              top: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isFaculty ? const Color(0xFFFDE047) : Colors.white70,
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  badgeText,
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    color: isFaculty ? const Color(0xFFFDE047) : Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),
        ),

        // 2. Ultra-Compact Floating Top Pill Bar & Nearest Stop Banner
        Positioned(
          top: 14,
          left: 14,
          right: 14,
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xEE0F172A),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
                      boxShadow: const [
                        BoxShadow(color: Colors.black38, blurRadius: 14, offset: Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      children: [
                        // VIT Transit Badge & Role
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isFacultyUser ? const Color(0xFF059669) : const Color(0xFF0284C7),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                isFacultyUser ? 'Faculty' : 'Student',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Route dropdown pill
                        Expanded(
                          child: Container(
                            height: 30,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedRouteId,
                                isDense: true,
                                isExpanded: true,
                                dropdownColor: const Color(0xFF1E293B),
                                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 16),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                onChanged: (val) {
                                  if (val != null) setState(() => _selectedRouteId = val);
                                },
                                items: [
                                  const DropdownMenuItem(value: 'all', child: Text('All Campus Routes', style: TextStyle(color: Colors.white))),
                                  ..._allRoutes.map((r) => DropdownMenuItem(
                                    value: r['id'].toString(),
                                    child: Text(r['route_name'] ?? 'Route ${r['id']}', style: const TextStyle(color: Colors.white)),
                                  )),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Live Status Pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                          decoration: BoxDecoration(
                            color: _isConnected ? const Color(0x2222C55E) : const Color(0x22EF4444),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _isConnected ? const Color(0x5522C55E) : const Color(0x55EF4444),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: _isConnected ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _isConnected ? 'LIVE' : 'OFFLINE',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: _isConnected ? const Color(0xFF4ADE80) : const Color(0xFFF87171),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Logout Button
                        IconButton(
                          icon: const Icon(Icons.logout_rounded, size: 16, color: Color(0xFFF87171)),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          constraints: const BoxConstraints(),
                          onPressed: _logout,
                          tooltip: 'Logout',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 6),

                  // 2b. In-App Walking Directions HUD or Nearest Stop Floating Pill
                  if (_isDirectionsMode)
                    _buildDirectionsHud()
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xEE0F172A),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _nearestStopName != null ? const Color(0x6638BDF8) : Colors.white12,
                        ),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 3)),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Text('📍', style: TextStyle(fontSize: 13)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _requestLocationAndFindNearestStop(manual: true),
                              child: Text(
                                _isLocatingUser
                                    ? 'Locating your nearest campus stop...'
                                    : (_nearestStopName != null
                                        ? 'Nearest: $_nearestStopName • ${(_nearestStopDistanceMeters!).toStringAsFixed(0)}m (~$_nearestStopWalkMinutes min walk)'
                                        : 'Tap to allow location & find nearest stop'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _nearestStopName != null ? Colors.white : const Color(0xFF94A3B8),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          if (_nearestStopName != null) ...[
                            InkWell(
                              onTap: _startDirectionsMode,
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [Color(0xFF0284C7), Color(0xFF38BDF8)]),
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: [
                                    BoxShadow(color: const Color(0xFF0284C7).withOpacity(0.4), blurRadius: 4),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('🚶', style: TextStyle(fontSize: 10)),
                                    SizedBox(width: 3),
                                    Text('Directions', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                          ],
                          InkWell(
                            onTap: () => _requestLocationAndFindNearestStop(manual: true),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                border: Border.all(color: Colors.white24),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _nearestStopName != null ? 'Focus' : 'Enable GPS',
                                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),

        // 3. Floating Map Controls (Zoom In, Zoom Out, GPS Locate, Center)
        Positioned(
          right: 14,
          bottom: 148,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xEE0F172A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
                ),
                child: Column(
                  children: [
                    InkWell(
                      onTap: () {
                        final currentZoom = _mapController.camera.zoom;
                        _mapController.move(_mapController.camera.center, (currentZoom + 1).clamp(3.0, 20.0));
                      },
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      child: const Padding(
                        padding: EdgeInsets.all(9),
                        child: Icon(Icons.add, color: Colors.white, size: 18),
                      ),
                    ),
                    Container(height: 1, width: 24, color: Colors.white10),
                    InkWell(
                      onTap: () {
                        final currentZoom = _mapController.camera.zoom;
                        _mapController.move(_mapController.camera.center, (currentZoom - 1).clamp(3.0, 20.0));
                      },
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                      child: const Padding(
                        padding: EdgeInsets.all(9),
                        child: Icon(Icons.remove, color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xEE0F172A),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white12),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
                ),
                child: IconButton(
                  icon: const Icon(Icons.gps_fixed_rounded, color: Color(0xFF38BDF8), size: 18),
                  tooltip: 'My Location & Nearest Stop',
                  onPressed: () => _requestLocationAndFindNearestStop(manual: true),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xEE0F172A),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white12),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
                ),
                child: IconButton(
                  icon: Icon(
                    Icons.my_location_rounded,
                    color: selectedShuttle.isFaculty ? const Color(0xFF34D399) : const Color(0xFF38BDF8),
                    size: 18,
                  ),
                  tooltip: 'Center on Selected Shuttle',
                  onPressed: () {
                    _mapController.move(selectedShuttle.location, 16.5);
                  },
                ),
              ),
            ],
          ),
        ),

        // 4. Sleek Floating Bottom Tray (leaves 85%+ visible map space)
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 500),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: const Color(0xEE0F172A),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white12),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 20, offset: Offset(0, 6)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Row 1: Shuttle Quick Switcher (General Bus ₹20 vs Faculty Shuttle Free)
                  // Row 1: Shuttle Quick Switcher (Men's Hostels ₹20, Women's Hostel ₹20, Faculty Free)
                  Row(
                    children: [
                      // Men's Hostels Bus Pill
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _selectedShuttleId = 'vit_general_bus_101');
                            final s = _activeShuttles['vit_general_bus_101'];
                            if (s != null) _mapController.move(s.location, 16.5);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                            decoration: BoxDecoration(
                              color: _selectedShuttleId == 'vit_general_bus_101'
                                  ? const Color(0xFF0284C7).withOpacity(0.22)
                                  : const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _selectedShuttleId == 'vit_general_bus_101'
                                    ? const Color(0xFF0284C7)
                                    : Colors.white10,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: const [
                                    Text('🚌', style: TextStyle(fontSize: 12)),
                                    SizedBox(width: 4),
                                    Text('MH', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0284C7),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: const Text('₹20', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.white)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),

                      // Women's Hostel Bus Pill
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _selectedShuttleId = 'vit_general_bus_102');
                            final s = _activeShuttles['vit_general_bus_102'];
                            if (s != null) _mapController.move(s.location, 16.5);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                            decoration: BoxDecoration(
                              color: _selectedShuttleId == 'vit_general_bus_102'
                                  ? const Color(0xFFEC4899).withOpacity(0.22)
                                  : const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _selectedShuttleId == 'vit_general_bus_102'
                                    ? const Color(0xFFEC4899)
                                    : Colors.white10,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: const [
                                    Text('🌸', style: TextStyle(fontSize: 12)),
                                    SizedBox(width: 4),
                                    Text('LH', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDB2777),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: const Text('₹20', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.white)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),

                      // Faculty Shuttle Pill
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _selectedShuttleId = 'vit_faculty_shuttle_201');
                            final s = _activeShuttles['vit_faculty_shuttle_201'];
                            if (s != null) _mapController.move(s.location, 16.5);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                            decoration: BoxDecoration(
                              color: _selectedShuttleId == 'vit_faculty_shuttle_201'
                                  ? const Color(0xFF059669).withOpacity(0.22)
                                  : const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _selectedShuttleId == 'vit_faculty_shuttle_201'
                                    ? const Color(0xFF059669)
                                    : Colors.white10,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: const [
                                    Text('⭐', style: TextStyle(fontSize: 12)),
                                    SizedBox(width: 4),
                                    Text('Faculty', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF059669),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: const Text('FREE', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.white)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Row 2: Telemetry Snapshot & Action Button
                  Row(
                    children: [
                      // Next stop & speed chip
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle)),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    selectedShuttle.stopETAs.isNotEmpty
                                        ? 'Next: ${selectedShuttle.stopETAs[0]['stopName']}'
                                        : 'Next: MB (Main Bldg)',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  selectedShuttle.stopETAs.isNotEmpty
                                      ? '• ${selectedShuttle.stopETAs[0]['etaMinutes']}m'
                                      : '• 2m',
                                  style: TextStyle(
                                    color: selectedShuttle.isFaculty ? const Color(0xFF34D399) : const Color(0xFF38BDF8),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Speed: ${selectedShuttle.speed.toStringAsFixed(0)} km/h • Live Tracking',
                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                            ),
                          ],
                        ),
                      ),

                      // Action button
                      if (!selectedShuttle.isFaculty)
                        ElevatedButton(
                          onPressed: () => _showGeneralBusTicketModal(selectedShuttle),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0284C7),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          child: const Text('🎫 Pass (₹20)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        )
                      else if (isFacultyUser)
                        ElevatedButton(
                          onPressed: () => _showFacultyPassModal(selectedShuttle),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          child: const Text('⭐ Pass (FREE)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        )
                      else
                        ElevatedButton(
                          onPressed: () => setState(() => _selectedShuttleId = 'vit_general_bus_101'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD97706),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          child: const Text('Switch ₹20', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),

                  // Row 3: Tap to expand stops & crowding
                  GestureDetector(
                    onTap: () => setState(() => _isDrawerExpanded = !_isDrawerExpanded),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _isDrawerExpanded ? 'Hide stops ▴' : 'Show all stops & crowd info ▾',
                        style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),

                  // Collapsible Section: Stops List & Crowding
                  if (_isDrawerExpanded) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 52,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: selectedShuttle.stopETAs.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (context, i) {
                          final stop = selectedShuttle.stopETAs[i];
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(stop['stopName'] ?? 'Stop', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.white)),
                                Text(
                                  '${stop['etaMinutes']} min away',
                                  style: TextStyle(
                                    color: selectedShuttle.isFaculty ? const Color(0xFF34D399) : const Color(0xFF38BDF8),
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Text('Crowd: ', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                        const SizedBox(width: 4),
                        _buildCrowdChip('Low', '🟢 Low', const Color(0xFF22C55E)),
                        const SizedBox(width: 4),
                        _buildCrowdChip('Moderate', '🟡 Med', const Color(0xFFF59E0B)),
                        const SizedBox(width: 4),
                        _buildCrowdChip('Full', '🔴 Full', const Color(0xFFEF4444)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCrowdChip(String level, String label, Color color) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _reportCrowding(level),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.18),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 4. DRIVER MODE SCREEN (Select Vehicle: General ₹20 vs Faculty Free)
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
  String _coords = "Ready to start shift";
  final MapController _mapController = MapController();
  LatLng _driverLocation = const LatLng(12.9715, 79.1595);

  // Selected vehicle for the shift
  String _selectedShuttleType = 'general'; // 'general' or 'faculty'

  String get currentShuttleId => _selectedShuttleType == 'faculty' ? 'vit_faculty_shuttle_201' : 'vit_general_bus_101';
  String get currentVehicleName => _selectedShuttleType == 'faculty' ? 'Faculty Exclusive Shuttle #201' : 'General Campus Bus #101';
  double get currentFare => _selectedShuttleType == 'faculty' ? 0.0 : 20.0;

  @override
  void initState() {
    super.initState();
    _channel = WebSocketChannel.connect(
      Uri.parse(getWsUrl('role=driver&shuttleId=$currentShuttleId')),
    );
  }

  Future<void> _toggleTracking() async {
    if (_isTracking) {
      _positionStream?.cancel();
      setState(() {
        _isTracking = false;
        _currentSpeed = 0.0;
        _coords = "Shift Ended";
      });
    } else {
      var status = await Permission.locationWhenInUse.request();
      if (status.isGranted) {
        setState(() => _isTracking = true);

        const LocationSettings locationSettings = LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 2,
        );

        _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
          final speedKmH = (position.speed * 3.6).clamp(0.0, 80.0);
          setState(() {
            _currentSpeed = speedKmH;
            _coords = "${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}";
            _driverLocation = LatLng(position.latitude, position.longitude);
          });
          _mapController.move(_driverLocation, 16.5);

          final payload = {
            'type': 'LOCATION_UPDATE',
            'shuttleId': currentShuttleId,
            'name': currentVehicleName,
            'shuttleType': _selectedShuttleType,
            'fare': currentFare,
            'lat': position.latitude,
            'lng': position.longitude,
            'speed': speedKmH,
            'heading': position.heading,
            'timestamp': DateTime.now().toIso8601String(),
          };
          _channel.sink.add(jsonEncode(payload));
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission required for Driver mode')),
        );
      }
    }
  }

  Future<void> _logout() async {
    _positionStream?.cancel();
    _channel.sink.close();
    await supabase.auth.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MobileShell(child: RoleSelectionScreen())),
        (route) => false,
      );
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _channel.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFaculty = _selectedShuttleType == 'faculty';
    final themeColor = isFaculty ? const Color(0xFF059669) : const Color(0xFF0284C7);

    return Stack(
      children: [
        // 1. Fullscreen Map (covering 100% of viewport)
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _driverLocation,
            initialZoom: 16.5,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
              subdomains: const ['mt0', 'mt1', 'mt2', 'mt3'],
              userAgentPackageName: 'com.example.shuttle_flutter_app',
              maxZoom: 20,
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: _driverLocation,
                  width: 52,
                  height: 52,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: themeColor,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 3))],
                    ),
                    child: Icon(
                      isFaculty ? Icons.stars_rounded : Icons.directions_bus_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),

        // 2. Ultra-Compact Floating Top Bar
        Positioned(
          top: 14,
          left: 14,
          right: 14,
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 520),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xEE0F172A),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 14, offset: Offset(0, 4))],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: Colors.white),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Driver Console',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _isTracking ? const Color(0x2222C55E) : const Color(0x22EF4444),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _isTracking ? const Color(0x5522C55E) : const Color(0x55EF4444)),
                        ),
                        child: Text(
                          _isTracking ? 'BROADCASTING' : 'OFFLINE',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: _isTracking ? const Color(0xFF4ADE80) : const Color(0xFFF87171),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.logout_rounded, color: Color(0xFFF87171), size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: _logout,
                        tooltip: 'Logout',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // 3. Floating Bottom Controls: Vehicle Selector, Speedometer & Shift Button
        Positioned(
          left: 14,
          right: 14,
          bottom: 14,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 500),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xEE0F172A),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white12),
                boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 20, offset: Offset(0, 6))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Vehicle Service Switcher
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _isTracking ? null : () => setState(() => _selectedShuttleType = 'general'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: !isFaculty ? const Color(0xFF0284C7).withOpacity(0.22) : const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: !isFaculty ? const Color(0xFF0284C7) : Colors.white10,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: const [
                                Text('🚌 General Bus', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF38BDF8))),
                                Text('₹20', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.white70)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: _isTracking ? null : () => setState(() => _selectedShuttleType = 'faculty'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: isFaculty ? const Color(0xFF059669).withOpacity(0.22) : const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isFaculty ? const Color(0xFF059669) : Colors.white10,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: const [
                                Text('⭐ Faculty Shuttle', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF34D399))),
                                Text('FREE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.white70)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Speed & Coordinates row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: themeColor.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: themeColor),
                            ),
                            child: Text(
                              '${_currentSpeed.toStringAsFixed(0)} KM/H',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: themeColor),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(_coords, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                        ],
                      ),
                      ElevatedButton(
                        onPressed: _toggleTracking,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isTracking ? const Color(0xFFEF4444) : themeColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: Text(
                          _isTracking ? 'END SHIFT' : 'START SHIFT',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
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

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

// Automatically resolves PC's local IP (10.172.147.61) or current browser host for phone testing
String getWsUrl(String params) {
  if (kIsWeb) {
    final host = Uri.base.host.isNotEmpty && Uri.base.host != 'localhost' ? Uri.base.host : '10.172.147.61';
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
    final width = MediaQuery.of(context).size.width;

    // On actual mobile phones, render 100% full screen
    if (width <= 500) {
      return Scaffold(
        body: SafeArea(child: child),
      );
    }

    // On desktop browsers (like Chrome), render inside a realistic phone frame
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: Container(
          width: 420,
          height: 870,
          margin: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(36),
            border: Border.all(color: const Color(0xFF334155), width: 8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.55),
                blurRadius: 40,
                spreadRadius: 8,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // Phone speaker / dynamic island notch simulation
              Container(
                height: 28,
                color: Colors.white,
                child: Center(
                  child: Container(
                    width: 120,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
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
      name: 'General Campus Bus #101',
      shuttleType: 'general',
      fare: 20.0,
      location: const LatLng(12.9692, 79.1559),
      speed: 21.0,
      heading: 45.0,
      stopETAs: [
        {'stopName': 'MB (Main Building)', 'etaMinutes': 2, 'distanceKm': 0.4},
        {'stopName': 'SJT Tower', 'etaMinutes': 5, 'distanceKm': 1.1},
        {'stopName': "Men's Hostel", 'etaMinutes': 9, 'distanceKm': 2.0},
      ],
      lastUpdated: DateTime.now(),
    ),
    'vit_faculty_shuttle_201': ShuttleData(
      shuttleId: 'vit_faculty_shuttle_201',
      name: 'Faculty Exclusive Shuttle #201',
      shuttleType: 'faculty',
      fare: 0.0,
      location: const LatLng(12.9715, 79.1633),
      speed: 19.0,
      heading: 180.0,
      stopETAs: [
        {'stopName': 'Technology Tower (TT)', 'etaMinutes': 3, 'distanceKm': 0.6},
        {'stopName': 'MB Admin Block', 'etaMinutes': 6, 'distanceKm': 1.3},
        {'stopName': 'Main Gate', 'etaMinutes': 8, 'distanceKm': 1.9},
      ],
      lastUpdated: DateTime.now(),
    ),
  };

  String _selectedShuttleId = 'vit_general_bus_101';
  String _shuttleFilter = 'all'; // 'all', 'general', 'faculty'
  
  List<Map<String, dynamic>> _allRoutes = [];
  String _selectedRouteId = 'all';

  final MapController _mapController = MapController();
  double _trackpadStartZoom = 16.2;

  final Map<String, LatLng> _campusStops = {
    'Main Gate': const LatLng(12.9692, 79.1559),
    'MB (Main Bldg)': const LatLng(12.9698, 79.1588),
    'SJT Tower': const LatLng(12.9715, 79.1633),
    'TT (Tech Tower)': const LatLng(12.9730, 79.1585),
    "Men's Hostel": const LatLng(12.9750, 79.1610),
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
                ],
              ),

              // Markers: Campus Stops and Live Moving Shuttles
              MarkerLayer(
                markers: [
                  // Campus Stop Markers
                  ..._campusStops.entries.map((entry) => Marker(
                    point: entry.value,
                    width: 100,
                    height: 52,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF0F172A), width: 1.2),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
                            ],
                          ),
                          child: Text(
                            entry.key,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
                          ),
                        ),
                      ],
                    ),
                  )),

                  // Both Shuttles (General Bus vs Faculty Shuttle)
                  ...visibleShuttles.map((shuttle) {
                    final isFaculty = shuttle.isFaculty;
                    final isSelected = shuttle.shuttleId == _selectedShuttleId;
                    final themeColor = isFaculty ? const Color(0xFF059669) : const Color(0xFF0284C7);
                    final badgeText = isFaculty ? 'FACULTY • FREE' : 'BUS 101 • ₹20';

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
                                      : [const Color(0xFF0284C7), const Color(0xFF0369A1)],
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

        // 2. Top Header Bar with Portal Badge & Route Dropdown
        Positioned(
          top: 14,
          left: 14,
          right: 14,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.logout_rounded, size: 20, color: Color(0xFFEF4444)),
                      onPressed: _logout,
                      tooltip: 'Logout to Role Selection',
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                isFacultyUser ? 'Faculty Portal' : 'Student Portal',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isFacultyUser ? const Color(0xFF059669) : const Color(0xFF0284C7),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: isFacultyUser ? const Color(0xFFDCFCE7) : const Color(0xFFE0F2FE),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isFacultyUser ? 'FREE PASS' : '₹20 FARE',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: isFacultyUser ? const Color(0xFF059669) : const Color(0xFF0284C7),
                                  ),
                                ),
                              )
                            ],
                          ),
                          DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedRouteId,
                              isDense: true,
                              isExpanded: true,
                              style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 13),
                              onChanged: (val) {
                                if (val != null) setState(() => _selectedRouteId = val);
                              },
                              items: [
                                const DropdownMenuItem(value: 'all', child: Text('All Campus Routes')),
                                ..._allRoutes.map((r) => DropdownMenuItem(
                                  value: r['id'].toString(),
                                  child: Text(r['route_name'] ?? 'Route ${r['id']}'),
                                )),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _isConnected ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
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
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _isConnected ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Filter Tabs: [All] [General Bus (₹20)] [Faculty Shuttle (Free)]
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
                ),
                child: Row(
                  children: [
                    _buildFilterTab('all', 'All Fleet'),
                    _buildFilterTab('general', '🚌 General (₹20)'),
                    _buildFilterTab('faculty', '⭐ Faculty (Free)'),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 3. Floating Map Controls (Zoom In, Zoom Out, Center)
        Positioned(
          right: 14,
          bottom: 275,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
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
                        child: Icon(Icons.add, color: Color(0xFF0F172A), size: 20),
                      ),
                    ),
                    Container(height: 1, width: 26, color: const Color(0xFFE2E8F0)),
                    InkWell(
                      onTap: () {
                        final currentZoom = _mapController.camera.zoom;
                        _mapController.move(_mapController.camera.center, (currentZoom - 1).clamp(3.0, 20.0));
                      },
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                      child: const Padding(
                        padding: EdgeInsets.all(9),
                        child: Icon(Icons.remove, color: Color(0xFF0F172A), size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
                ),
                child: IconButton(
                  icon: Icon(
                    Icons.my_location_rounded,
                    color: selectedShuttle.isFaculty ? const Color(0xFF059669) : const Color(0xFF0284C7),
                    size: 20,
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

        // 4. Bottom Sheet: Selected Shuttle Telemetry, Stop ETAs, Ticket Actions & Crowding
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -4))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Shuttle Selector Toggle Chips
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: _activeShuttles.values.map((s) {
                      final isSelected = s.shuttleId == _selectedShuttleId;
                      final isFac = s.isFaculty;
                      final activeColor = isFac ? const Color(0xFF059669) : const Color(0xFF0284C7);

                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedShuttleId = s.shuttleId);
                          _mapController.move(s.location, 16.5);
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? activeColor.withOpacity(0.12) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? activeColor : const Color(0xFFE2E8F0),
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isFac ? Icons.stars_rounded : Icons.directions_bus_rounded,
                                size: 16,
                                color: isSelected ? activeColor : const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isFac ? 'Faculty Shuttle (Free)' : 'General Bus (₹20)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? activeColor : const Color(0xFF475569),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 10),

                // Selected Shuttle Details & Fare Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedShuttle.name,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            selectedShuttle.isFaculty
                                ? 'Privilege: Faculty Only • Fare: Free (₹0)'
                                : 'Available for Everyone • Fare: ₹20 fixed',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: selectedShuttle.isFaculty ? const Color(0xFF059669) : const Color(0xFF0284C7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${selectedShuttle.speed.toStringAsFixed(1)} km/h',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: selectedShuttle.isFaculty ? const Color(0xFF059669) : const Color(0xFF0284C7),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Stop ETAs Horizontal List
                if (selectedShuttle.stopETAs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text('Calculating stop ETAs...', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                  )
                else
                  SizedBox(
                    height: 66,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: selectedShuttle.stopETAs.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final stop = selectedShuttle.stopETAs[i];
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(stop['stopName'] ?? 'Stop', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              const SizedBox(height: 2),
                              Text(
                                '${stop['etaMinutes']} min away',
                                style: TextStyle(
                                  color: selectedShuttle.isFaculty ? const Color(0xFF059669) : const Color(0xFF0284C7),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                ),
                              ),
                              Text('${stop['distanceKm']} km', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 10),

                // ACTION ROW: TICKET BUTTON / FACULTY PASS / RESTRICTION WARNING
                if (!selectedShuttle.isFaculty) ...[
                  // General Bus: Available for everyone, ₹20 Ticket
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showGeneralBusTicketModal(selectedShuttle),
                      icon: const Icon(Icons.qr_code_rounded, size: 18),
                      label: const Text('Book / Pay Ticket (₹20)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ] else if (isFacultyUser) ...[
                  // Faculty Shuttle & User IS Faculty: FREE PASS
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showFacultyPassModal(selectedShuttle),
                      icon: const Icon(Icons.verified_rounded, size: 18),
                      label: const Text('Show Faculty Transit Pass (FREE)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ] else ...[
                  // Faculty Shuttle but User is STUDENT: Show Restriction Alert & Quick Switch
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_rounded, color: Color(0xFFB45309), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Faculty-Only Service',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
                              ),
                              Text(
                                'Free for faculty. Students must board General Bus (₹20).',
                                style: TextStyle(fontSize: 10, color: Color(0xFFB45309)),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() => _selectedShuttleId = 'vit_general_bus_101');
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            backgroundColor: const Color(0xFF0284C7),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          child: const Text('Switch', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 10),

                // Crowding Reporting Buttons
                Row(
                  children: [
                    const Text('Crowding:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDCFCE7),
                          foregroundColor: const Color(0xFF15803D),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _reportCrowding('Low'),
                        child: const Text('Low', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFEF3C7),
                          foregroundColor: const Color(0xFFB45309),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _reportCrowding('Moderate'),
                        child: const Text('Med', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFEE2E2),
                          foregroundColor: const Color(0xFFB91C1C),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _reportCrowding('Full'),
                        child: const Text('Full', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterTab(String filterKey, String label) {
    final isSelected = _shuttleFilter == filterKey;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _shuttleFilter = filterKey),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF0F172A) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : const Color(0xFF64748B),
              ),
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
  String _coords = "Waiting to start shift...";

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
          });

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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  const Text('Driver Console', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 20),
                onPressed: _logout,
                tooltip: 'Logout to Role Selection',
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Vehicle Type Selector (General Bus ₹20 vs Faculty Free)
          const Text('Assigned Vehicle Service', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _isTracking ? null : () => setState(() => _selectedShuttleType = 'general'),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: !isFaculty ? const Color(0xFF0284C7).withOpacity(0.12) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: !isFaculty ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0),
                        width: !isFaculty ? 1.5 : 1.0,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('🚌 General Bus', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0284C7))),
                        SizedBox(height: 2),
                        Text('Fare: ₹20 • For Everyone', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: _isTracking ? null : () => setState(() => _selectedShuttleType = 'faculty'),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isFaculty ? const Color(0xFF059669).withOpacity(0.12) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isFaculty ? const Color(0xFF059669) : const Color(0xFFE2E8F0),
                        width: isFaculty ? 1.5 : 1.0,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('⭐ Faculty Shuttle', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF059669))),
                        SizedBox(height: 2),
                        Text('Fare: FREE • Faculty Only', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Operational Guidelines Notice
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isFaculty ? const Color(0xFFECFDF5) : const Color(0xFFF0F9FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isFaculty ? const Color(0xFFA7F3D0) : const Color(0xFFBAE6FD)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: themeColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isFaculty
                        ? 'Instruction: Free boarding for faculty members. Verify faculty ID pass.'
                        : 'Instruction: Collect ₹20 per passenger or verify digital QR ticket.',
                    style: TextStyle(fontSize: 11, color: themeColor, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Speedometer Dial
          Center(
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: _isTracking
                      ? (isFaculty ? [const Color(0xFF059669), const Color(0xFF10B981)] : [const Color(0xFF0284C7), const Color(0xFF38BDF8)])
                      : [const Color(0xFF64748B), const Color(0xFF475569)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: (_isTracking ? themeColor : Colors.black).withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  )
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _currentSpeed.toStringAsFixed(0),
                    style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const Text('KM / H', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          Center(
            child: Text(
              _isTracking ? 'BROADCASTING $currentShuttleId'.toUpperCase() : 'DRIVER SHIFT INACTIVE',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1.0,
                color: _isTracking ? themeColor : const Color(0xFF64748B),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(_coords, style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
          ),

          const Spacer(),

          // Start / End Shift Button
          ElevatedButton(
            onPressed: _toggleTracking,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isTracking ? const Color(0xFFEF4444) : themeColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 4,
            ),
            child: Text(
              _isTracking ? 'END DRIVING SHIFT' : 'START DRIVING SHIFT',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

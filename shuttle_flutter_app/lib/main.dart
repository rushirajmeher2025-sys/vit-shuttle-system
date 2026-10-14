import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'dart:async';

// Supabase live configuration
const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://yaypinidsnhmcoccvqco.supabase.co');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlheXBpbmlkc25obWNvY2N2cWNvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE5NTU1OTMsImV4cCI6MjEwNzUzMTU5M30.PDzKPv4lTEISGBPq6pacG9aueBtUoRV-sqk_JZN_vpU');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  runApp(const MyApp());
}

final supabase = Supabase.instance.client;

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
      home: const MobileShell(child: AuthScreen()),
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

    // On desktop browsers (like Chrome), render inside a phone frame
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark slate surrounding background
      body: Center(
        child: Container(
          width: 420,
          height: 860,
          margin: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(36),
            border: Border.all(color: const Color(0xFF334155), width: 8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 40,
                spreadRadius: 8,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // Phone speaker / dynamic notch simulation
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
// 1. AUTHENTICATION SCREEN
// ============================================================================
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isLogin = true;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  void _checkSession() {
    final session = supabase.auth.currentSession;
    if (session != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MobileShell(child: RoleSelectionScreen())),
        );
      });
    }
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

    if (!email.endsWith('@vitstudent.ac.in')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Must be a valid VIT email (ends with @vitstudent.ac.in)'),
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
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MobileShell(child: RoleSelectionScreen())),
        );
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 15),
          // App Logo and Header
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0284C7).withOpacity(0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  )
                ],
              ),
              child: const Icon(Icons.directions_bus_rounded, size: 44, color: Colors.white),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'VIT Shuttle Tracker',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            ),
          ),
          const Center(
            child: Text(
              'Real-Time Campus Transit & ETAs',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
          ),
          const SizedBox(height: 28),

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
                            color: _isLogin ? const Color(0xFF0284C7) : const Color(0xFF64748B),
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
                            color: !_isLogin ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Email Input
          const Text('VIT Student Email', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF334155))),
          const SizedBox(height: 6),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: 'name@vitstudent.ac.in',
              hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
              prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF64748B)),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.5)),
            ),
          ),
          const SizedBox(height: 16),

          // Password Input
          const Text('Password', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF334155))),
          const SizedBox(height: 6),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              hintText: '••••••••••••',
              hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
              prefixIcon: const Icon(Icons.lock_outline_rounded, color: Color(0xFF64748B)),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: const Color(0xFF64748B)),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.5)),
            ),
          ),
          const SizedBox(height: 24),

          // Submit Button
          ElevatedButton(
            onPressed: _isLoading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_isLogin ? 'Sign In to Campus' : 'Create Account', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 16),

          Center(
            child: Text(
              _isLogin ? 'VIT Vellore Campus Transit Network' : 'Registration requires @vitstudent.ac.in',
              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 2. ROLE SELECTION SCREEN
// ============================================================================
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await supabase.auth.signOut();
    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MobileShell(child: AuthScreen())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    final email = user?.email ?? 'Student';

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Welcome Back,', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                    Text(
                      email.split('@')[0],
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444)),
                onPressed: () => _logout(context),
                tooltip: 'Logout',
              ),
            ],
          ),
          const SizedBox(height: 30),
          const Text('Select Transit Mode', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          const SizedBox(height: 6),
          const Text('Choose your view for campus tracking', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
          const SizedBox(height: 20),

          // Option 1: Student Passenger
          _buildRoleCard(
            context: context,
            title: 'Student Passenger',
            subtitle: 'Track campus shuttles live, view next stop ETAs & report crowding',
            icon: Icons.directions_bus_filled_rounded,
            gradient: const [Color(0xFF0284C7), Color(0xFF0369A1)],
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MobileShell(child: StudentMapScreen())),
              );
            },
          ),
          const SizedBox(height: 16),

          // Option 2: Shuttle Driver
          _buildRoleCard(
            context: context,
            title: 'Shuttle Driver',
            subtitle: 'Stream real-time vehicle GPS coordinates and speed to campus',
            icon: Icons.speed_rounded,
            gradient: const [Color(0xFF059669), Color(0xFF047857)],
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MobileShell(child: DriverModeScreen())),
              );
            },
          ),
          const Spacer(),

          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                const Text('Vellore Campus System Online', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: gradient[0].withOpacity(0.3),
              blurRadius: 14,
              offset: const Offset(0, 6),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, size: 32, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.85), height: 1.3)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 3. STUDENT MAP SCREEN (Live tracking, Stops, ETAs & Crowding)
// ============================================================================
class StudentMapScreen extends StatefulWidget {
  const StudentMapScreen({super.key});

  @override
  State<StudentMapScreen> createState() => _StudentMapScreenState();
}

class _StudentMapScreenState extends State<StudentMapScreen> {
  late WebSocketChannel _channel;
  bool _isConnected = false;
  
  LatLng? _shuttleLocation;
  List<dynamic> _stopETAs = [];
  double _shuttleSpeed = 0;
  
  List<Map<String, dynamic>> _allRoutes = [];
  String _selectedRouteId = 'all';

  final MapController _mapController = MapController();

  final Map<String, LatLng> _campusStops = {
    'Main Gate': const LatLng(12.9692, 79.1559),
    'SJT': const LatLng(12.9715, 79.1633),
    'TT': const LatLng(12.9730, 79.1585),
    'MB': const LatLng(12.9698, 79.1588),
    "Men's Hostel": const LatLng(12.9750, 79.1610),
  };

  @override
  void initState() {
    super.initState();
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
    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('ws://localhost:8080?role=student'),
      );
      
      setState(() => _isConnected = true);

      _channel.stream.listen(
        (message) {
          final data = jsonDecode(message);
          if (data['type'] == 'SHUTTLE_MOVED' || data['type'] == 'LOCATION_UPDATE') {
            setState(() {
              _shuttleLocation = LatLng(data['lat'], data['lng']);
              _shuttleSpeed = data['speed'] != null ? (data['speed'] as num).toDouble() : 18.0;
              if (data['stopETAs'] != null) {
                _stopETAs = data['stopETAs'];
              }
            });
          }
        },
        onDone: () => setState(() => _isConnected = false),
        onError: (e) => setState(() => _isConnected = false),
      );
    } catch (e) {
      setState(() => _isConnected = false);
    }
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
        'shuttleId': 'shuttle-01',
        'level': level,
        'timestamp': DateTime.now().toIso8601String(),
      }));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reported crowding: $level'), backgroundColor: Colors.green),
      );
    }
  }

  @override
  void dispose() {
    _channel.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 1. The Campus Map
        FlutterMap(
          mapController: _mapController,
          options: const MapOptions(
            initialCenter: LatLng(12.9692, 79.1559), // VIT Vellore
            initialZoom: 15.6,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.shuttle_flutter_app',
            ),
            
            // Dynamic Routes
            PolylineLayer(
              polylines: _allRoutes.where((route) {
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
              }).toList(),
            ),

            // Stop Markers & Shuttle Marker
            MarkerLayer(
              markers: [
                ..._campusStops.entries.map((entry) => Marker(
                  point: entry.value,
                  width: 36,
                  height: 36,
                  child: Tooltip(
                    message: entry.key,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.red.shade600,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                      ),
                      child: const Icon(Icons.location_on, color: Colors.white, size: 20),
                    ),
                  ),
                )),
                if (_shuttleLocation != null)
                  Marker(
                    point: _shuttleLocation!,
                    width: 50,
                    height: 50,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4))],
                      ),
                      child: const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 28),
                    ),
                  ),
              ],
            ),
          ],
        ),

        // 2. Top Header Bar
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedRouteId,
                      isExpanded: true,
                      style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 14),
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
        ),

        // 3. Floating Re-Center Button
        Positioned(
          right: 16,
          bottom: 230,
          child: FloatingActionButton.small(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF0F172A),
            elevation: 3,
            onPressed: () {
              if (_shuttleLocation != null) {
                _mapController.move(_shuttleLocation!, 16.5);
              } else {
                _mapController.move(const LatLng(12.9692, 79.1559), 16.0);
              }
            },
            child: const Icon(Icons.my_location_rounded),
          ),
        ),

        // 4. Bottom Stop ETAs & Crowding Sheet
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -4))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Next Stops & ETAs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                    Text(
                      _shuttleSpeed > 0 ? '${_shuttleSpeed.toStringAsFixed(1)} km/h' : '18.0 km/h',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_stopETAs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Connecting to live telemetry...', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                  )
                else
                  SizedBox(
                    height: 72,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _stopETAs.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final stop = _stopETAs[i];
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(stop['stopName'] ?? 'Stop', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              const SizedBox(height: 2),
                              Text('${stop['etaMinutes']} min away', style: const TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.w600, fontSize: 12)),
                              Text('${stop['distanceKm']} km', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 14),
                // Report Crowding Row
                Row(
                  children: [
                    const Text('Crowding:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDCFCE7),
                          foregroundColor: const Color(0xFF15803D),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _reportCrowding('Low'),
                        child: const Text('Low', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFEF3C7),
                          foregroundColor: const Color(0xFFB45309),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _reportCrowding('Moderate'),
                        child: const Text('Med', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFEE2E2),
                          foregroundColor: const Color(0xFFB91C1C),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _reportCrowding('Full'),
                        child: const Text('Full', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
  String _coords = "Waiting to start...";

  @override
  void initState() {
    super.initState();
    _channel = WebSocketChannel.connect(
      Uri.parse('ws://localhost:8080?role=driver&shuttleId=shuttle-01'),
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
            'shuttleId': 'shuttle-01',
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

  @override
  void dispose() {
    _positionStream?.cancel();
    _channel.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              const Text('Driver Console', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
          const Spacer(),

          // Speedometer Dial
          Center(
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: _isTracking
                      ? [const Color(0xFF059669), const Color(0xFF10B981)]
                      : [const Color(0xFF64748B), const Color(0xFF475569)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: (_isTracking ? const Color(0xFF10B981) : Colors.black).withOpacity(0.3),
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
                    style: const TextStyle(fontSize: 52, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const Text('KM / H', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white70)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          Center(
            child: Text(
              _isTracking ? 'BROADCASTING LIVE GPS' : 'DRIVER SHIFT INACTIVE',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                letterSpacing: 1.0,
                color: _isTracking ? const Color(0xFF059669) : const Color(0xFF64748B),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(_coords, style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
          ),

          const Spacer(),

          // Start / End Shift Button
          ElevatedButton(
            onPressed: _toggleTracking,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isTracking ? const Color(0xFFEF4444) : const Color(0xFF059669),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 4,
            ),
            child: Text(
              _isTracking ? 'END SHIFT' : 'START DRIVING SHIFT',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

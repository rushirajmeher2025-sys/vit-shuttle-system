import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'dart:async';

// Make sure to replace these with your actual Supabase credentials for production
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const AuthScreen(),
    );
  }
}

// ==========================================
// 1. Authentication Screen
// ==========================================
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
          MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
        );
      });
    }
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
      return;
    }

    if (!email.endsWith('@vitstudent.ac.in')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email must end with @vitstudent.ac.in')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        await supabase.auth.signInWithPassword(email: email, password: password);
      } else {
        await supabase.auth.signUp(email: email, password: password);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registration successful! Check your email or login.')));
        if (!mounted) return;
        setState(() => _isLogin = true);
        setState(() => _isLoading = false);
        return;
      }
      
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
        );
      }
    } on AuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('An unexpected error occurred')));
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
    return Scaffold(
      appBar: AppBar(title: Text(_isLogin ? 'VIT Shuttle Login' : 'Student Registration')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'VIT Student Email', 
                hintText: 'example@vitstudent.ac.in'
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            if (_isLoading)
              const CircularProgressIndicator()
            else
              ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: Text(_isLogin ? 'Login' : 'Register', style: const TextStyle(fontSize: 16)),
              ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => setState(() => _isLogin = !_isLogin),
              child: Text(_isLogin ? 'Need an account? Register here' : 'Have an account? Login here'),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 2. Role Selection Screen (Post-Login)
// ==========================================
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await supabase.auth.signOut();
    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VIT Shuttle System'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
            tooltip: 'Logout',
          )
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.school),
              label: const Text('I am a Student'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StudentMapScreen()),
                );
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.directions_bus),
              label: const Text('I am a Shuttle Driver'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DriverModeScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 3. Driver Mode Screen
// ==========================================
class DriverModeScreen extends StatefulWidget {
  const DriverModeScreen({super.key});

  @override
  State<DriverModeScreen> createState() => _DriverModeScreenState();
}

class _DriverModeScreenState extends State<DriverModeScreen> {
  late WebSocketChannel _channel;
  bool _isTracking = false;
  StreamSubscription<Position>? _positionStream;
  String _statusMessage = "Ready to start shift";

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
        _statusMessage = "Shift ended.";
      });
    } else {
      var status = await Permission.locationWhenInUse.request();
      if (status.isGranted) {
        setState(() {
          _isTracking = true;
          _statusMessage = "Tracking active. Sending location...";
        });
        
        const LocationSettings locationSettings = LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        );

        _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
          final payload = {
            'type': 'LOCATION_UPDATE',
            'shuttleId': 'shuttle-01',
            'lat': position.latitude,
            'lng': position.longitude,
            'speed': position.speed * 3.6,
            'heading': position.heading,
            'timestamp': DateTime.now().toIso8601String(),
          };
          _channel.sink.add(jsonEncode(payload));
        });
      } else {
        setState(() {
          _statusMessage = "Location permission denied.";
        });
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
    return Scaffold(
      appBar: AppBar(title: const Text('Driver Mode')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_statusMessage, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 30),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _isTracking ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              ),
              onPressed: _toggleTracking,
              child: Text(_isTracking ? 'End Shift' : 'Start Shift', style: const TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 4. Student Map Screen
// ==========================================
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
  
  // Route polyline state
  List<Map<String, dynamic>> _allRoutes = [];
  String _selectedRouteId = 'all';

  // Static Campus Stops for rendering on the map
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

  Color _parseColor(String? colorHex) {
    if (colorHex == null || colorHex.isEmpty) return Colors.blue;
    try {
      final hex = colorHex.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (e) {
      return Colors.blue;
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
          if (data['type'] == 'SHUTTLE_MOVED') {
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

  void _showShuttleDetails() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Shuttle ID: shuttle-01', style: Theme.of(context).textTheme.titleLarge),
                Text('Current Speed: ${_shuttleSpeed.toStringAsFixed(1)} km/h'),
                const Divider(),
                const Text('Upcoming Stops:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 10),
                if (_stopETAs.isEmpty) const Text('Calculating ETAs...'),
                ..._stopETAs.map((eta) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Text('${eta['stopName']}: ${eta['etaMinutes']} mins away (${eta['distanceKm']} km)'),
                  );
                }),
                const SizedBox(height: 20),
                const Text('Report Crowding:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade100),
                      onPressed: () => _reportCrowding('Low'),
                      child: const Text('Low'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade100),
                      onPressed: () => _reportCrowding('Moderate'),
                      child: const Text('Moderate'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade100),
                      onPressed: () => _reportCrowding('Full'),
                      child: const Text('Full'),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      }
    );
  }

  void _reportCrowding(String level) {
    if (_isConnected) {
      _channel.sink.add(jsonEncode({
        'type': 'REPORT_CROWDING',
        'shuttleId': 'shuttle-01',
        'level': level,
        'timestamp': DateTime.now().toIso8601String(),
      }));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reported crowding: $level')));
      Navigator.pop(context); // close bottom sheet
    }
  }

  @override
  void dispose() {
    _channel.sink.close();
    super.dispose();
  }
  
  List<Polyline> _buildPolylines() {
    List<Polyline> polylines = [];
    for (var route in _allRoutes) {
      // Filter out if a specific route is selected and it does not match
      if (_selectedRouteId != 'all' && route['id'].toString() != _selectedRouteId) {
        continue;
      }
      
      // Parse coordinates. Assuming route['points'] is a JSON array: [{"lat": 12.9, "lng": 79.1}, ...]
      var rawPoints = route['points'];
      List<LatLng> points = [];
      if (rawPoints != null && rawPoints is List) {
        for (var p in rawPoints) {
          if (p is Map) {
            points.add(LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble()));
          }
        }
      }
      
      // Fallback: If DB format differs, you may need to adjust the parser.
      if (points.isNotEmpty) {
        polylines.add(
          Polyline(
            points: points,
            strokeWidth: 4.0,
            color: _parseColor(route['color']),
          )
        );
      }
    }
    return polylines;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Live Tracking'),
            const SizedBox(width: 10),
            if (_allRoutes.isNotEmpty)
              DropdownButton<String>(
                value: _selectedRouteId,
                icon: const Icon(Icons.map, color: Colors.white),
                dropdownColor: Theme.of(context).colorScheme.primary,
                style: const TextStyle(color: Colors.white),
                underline: Container(), // hide underline
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() {
                      _selectedRouteId = newValue;
                    });
                  }
                },
                items: [
                  const DropdownMenuItem<String>(
                    value: 'all',
                    child: Text('All Routes'),
                  ),
                  ..._allRoutes.map<DropdownMenuItem<String>>((route) {
                    return DropdownMenuItem<String>(
                      value: route['id'].toString(),
                      child: Text(route['route_name'] ?? 'Route ${route['id']}'),
                    );
                  })
                ],
              ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: Icon(
                _isConnected ? Icons.wifi : Icons.wifi_off,
                color: _isConnected ? Colors.green : Colors.red,
              ),
            ),
          ),
        ],
      ),
      body: FlutterMap(
        options: const MapOptions(
          initialCenter: LatLng(12.9692, 79.1559), // VIT Vellore center
          initialZoom: 15.5,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.shuttle_flutter_app',
          ),
          
          // Render dynamically fetched polylines
          PolylineLayer(
            polylines: _buildPolylines(),
          ),
          
          MarkerLayer(
            markers: [
              // Campus Stop Markers
              ..._campusStops.entries.map((entry) => Marker(
                point: entry.value,
                width: 40,
                height: 40,
                child: Tooltip(
                  message: entry.key,
                  child: const Icon(Icons.location_on, color: Colors.red, size: 30),
                ),
              )),
              // Live Shuttle Marker
              if (_shuttleLocation != null)
                Marker(
                  point: _shuttleLocation!,
                  width: 60,
                  height: 60,
                  child: GestureDetector(
                    onTap: _showShuttleDetails,
                    child: const Icon(Icons.directions_bus, color: Colors.blue, size: 40),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

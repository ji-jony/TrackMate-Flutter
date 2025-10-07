import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:math' as math;
import 'share.dart';
import 'view.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(VehicleLocationApp());
}

class VehicleLocationApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vehicle Tracker',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Roboto',
      ),
      home: SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// Firebase Service for Vehicle Tracking
class VehicleFirebaseService {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  // Save vehicle location
  Future<void> saveVehicleLocation(Map<String, dynamic> locationData) async {
    try {
      await _database.child('vehicle_locations').push().set({
        ...locationData,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      throw Exception('Failed to save location: $e');
    }
  }

  // Get all vehicle locations
  Future<Map<String, dynamic>?> getVehicleLocations() async {
    try {
      final snapshot = await _database.child('vehicle_locations').get();
      if (snapshot.exists) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get locations: $e');
    }
  }

  // Listen to vehicle locations in real-time
  Stream<Map<String, dynamic>?> getVehicleLocationsStream() {
    return _database.child('vehicle_locations').onValue.map((event) {
      if (event.snapshot.exists) {
        return Map<String, dynamic>.from(event.snapshot.value as Map);
      }
      return null;
    });
  }

  // Save shared location with code
  Future<void> saveSharedLocation(String code, Map<String, dynamic> locationData) async {
    try {
      await _database.child('shared_locations').child(code).set({
        ...locationData,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      throw Exception('Failed to save shared location: $e');
    }
  }

  // Get shared location by code
  Future<Map<String, dynamic>?> getSharedLocation(String code) async {
    try {
      final snapshot = await _database.child('shared_locations').child(code).get();
      if (snapshot.exists) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get shared location: $e');
    }
  }

  // Update shared location
  Future<void> updateSharedLocation(String code, Map<String, dynamic> locationData) async {
    try {
      await _database.child('shared_locations').child(code).update({
        ...locationData,
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      throw Exception('Failed to update shared location: $e');
    }
  }

  // Delete shared location
  Future<void> deleteSharedLocation(String code) async {
    try {
      await _database.child('shared_locations').child(code).remove();
    } catch (e) {
      throw Exception('Failed to delete shared location: $e');
    }
  }

  // Listen to shared location by code
  Stream<Map<String, dynamic>?> getSharedLocationStream(String code) {
    return _database.child('shared_locations').child(code).onValue.map((event) {
      if (event.snapshot.exists) {
        return Map<String, dynamic>.from(event.snapshot.value as Map);
      }
      return null;
    });
  }
}

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late AnimationController _vehicleController;
  late Animation<double> _vehicleAnimation;

  String _statusText = 'Initializing...';

  @override
  void initState() {
    super.initState();
    
    _animationController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    );
    
    _vehicleController = AnimationController(
      duration: Duration(seconds: 3),
      vsync: this,
    )..repeat();
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    
    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );
    
    _vehicleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _vehicleController, curve: Curves.linear),
    );
    
    _animationController.forward();
    
    _requestLocationPermission();
  }

  Future<void> _requestLocationPermission() async {
    setState(() {
      _statusText = 'Checking permissions...';
    });
    
    await Future.delayed(Duration(seconds: 2));
    
    try {
      // Check current permission status
      PermissionStatus status = await Permission.location.status;
      
      if (status.isGranted) {
        setState(() {
          _statusText = 'Permission granted! Starting app...';
        });
        await Future.delayed(Duration(seconds: 1));
        _navigateToMainScreen();
        return;
      }
      
      if (status.isDenied) {
        setState(() {
          _statusText = 'Requesting location permission...';
        });
        
        // Request permission
        PermissionStatus newStatus = await Permission.location.request();
        
        if (newStatus.isGranted) {
          setState(() {
            _statusText = 'Permission granted! Starting app...';
          });
          await Future.delayed(Duration(seconds: 1));
          _navigateToMainScreen();
        } else if (newStatus.isPermanentlyDenied) {
          setState(() {
            _statusText = 'Permission permanently denied. Please enable in settings.';
          });
          _showPermissionDialog();
        } else {
          setState(() {
            _statusText = 'Permission denied. App needs location access.';
          });
          _showPermissionDialog();
        }
      } else if (status.isPermanentlyDenied) {
        setState(() {
          _statusText = 'Permission permanently denied. Please enable in settings.';
        });
        _showPermissionDialog();
      }
    } catch (e) {
      setState(() {
        _statusText = 'Error checking permissions. Please try again.';
      });
      print('Permission error: $e');
      
      // Still navigate to main screen after a delay in case of error
      await Future.delayed(Duration(seconds: 2));
      _navigateToMainScreen();
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Location Permission Required'),
          content: Text(
            'This app needs location permission to track and share vehicle locations. Please grant permission in the app settings.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _navigateToMainScreen();
              },
              child: Text('Continue Anyway'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await openAppSettings();
              },
              child: Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  void _navigateToMainScreen() {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => MainScreen()),
      );
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _vehicleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF4A90E2),
              Color(0xFF357ABD),
              Color(0xFF1E5F99),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return FadeTransition(
                    opacity: _fadeAnimation,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      child: Container(
                        padding: EdgeInsets.all(30),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                            width: 2,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 80,
                              color: Colors.white,
                            ),
                            SizedBox(height: 20),
                            Text(
                              'Vehicle Tracker',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 10),
                            Text(
                              'Track & Share Locations',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              SizedBox(height: 50),
              AnimatedBuilder(
                animation: _vehicleAnimation,
                builder: (context, child) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildVehicleIcon(Icons.directions_bus, 0),
                      _buildVehicleIcon(Icons.train, 0.25),
                      _buildVehicleIcon(Icons.flight, 0.5),
                      _buildVehicleIcon(Icons.directions_boat, 0.75),
                    ],
                  );
                },
              ),
              SizedBox(height: 30),
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                strokeWidth: 3,
              ),
              SizedBox(height: 20),
              Text(
                _statusText,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVehicleIcon(IconData icon, double delay) {
    return Transform.translate(
      offset: Offset(
        0,
        20 * math.sin((_vehicleAnimation.value + delay) * 2 * math.pi),
      ),
      child: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  late AnimationController _buttonController;
  late Animation<double> _buttonAnimation;
  final VehicleFirebaseService _firebaseService = VehicleFirebaseService();

  @override
  void initState() {
    super.initState();
    _buttonController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );
    _buttonAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _buttonController, curve: Curves.elasticOut),
    );
    _buttonController.forward();
  }

  @override
  void dispose() {
    _buttonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF667eea),
              Color(0xFF764ba2),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              children: [
                // Header
                Container(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      Container(
                        padding: EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                          ),
                        ),
                        child: Icon(
                          Icons.location_on,
                          size: 50,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 20),
                      Text(
                        'Vehicle Location Tracker',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Share and track vehicle locations in real-time',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                
                Expanded(
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _buttonAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _buttonAnimation.value,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Share Location Button
                              _buildMainButton(
                                context,
                                'Share Location',
                                Icons.share_location,
                                Colors.green,
                                () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ShareLocationScreen(),
                                    ),
                                  );
                                },
                              ),
                              
                              SizedBox(height: 30),
                              
                              // View Locations Button
                              _buildMainButton(
                                context,
                                'View Locations',
                                Icons.map,
                                Colors.blue,
                                () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ViewLocationsScreen(),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                
                // Vehicle Icons Row
                Container(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildVehicleIconMain(Icons.directions_bus, 'Bus'),
                      _buildVehicleIconMain(Icons.train, 'Train'),
                      _buildVehicleIconMain(Icons.flight, 'Air'),
                      _buildVehicleIconMain(Icons.directions_boat, 'Ferry'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainButton(
    BuildContext context,
    String text,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return Container(
      width: double.infinity,
      height: 70,
      margin: EdgeInsets.symmetric(horizontal: 20),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: color,
          elevation: 8,
          shadowColor: Colors.black26,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28),
            SizedBox(width: 15),
            Text(
              text,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleIconMain(IconData icon, String label) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
            ),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 24,
          ),
        ),
        SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
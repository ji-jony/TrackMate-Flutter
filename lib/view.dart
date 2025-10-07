import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import 'share_pr.dart'; // Import the private screen
import 'vehicle_map_screen.dart'; // Import the new map screen

class Vehicle {
  final String id;
  final String vehicleName;
  final String vehicleNumber;
  final String vehicleType;
  final String from;
  final String to;
  final int estimatedHours;
  final int estimatedMinutes;
  final String description;
  final String? password;
  final bool isRealTimeEnabled;

  Vehicle({
    required this.id,
    required this.vehicleName,
    required this.vehicleNumber,
    required this.vehicleType,
    required this.from,
    required this.to,
    required this.estimatedHours,
    required this.estimatedMinutes,
    required this.description,
    this.password,
    required this.isRealTimeEnabled,
  });

  factory Vehicle.fromJson(String key, Map<dynamic, dynamic> json) {
    return Vehicle(
      id: key,
      vehicleName: json['vehicleName'] ?? '',
      vehicleNumber: json['vehicleNumber'] ?? '',
      vehicleType: json['vehicleType'] ?? 'Bus',
      from: json['from'] ?? '',
      to: json['to'] ?? '',
      estimatedHours: json['estimatedHours'] ?? 0,
      estimatedMinutes: json['estimatedMinutes'] ?? 0,
      description: json['description'] ?? '',
      password: json['password'],
      isRealTimeEnabled: json['isRealTimeEnabled'] ?? false,
    );
  }

  String get estimatedTime {
    if (estimatedHours == 0 && estimatedMinutes == 0) return 'Not specified';
    String timeString = '';
    if (estimatedHours > 0) timeString += '${estimatedHours}h';
    if (estimatedMinutes > 0) {
      if (timeString.isNotEmpty) timeString += ' ';
      timeString += '${estimatedMinutes}m';
    }
    return timeString;
  }
}

class VehicleService {
  static final _db = FirebaseDatabase.instance.ref();

  static Future<List<Vehicle>> getPublicVehicles() async {
    try {
      final snapshot = await _db.child('shared_locations').once();
      if (!snapshot.snapshot.exists) return [];

      final data = snapshot.snapshot.value as Map<dynamic, dynamic>;
      return data.entries
          .where((entry) {
            final vehicleData = entry.value as Map<dynamic, dynamic>;
            return vehicleData['shareType'] == 'Public' && vehicleData['status'] == 'active';
          })
          .map((entry) => Vehicle.fromJson(entry.key, entry.value))
          .toList();
    } catch (e) {
      return [];
    }
  }

  static Future<List<Vehicle>> getVehiclesByType(String type) async {
    final vehicles = await getPublicVehicles();
    return vehicles.where((v) => v.vehicleType == type).toList();
  }

  static Future<List<Vehicle>> searchVehicles(String query, String type) async {
    final vehicles = await getVehiclesByType(type);
    return vehicles.where((v) =>
        v.vehicleName.toLowerCase().contains(query.toLowerCase()) ||
        v.vehicleNumber.toLowerCase().contains(query.toLowerCase()) ||
        v.from.toLowerCase().contains(query.toLowerCase()) ||
        v.to.toLowerCase().contains(query.toLowerCase())).toList();
  }

  static Future<bool> terminateVehicle(String vehicleId, String password) async {
    try {
      final snapshot = await _db.child('shared_locations/$vehicleId').once();
      if (!snapshot.snapshot.exists) return false;

      final data = snapshot.snapshot.value as Map<dynamic, dynamic>;
      if (data['password'] == password) {
        await _db.child('shared_locations/$vehicleId').update({'status': 'terminated'});
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}

class ViewLocationsScreen extends StatefulWidget {
  @override
  _ViewLocationsScreenState createState() => _ViewLocationsScreenState();
}

class _ViewLocationsScreenState extends State<ViewLocationsScreen> {
  final _searchController = TextEditingController();
  List<Vehicle> _vehicles = [];
  String _selectedTab = 'Bus';
  bool _isLoading = true;
  Timer? _searchTimer;

  final _vehicleTypes = ['Bus', 'Train', 'Air', 'Ferry'];
  final _vehicleIcons = {
    'Bus': Icons.directions_bus,
    'Train': Icons.train,
    'Air': Icons.flight,
    'Ferry': Icons.directions_boat,
  };
  final _vehicleColors = {
    'Bus': Colors.green,
    'Train': Colors.blue,
    'Air': Colors.orange,
    'Ferry': Colors.teal,
  };

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadVehicles() async {
    setState(() => _isLoading = true);
    try {
      final vehicles = await VehicleService.getVehiclesByType(_selectedTab);
      setState(() {
        _vehicles = vehicles;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('Failed to load vehicles', Colors.red);
    }
  }

  void _onTabChanged(String type) {
    setState(() => _selectedTab = type);
    _loadVehicles();
  }

  void _onSearchChanged(String query) {
    _searchTimer?.cancel();
    _searchTimer = Timer(Duration(milliseconds: 300), () => _performSearch(query));
  }

  void _performSearch(String query) async {
    if (query.isEmpty) {
      _loadVehicles();
      return;
    }
    try {
      final results = await VehicleService.searchVehicles(query, _selectedTab);
      setState(() => _vehicles = results);
    } catch (e) {
      _showSnackBar('Search failed', Colors.red);
    }
  }

  void _showTerminateDialog(Vehicle vehicle) {
    final passwordController = TextEditingController();
    bool isTerminating = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.orange),
              SizedBox(width: 10),
              Text('Terminate Vehicle'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Enter password to terminate ${vehicle.vehicleName}:'),
              SizedBox(height: 15),
              TextField(
                controller: passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                obscureText: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isTerminating ? null : () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isTerminating ? null : () async {
                if (passwordController.text.isEmpty) {
                  _showSnackBar('Please enter password', Colors.red);
                  return;
                }

                setState(() => isTerminating = true);
                try {
                  final success = await VehicleService.terminateVehicle(
                    vehicle.id, passwordController.text);
                  
                  if (success) {
                    Navigator.pop(context);
                    _showSnackBar('Vehicle terminated successfully', Colors.green);
                    _loadVehicles();
                  } else {
                    setState(() => isTerminating = false);
                    _showSnackBar('Wrong password', Colors.red);
                  }
                } catch (e) {
                  setState(() => isTerminating = false);
                  _showSnackBar('Termination failed', Colors.red);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: isTerminating 
                ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Terminate'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  void _openMapScreen({String? vehicleId}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VehicleMapScreen(
          vehicleId: vehicleId,
          vehicleType: _selectedTab,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Vehicle Locations'),
        backgroundColor: _vehicleColors[_selectedTab],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () => _openMapScreen(),
            icon: Icon(Icons.map),
            tooltip: 'View Map',
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => SharePrivateScreen()),
              );
            },
            icon: Icon(Icons.lock),
            tooltip: 'Private Locations',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_vehicleColors[_selectedTab]!, _vehicleColors[_selectedTab]!.withOpacity(0.1)],
          ),
        ),
        child: Column(
          children: [
            _buildVehicleTypeTabs(),
            _buildSearchBar(),
            _buildActiveCountBadge(),
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: Colors.white))
                  : _vehicles.isEmpty
                      ? _buildEmptyState()
                      : _buildVehicleList(),
            ),
          ],
        ),
      ),
      floatingActionButton: _vehicles.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _openMapScreen(),
              backgroundColor: _vehicleColors[_selectedTab],
              foregroundColor: Colors.white,
              icon: Icon(Icons.map),
              label: Text('View All on Map'),
            )
          : null,
    );
  }

  Widget _buildVehicleTypeTabs() {
    return Container(
      height: 80,
      padding: EdgeInsets.all(10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _vehicleTypes.length,
        itemBuilder: (context, index) {
          String type = _vehicleTypes[index];
          bool isSelected = _selectedTab == type;
          
          return GestureDetector(
            onTap: () => _onTabChanged(type),
            child: Container(
              width: 100,
              margin: EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_vehicleIcons[type]!, 
                    color: isSelected ? _vehicleColors[type]! : Colors.white, size: 24),
                  SizedBox(height: 5),
                  Text(type, 
                    style: TextStyle(
                      color: isSelected ? _vehicleColors[type]! : Colors.white,
                      fontWeight: FontWeight.bold, fontSize: 10)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: 'Search ${_selectedTab.toLowerCase()}s...',
          prefixIcon: Icon(Icons.search),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                  icon: Icon(Icons.clear),
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildActiveCountBadge() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            decoration: BoxDecoration(
              color: _vehicleColors[_selectedTab]!,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_vehicles.length} Active ${_selectedTab.toUpperCase()}${_vehicles.length != 1 ? 'S' : ''}',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          Spacer(),
          if (_vehicles.isNotEmpty)
            GestureDetector(
              onTap: () => _openMapScreen(),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: _vehicleColors[_selectedTab]!),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.map, color: _vehicleColors[_selectedTab]!, size: 16),
                    SizedBox(width: 5),
                    Text('Map View', style: TextStyle(
                      color: _vehicleColors[_selectedTab]!,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    )),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_vehicleIcons[_selectedTab]!, size: 80, color: Colors.white.withOpacity(0.5)),
          SizedBox(height: 20),
          Text('No ${_selectedTab}s Available', 
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          SizedBox(height: 10),
          Text(
            _searchController.text.isNotEmpty
                ? 'No results found for "${_searchController.text}"'
                : 'No active ${_selectedTab.toLowerCase()}s are sharing location',
            style: TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleList() {
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      itemCount: _vehicles.length,
      itemBuilder: (context, index) => _buildVehicleCard(_vehicles[index]),
    );
  }

  Widget _buildVehicleCard(Vehicle vehicle) {
    return Container(
      margin: EdgeInsets.only(bottom: 15),
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Colors.grey.shade50],
            ),
          ),
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _vehicleColors[vehicle.vehicleType]!.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_vehicleIcons[vehicle.vehicleType]!, 
                      color: _vehicleColors[vehicle.vehicleType]!, size: 24),
                  ),
                  SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(vehicle.vehicleName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(vehicle.vehicleNumber, style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      if (vehicle.isRealTimeEnabled)
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(10)),
                          child: Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                        ),
                      SizedBox(width: 5),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(10)),
                        child: Text('ACTIVE', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 20),
              Container(
                padding: EdgeInsets.all(15),
                decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10)),
                child: Column(
                  children: [
                    _buildRouteInfo(Icons.location_on, 'From', vehicle.from, Colors.green),
                    SizedBox(height: 10),
                    _buildRouteInfo(Icons.location_on, 'To', vehicle.to, Colors.red),
                    SizedBox(height: 10),
                    _buildRouteInfo(Icons.access_time, 'Estimated Time', vehicle.estimatedTime, Colors.blue),
                  ],
                ),
              ),
              if (vehicle.description.isNotEmpty) ...[
                SizedBox(height: 15),
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(vehicle.description, 
                          style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
                      ),
                    ],
                  ),
                ),
              ],
              SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _openMapScreen(vehicleId: vehicle.id),
                      icon: Icon(Icons.map, size: 18),
                      label: Text('View on Map'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showTerminateDialog(vehicle),
                      icon: Icon(Icons.stop, size: 18),
                      label: Text('Terminate'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRouteInfo(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        SizedBox(width: 10),
        Text('$label: ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        Expanded(child: Text(value, style: TextStyle(fontSize: 14))),
      ],
    );
  }
}
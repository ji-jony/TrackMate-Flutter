import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class TrainRoute {
  final String trainName;
  final String trainNumber;
  final List<TrainStation> stations;
  final String type; // Express, Mail, Local, Intercity
  final List<String> operatingDays;

  TrainRoute({
    required this.trainName,
    required this.trainNumber,
    required this.stations,
    required this.type,
    required this.operatingDays,
  });

  // Get stations between two points
  List<TrainStation> getStationsBetween(String from, String to) {
    int fromIndex = stations.indexWhere((s) => s.name.toLowerCase().contains(from.toLowerCase()));
    int toIndex = stations.indexWhere((s) => s.name.toLowerCase().contains(to.toLowerCase()));
    
    if (fromIndex == -1 || toIndex == -1) return [];
    
    int start = fromIndex < toIndex ? fromIndex : toIndex;
    int end = fromIndex < toIndex ? toIndex : fromIndex;
    
    return stations.sublist(start, end + 1);
  }

  // Calculate total journey time between two stations
  Duration getJourneyTime(String from, String to) {
    List<TrainStation> routeStations = getStationsBetween(from, to);
    if (routeStations.length < 2) return Duration.zero;
    
    return routeStations.last.arrivalTime.difference(routeStations.first.departureTime);
  }

  // Check if train operates on given day
  bool operatesOn(String day) {
    return operatingDays.contains(day) || operatingDays.contains('Daily');
  }
}

class TrainStation {
  final String name;
  final String code;
  final LatLng position;
  final DateTime arrivalTime;
  final DateTime departureTime;
  final int stopDuration; // in minutes
  final double distanceFromDhaka; // in km

  TrainStation({
    required this.name,
    required this.code,
    required this.position,
    required this.arrivalTime,
    required this.departureTime,
    required this.stopDuration,
    required this.distanceFromDhaka,
  });
}

class TrainRouteService {
  static final TrainRouteService _instance = TrainRouteService._internal();
  factory TrainRouteService() => _instance;
  TrainRouteService._internal();

  // Bangladesh Railway Routes (Dhaka-connected trains)
  final List<TrainRoute> _trainRoutes = [
    // Dhaka to Chittagong
    TrainRoute(
      trainName: 'q Nishitha',
      trainNumber: '141',
      type: 'Express',
      operatingDays: ['Daily'],
      stations: [
        TrainStation(
          name: 'Dhaka (Kamalapur)',
          code: 'DK',
          position: LatLng(23.7315, 90.4266),
          arrivalTime: DateTime(2024, 1, 1, 0, 0),
          departureTime: DateTime(2024, 1, 1, 23, 10),
          stopDuration: 0,
          distanceFromDhaka: 0,
        ),
        TrainStation(
          name: 'Cumilla',
          code: 'CML',
          position: LatLng(23.4682, 91.1788),
          arrivalTime: DateTime(2024, 1, 2, 1, 35),
          departureTime: DateTime(2024, 1, 2, 1, 37),
          stopDuration: 2,
          distanceFromDhaka: 97,
        ),
        TrainStation(
          name: 'Feni',
          code: 'FN',
          position: LatLng(23.0159, 91.3976),
          arrivalTime: DateTime(2024, 1, 2, 2, 45),
          departureTime: DateTime(2024, 1, 2, 2, 47),
          stopDuration: 2,
          distanceFromDhaka: 162,
        ),
        TrainStation(
          name: 'Chittagong',
          code: 'CTG',
          position: LatLng(22.3569, 91.7832),
          arrivalTime: DateTime(2024, 1, 2, 5, 40),
          departureTime: DateTime(2024, 1, 2, 5, 40),
          stopDuration: 0,
          distanceFromDhaka: 264,
        ),
      ],
    ),
    
    // Dhaka to Sylhet
    TrainRoute(
      trainName: 'Parabat Express',
      trainNumber: '709',
      type: 'Express',
      operatingDays: ['Daily'],
      stations: [
        TrainStation(
          name: 'Dhaka (Kamalapur)',
          code: 'DK',
          position: LatLng(23.7315, 90.4266),
          arrivalTime: DateTime(2024, 1, 1, 0, 0),
          departureTime: DateTime(2024, 1, 1, 14, 50),
          stopDuration: 0,
          distanceFromDhaka: 0,
        ),
        TrainStation(
          name: 'Bhairab Bazar',
          code: 'BBZ',
          position: LatLng(24.0517, 90.9764),
          arrivalTime: DateTime(2024, 1, 1, 16, 23),
          departureTime: DateTime(2024, 1, 1, 16, 25),
          stopDuration: 2,
          distanceFromDhaka: 78,
        ),
        TrainStation(
          name: 'Kishoreganj',
          code: 'KSG',
          position: LatLng(24.4449, 90.7815),
          arrivalTime: DateTime(2024, 1, 1, 17, 15),
          departureTime: DateTime(2024, 1, 1, 17, 17),
          stopDuration: 2,
          distanceFromDhaka: 145,
        ),
        TrainStation(
          name: 'Mymensingh',
          code: 'MYM',
          position: LatLng(24.7471, 90.4203),
          arrivalTime: DateTime(2024, 1, 1, 18, 30),
          departureTime: DateTime(2024, 1, 1, 18, 32),
          stopDuration: 2,
          distanceFromDhaka: 120,
        ),
        TrainStation(
          name: 'Sylhet',
          code: 'SYL',
          position: LatLng(24.8949, 91.8687),
          arrivalTime: DateTime(2024, 1, 1, 22, 50),
          departureTime: DateTime(2024, 1, 1, 22, 50),
          stopDuration: 0,
          distanceFromDhaka: 242,
        ),
      ],
    ),

    // Dhaka to Rajshahi
    TrainRoute(
      trainName: 'Silk City Express',
      trainNumber: '751',
      type: 'Express',
      operatingDays: ['Daily'],
      stations: [
        TrainStation(
          name: 'Dhaka (Kamalapur)',
          code: 'DK',
          position: LatLng(23.7315, 90.4266),
          arrivalTime: DateTime(2024, 1, 1, 0, 0),
          departureTime: DateTime(2024, 1, 1, 15, 20),
          stopDuration: 0,
          distanceFromDhaka: 0,
        ),
        TrainStation(
          name: 'Tangail',
          code: 'TGL',
          position: LatLng(24.2513, 89.9167),
          arrivalTime: DateTime(2024, 1, 1, 17, 13),
          departureTime: DateTime(2024, 1, 1, 17, 15),
          stopDuration: 2,
          distanceFromDhaka: 124,
        ),
        TrainStation(
          name: 'Sirajganj',
          code: 'SRJ',
          position: LatLng(24.4533, 89.7006),
          arrivalTime: DateTime(2024, 1, 1, 18, 35),
          departureTime: DateTime(2024, 1, 1, 18, 37),
          stopDuration: 2,
          distanceFromDhaka: 158,
        ),
        TrainStation(
          name: 'Bogura',
          code: 'BOG',
          position: LatLng(24.8465, 89.3775),
          arrivalTime: DateTime(2024, 1, 1, 19, 45),
          departureTime: DateTime(2024, 1, 1, 19, 47),
          stopDuration: 2,
          distanceFromDhaka: 207,
        ),
        TrainStation(
          name: 'Rajshahi',
          code: 'RAJ',
          position: LatLng(24.3745, 88.6042),
          arrivalTime: DateTime(2024, 1, 1, 21, 50),
          departureTime: DateTime(2024, 1, 1, 21, 50),
          stopDuration: 0,
          distanceFromDhaka: 256,
        ),
      ],
    ),

    // Dhaka to Khulna
    TrainRoute(
      trainName: 'Sundarban Express',
      trainNumber: '805',
      type: 'Express',
      operatingDays: ['Daily'],
      stations: [
        TrainStation(
          name: 'Dhaka (Kamalapur)',
          code: 'DK',
          position: LatLng(23.7315, 90.4266),
          arrivalTime: DateTime(2024, 1, 1, 0, 0),
          departureTime: DateTime(2024, 1, 1, 6, 50),
          stopDuration: 0,
          distanceFromDhaka: 0,
        ),
        TrainStation(
          name: 'Faridpur',
          code: 'FRP',
          position: LatLng(23.6070, 89.8429),
          arrivalTime: DateTime(2024, 1, 1, 9, 15),
          departureTime: DateTime(2024, 1, 1, 9, 17),
          stopDuration: 2,
          distanceFromDhaka: 117,
        ),
        TrainStation(
          name: 'Goalanda Ghat',
          code: 'GLG',
          position: LatLng(23.6833, 89.6167),
          arrivalTime: DateTime(2024, 1, 1, 9, 50),
          departureTime: DateTime(2024, 1, 1, 9, 52),
          stopDuration: 2,
          distanceFromDhaka: 135,
        ),
        TrainStation(
          name: 'Jessore',
          code: 'JSR',
          position: LatLng(23.1665, 89.2081),
          arrivalTime: DateTime(2024, 1, 1, 12, 20),
          departureTime: DateTime(2024, 1, 1, 12, 22),
          stopDuration: 2,
          distanceFromDhaka: 165,
        ),
        TrainStation(
          name: 'Khulna',
          code: 'KHL',
          position: LatLng(22.8456, 89.5403),
          arrivalTime: DateTime(2024, 1, 1, 14, 25),
          departureTime: DateTime(2024, 1, 1, 14, 25),
          stopDuration: 0,
          distanceFromDhaka: 225,
        ),
      ],
    ),

    // Dhaka to Rangpur
    TrainRoute(
      trainName: 'Rangpur Express',
      trainNumber: '771',
      type: 'Express',
      operatingDays: ['Daily'],
      stations: [
        TrainStation(
          name: 'Dhaka (Kamalapur)',
          code: 'DK',
          position: LatLng(23.7315, 90.4266),
          arrivalTime: DateTime(2024, 1, 1, 0, 0),
          departureTime: DateTime(2024, 1, 1, 9, 0),
          stopDuration: 0,
          distanceFromDhaka: 0,
        ),
        TrainStation(
          name: 'Joydebpur',
          code: 'JYD',
          position: LatLng(24.1058, 90.4264),
          arrivalTime: DateTime(2024, 1, 1, 9, 45),
          departureTime: DateTime(2024, 1, 1, 9, 47),
          stopDuration: 2,
          distanceFromDhaka: 35,
        ),
        TrainStation(
          name: 'Tangail',
          code: 'TGL',
          position: LatLng(24.2513, 89.9167),
          arrivalTime: DateTime(2024, 1, 1, 10, 45),
          departureTime: DateTime(2024, 1, 1, 10, 47),
          stopDuration: 2,
          distanceFromDhaka: 124,
        ),
        TrainStation(
          name: 'Bogura',
          code: 'BOG',
          position: LatLng(24.8465, 89.3775),
          arrivalTime: DateTime(2024, 1, 1, 13, 15),
          departureTime: DateTime(2024, 1, 1, 13, 17),
          stopDuration: 2,
          distanceFromDhaka: 207,
        ),
        TrainStation(
          name: 'Rangpur',
          code: 'RNG',
          position: LatLng(25.7439, 89.2752),
          arrivalTime: DateTime(2024, 1, 1, 15, 30),
          departureTime: DateTime(2024, 1, 1, 15, 30),
          stopDuration: 0,
          distanceFromDhaka: 304,
        ),
      ],
    ),
  ];

  // Get all available trains
  List<TrainRoute> getAllTrains() => _trainRoutes;

  // Search trains by name or route
  List<TrainRoute> searchTrains(String query) {
    if (query.trim().isEmpty) return [];
    
    return _trainRoutes.where((train) {
      String searchQuery = query.toLowerCase();
      
      // Search by train name
      if (train.trainName.toLowerCase().contains(searchQuery)) return true;
      
      // Search by train number
      if (train.trainNumber.contains(searchQuery)) return true;
      
      // Search by station names
      for (TrainStation station in train.stations) {
        if (station.name.toLowerCase().contains(searchQuery)) return true;
      }
      
      return false;
    }).toList();
  }

  // Get trains between two stations
  List<TrainRoute> getTrainsBetween(String from, String to) {
    return _trainRoutes.where((train) {
      return train.getStationsBetween(from, to).length >= 2;
    }).toList();
  }

  // Get all unique station names
  Set<String> getAllStationNames() {
    Set<String> stations = {};
    for (TrainRoute train in _trainRoutes) {
      for (TrainStation station in train.stations) {
        stations.add(station.name);
      }
    }
    return stations;
  }

  // Get all unique city names (simplified station names)
  Set<String> getAllCityNames() {
    Set<String> cities = {};
    for (TrainRoute train in _trainRoutes) {
      for (TrainStation station in train.stations) {
        String cityName = station.name.split('(')[0].trim();
        cities.add(cityName);
      }
    }
    return cities;
  }

  // Find station by name (partial match)
  TrainStation? findStation(String name) {
    for (TrainRoute train in _trainRoutes) {
      for (TrainStation station in train.stations) {
        if (station.name.toLowerCase().contains(name.toLowerCase())) {
          return station;
        }
      }
    }
    return null;
  }

  // Get route polyline points for a train
  List<LatLng> getTrainRoutePoints(String trainNumber) {
    TrainRoute? train = _trainRoutes.firstWhere(
      (t) => t.trainNumber == trainNumber,
      orElse: () => _trainRoutes.first,
    );
    
    return train.stations.map((station) => station.position).toList();
  }

  // Format time for display
  String formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  // Format duration for display
  String formatDuration(Duration duration) {
    int hours = duration.inHours;
    int minutes = duration.inMinutes.remainder(60);
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  // Add new train route (for future expansion)
  void addTrainRoute(TrainRoute route) {
    _trainRoutes.add(route);
  }

  // Update existing train route
  void updateTrainRoute(String trainNumber, TrainRoute newRoute) {
    int index = _trainRoutes.indexWhere((t) => t.trainNumber == trainNumber);
    if (index != -1) {
      _trainRoutes[index] = newRoute;
    }
  }

  // Remove train route
  void removeTrainRoute(String trainNumber) {
    _trainRoutes.removeWhere((t) => t.trainNumber == trainNumber);
  }
}
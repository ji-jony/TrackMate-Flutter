import 'package:firebase_database/firebase_database.dart';

class FirebaseService {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  // Save data
  Future<void> saveData(String collection, Map<String, dynamic> data) async {
    try {
      await _database.child(collection).push().set(data);
    } catch (e) {
      throw Exception('Failed to save data: $e');
    }
  }

  // Get data once
  Future<Map<String, dynamic>?> getData(String collection) async {
    try {
      final snapshot = await _database.child(collection).get();
      if (snapshot.exists) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get data: $e');
    }
  }

  // Listen to data changes
  Stream<Map<String, dynamic>?> getDataStream(String collection) {
    return _database.child(collection).onValue.map((event) {
      if (event.snapshot.exists) {
        return Map<String, dynamic>.from(event.snapshot.value as Map);
      }
      return null;
    });
  }

  // Update data
  Future<void> updateData(String collection, String key, Map<String, dynamic> data) async {
    try {
      await _database.child(collection).child(key).update(data);
    } catch (e) {
      throw Exception('Failed to update data: $e');
    }
  }

  // Delete data
  Future<void> deleteData(String collection, String key) async {
    try {
      await _database.child(collection).child(key).remove();
    } catch (e) {
      throw Exception('Failed to delete data: $e');
    }
  }
}
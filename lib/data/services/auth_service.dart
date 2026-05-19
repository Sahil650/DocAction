import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:device_info_plus/device_info_plus.dart';


class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal() {
    _initBaseUrl();
  }

  final _storage = const FlutterSecureStorage();
  String _baseUrl = 'http://10.0.2.2:5000'; // Default for emulators

  Future<void> _initBaseUrl() async {
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      // For physical devices, we use 127.0.0.1 and expect the user to run:
      // 'adb reverse tcp:5000 tcp:5000'
      _baseUrl = androidInfo.isPhysicalDevice 
          ? 'http://127.0.0.1:5000' 
          : 'http://10.0.2.2:5000';
      
      if (androidInfo.isPhysicalDevice) {
        // Physical device connected
      }
    } else {
      _baseUrl = 'http://127.0.0.1:5000';
    }
  }

  String get baseUrl => _baseUrl;

  void updateBaseUrl(String url) {
    _baseUrl = url;
  }

  Future<String?> getToken() async {
    return await _storage.read(key: 'jwt_token');
  }

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null;
  }

  Future<void>? _initFuture;

  Future<void> _ensureInitialized() async {
    _initFuture ??= _initBaseUrl();
    await _initFuture;
  }

  Future<bool> isBackendHealthy() async {
    try {
      await _ensureInitialized();
      final response = await http.get(Uri.parse('$baseUrl/health')).timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasExternalInternet() async {
    try {
      // Try resolving a common domain first
      final result = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 5));
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) return true;
      
      // Fallback: Try a direct IP ping (Google DNS) to bypass potential DNS issues
      final socket = await Socket.connect('8.8.8.8', 53, timeout: const Duration(seconds: 3));
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    await _ensureInitialized();
    
    // Check for real internet connection before allowing login
    if (!await hasExternalInternet()) {
      return {
        'success': false,
        'message': 'No internet connection'
      };
    }

    print('DEBUG: Attempting login at: $baseUrl/login');
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      ).timeout(const Duration(seconds: 10));

      // Handle non-JSON responses or errors gracefully
      if (response.headers['content-type']?.contains('application/json') != true) {
        return {
          'success': false, 
          'message': 'Server error: Invalid response format (Expected JSON). Please check if backend is running.'
        };
      }

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        await _storage.write(key: 'jwt_token', value: data['token']);
        return {'success': true, 'user': data['user']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Login failed'};
      }
    } catch (e) {
      if (e is FormatException) {
        return {'success': false, 'message': 'Server returned an invalid response. Please check your connection or backend status.'};
      }
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> register(String email, String password) async {
    await _ensureInitialized();

    // Check for real internet connection before allowing registration
    if (!await hasExternalInternet()) {
      return {
        'success': false,
        'message': 'No internet connection'
      };
    }
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      ).timeout(const Duration(seconds: 10));

      // Handle non-JSON responses or errors gracefully
      if (response.headers['content-type']?.contains('application/json') != true) {
        return {
          'success': false, 
          'message': 'Server error: Invalid response format (Expected JSON). Please check if backend is running.'
        };
      }

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Registration failed'};
      }
    } catch (e) {
      if (e is FormatException) {
        return {'success': false, 'message': 'Server returned an invalid response. Please check your connection or backend status.'};
      }
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> forgotPassword(String email) async {
    await _ensureInitialized();

    // Check for real internet connection before allowing reset
    if (!await hasExternalInternet()) {
      return {
        'success': false,
        'message': 'No internet connection'
      };
    }
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      ).timeout(const Duration(seconds: 10));

      // Handle non-JSON responses or errors gracefully
      if (response.headers['content-type']?.contains('application/json') != true) {
        return {
          'success': false, 
          'message': 'Server error: Invalid response format (Expected JSON)'
        };
      }

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message'] ?? 'Reset link sent to your email'};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Process failed'};
      }
    } catch (e) {
      if (e is FormatException) {
        return {'success': false, 'message': 'Server returned an invalid response. Please try again later.'};
      }
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }


  Future<void> logout() async {
    await _storage.delete(key: 'jwt_token');
  }

  Future<Map<String, dynamic>?> getProfile() async {
    try {
      final token = await getToken();
      if (token == null) return null;

      final response = await http.get(
        Uri.parse('$baseUrl/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        // Token might be expired or invalid
        await logout();
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>> updateProfile(String name) async {
    try {
      final token = await getToken();
      if (token == null) return {'success': false, 'message': 'Not logged in'};

      final response = await http.put(
        Uri.parse('$baseUrl/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'name': name}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'user': data['user']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to update profile'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> uploadProfilePicture(File imageFile) async {
    try {
      final token = await getToken();
      if (token == null) return {'success': false, 'message': 'Not logged in'};

      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/profile-picture'));
      request.headers['Authorization'] = 'Bearer $token';
      
      request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));
      
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'profile_picture_url': data['profile_picture_url'], 'user': data['user']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to upload picture'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }
}

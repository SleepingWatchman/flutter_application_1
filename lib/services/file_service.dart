import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';

class FileService {
  static const String baseUrl = 'http://127.0.0.1:5294/api/file';

  Future<String> uploadFile(File file, String token) async {
    try {
      // Проверяем размер файла (не более 5MB)
      final fileSize = await file.length();
      if (fileSize > 5 * 1024 * 1024) {
        throw Exception('File size exceeds 5MB limit');
      }

      // Проверяем расширение файла
      final extension = file.path.toLowerCase().split('.').last;
      final allowedExtensions = ['jpg', 'jpeg', 'png', 'gif'];
      if (!allowedExtensions.contains(extension)) {
        throw Exception('Invalid file type. Allowed types: ${allowedExtensions.join(", ")}');
      }

      print('Creating multipart request...');
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/upload'));
      
      print('Adding authorization header...');
      request.headers['Authorization'] = 'Bearer $token';
      
      print('Creating multipart file...');
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        file.path,
      ));

      print('Sending request...');
      var response = await request.send();
      print('Response status code: ${response.statusCode}');
      
      var responseData = await response.stream.bytesToString();
      print('Response data: $responseData');

      if (response.statusCode == 200) {
        try {
          var data = json.decode(responseData);
          if (data['url'] != null) {
            print('Successfully uploaded file. URL: ${data['url']}');
            return data['url'];
          } else {
            throw Exception('Response missing URL');
          }
        } catch (e) {
          print('Error parsing response: $e');
          throw Exception('Invalid server response format');
        }
      } else {
        try {
          var error = json.decode(responseData);
          throw Exception(error['message'] ?? 'Failed to upload file');
        } catch (e) {
          throw Exception('Server error: ${response.statusCode}');
        }
      }
    } catch (e) {
      print('File upload error: $e');
      rethrow;
    }
  }
} 
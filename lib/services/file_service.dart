import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'server_config_service.dart';

class FileService {
  static Future<String> getUploadUrl() async {
    final baseUrl = await ServerConfigService.getBaseUrl();
    return '$baseUrl/api/file/upload';
  }

  static Future<String> getFileUrl(String relativeUrl) async {
    final baseUrl = await ServerConfigService.getBaseUrl();
    return '$baseUrl$relativeUrl';
  }

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
      var request = http.MultipartRequest('POST', Uri.parse(await getUploadUrl()));
      
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
            String relativeUrl = data['url'];
            // Формируем полный URL для изображения
            String fullUrl = await getFileUrl(relativeUrl);
            print('Successfully uploaded file. URL: $fullUrl');
            return fullUrl;
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
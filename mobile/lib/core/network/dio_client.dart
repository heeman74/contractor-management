import 'package:dio/dio.dart';

/// Base URL for Android emulator accessing host machine.
/// In production, this would be set via environment config.
const _baseUrl = 'http://10.0.2.2:8000/api/v1';

class DioClient {
  late final Dio _dio;

  DioClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (obj) => print('[DIO] $obj'), // ignore: avoid_print
      ),
    );
  }

  Dio get instance => _dio;
}

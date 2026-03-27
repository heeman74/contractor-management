import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Log severity levels, ordered from least to most severe.
enum LogLevel { verbose, debug, info, warning, error, fatal }

/// A single structured log entry.
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final String? error;
  final String? stackTrace;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.error,
    this.stackTrace,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'level': level.name,
        'tag': tag,
        'message': message,
        if (error != null) 'error': error,
        if (stackTrace != null) 'stackTrace': stackTrace,
      };
}

/// Structured logger for ContractorHub mobile app.
///
/// Features:
/// - Log levels: verbose, debug, info, warning, error, fatal
/// - Ring buffer (last 500 entries) for crash reporting / debug export
/// - JSON-structured log entries with timestamp, level, tag, message, error, stackTrace
/// - Release builds: only warning+ logged to console (verbose/debug/info still buffered)
/// - Debug builds: all levels logged to console via debugPrint
/// - Thread-safe ring buffer for concurrent access
///
/// Usage:
///   AppLogger.info('ChecklistScreen', 'Loaded 5 checklists');
///   AppLogger.error('SyncEngine', 'Pull failed', error: e, stackTrace: st);
///   final logs = AppLogger.getRecentLogs(); // for debug export
class AppLogger {
  AppLogger._();

  static int _bufferSize = 500;
  static LogLevel _minConsoleLevel = kReleaseMode ? LogLevel.warning : LogLevel.verbose;
  static final List<LogEntry> _buffer = [];

  /// ANSI color codes for debug console output (no-ops in release).
  static const _levelColors = {
    LogLevel.verbose: '\x1B[37m',   // white
    LogLevel.debug: '\x1B[36m',     // cyan
    LogLevel.info: '\x1B[32m',      // green
    LogLevel.warning: '\x1B[33m',   // yellow
    LogLevel.error: '\x1B[31m',     // red
    LogLevel.fatal: '\x1B[35m',     // magenta
  };
  static const _reset = '\x1B[0m';

  static const _levelLabels = {
    LogLevel.verbose: 'V',
    LogLevel.debug: 'D',
    LogLevel.info: 'I',
    LogLevel.warning: 'W',
    LogLevel.error: 'E',
    LogLevel.fatal: 'F',
  };

  /// Initialize the logger. Call once at app startup before runApp.
  ///
  /// [minConsoleLevel] — minimum level for console output. Defaults to
  /// [LogLevel.warning] in release, [LogLevel.verbose] in debug.
  /// [bufferSize] — max entries in the ring buffer (default 500).
  static void init({LogLevel? minConsoleLevel, int bufferSize = 500}) {
    _bufferSize = bufferSize;
    if (minConsoleLevel != null) {
      _minConsoleLevel = minConsoleLevel;
    }
  }

  static void verbose(String tag, String message,
      {Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.verbose, tag, message, error: error, stackTrace: stackTrace);
  }

  static void debug(String tag, String message,
      {Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.debug, tag, message, error: error, stackTrace: stackTrace);
  }

  static void info(String tag, String message,
      {Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.info, tag, message, error: error, stackTrace: stackTrace);
  }

  static void warning(String tag, String message,
      {Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.warning, tag, message, error: error, stackTrace: stackTrace);
  }

  static void error(String tag, String message,
      {Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.error, tag, message, error: error, stackTrace: stackTrace);
  }

  static void fatal(String tag, String message,
      {Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.fatal, tag, message, error: error, stackTrace: stackTrace);
  }

  /// Returns a copy of the ring buffer (oldest first).
  static List<LogEntry> getRecentLogs() => List.unmodifiable(_buffer);

  /// Returns the ring buffer contents as a JSON string for export/upload.
  static String getRecentLogsAsJson() {
    final entries = _buffer.map((e) => e.toJson()).toList();
    return jsonEncode(entries);
  }

  /// Clears the ring buffer.
  static void clear() => _buffer.clear();

  static void _log(
    LogLevel level,
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      error: error?.toString(),
      stackTrace: stackTrace?.toString(),
    );

    // Always buffer, regardless of console level.
    _addToBuffer(entry);

    // Console output respects the minimum level.
    if (level.index >= _minConsoleLevel.index) {
      _printToConsole(entry);
    }
  }

  /// FIFO ring buffer — evicts oldest entry when full.
  static void _addToBuffer(LogEntry entry) {
    if (_buffer.length >= _bufferSize) {
      _buffer.removeAt(0);
    }
    _buffer.add(entry);
  }

  /// Print colored output in debug; plain in release (no ANSI codes).
  static void _printToConsole(LogEntry entry) {
    final label = _levelLabels[entry.level] ?? '?';
    final ts = _formatTimestamp(entry.timestamp);

    if (kDebugMode) {
      final color = _levelColors[entry.level] ?? '';
      final line = '$color[$label] $ts [${entry.tag}] ${entry.message}$_reset';
      debugPrint(line);
      if (entry.error != null) {
        debugPrint('$color    error: ${entry.error}$_reset');
      }
      if (entry.stackTrace != null) {
        debugPrint('$color    stackTrace: ${entry.stackTrace}$_reset');
      }
    } else {
      // In release, use print for warning+ (debugPrint is a no-op in release).
      final line = '[$label] $ts [${entry.tag}] ${entry.message}';
      // ignore: avoid_print
      print(line);
      if (entry.error != null) {
        // ignore: avoid_print
        print('    error: ${entry.error}');
      }
    }
  }

  /// Format as HH:mm:ss.SSS for compact console output.
  static String _formatTimestamp(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}.'
        '${dt.millisecond.toString().padLeft(3, '0')}';
  }
}

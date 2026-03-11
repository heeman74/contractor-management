import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/di/service_locator.dart';
import '../../data/job_dao.dart';
import '../../domain/job_entity.dart';

/// GPS capture button for the Job Detail screen's Details tab.
///
/// One-tap: captures device GPS coordinates and stores them in the local
/// Drift DB via [JobDao.updateJobGps]. The backend will reverse-geocode the
/// coordinates and populate [JobEntity.gpsAddress] on the next sync pull.
///
/// Permission flow:
///   - Location services off  → snackbar "Enable location services in Settings"
///   - Permission denied      → requests permission; if still denied, no action
///   - Permission deniedForever → dialog with "Open Settings" button
///   - Existing address       → confirm "Replace existing address?" before capture
///
/// Display below address field:
///   - GPS data unset          → shows only the Capture Location button
///   - lat/lng set, no address → shows "Coordinates: {lat}N {lng}W (address pending sync)"
///   - gpsAddress set          → shows the geocoded address string
class GpsCaptureButton extends ConsumerStatefulWidget {
  /// The current job entity, used to read jobId, existing GPS data.
  final JobEntity job;

  const GpsCaptureButton({required this.job, super.key});

  @override
  ConsumerState<GpsCaptureButton> createState() => _GpsCaptureButtonState();
}

class _GpsCaptureButtonState extends ConsumerState<GpsCaptureButton> {
  bool _isLoading = false;

  // ── Permission helpers ────────────────────────────────────────────────────

  Future<bool> _checkAndRequestPermission() async {
    // 1. Check if location services are enabled.
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enable location services in Settings.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return false;
    }

    // 2. Check existing permission.
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // User dismissed the prompt — do not show any dialog; silently abort.
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        await _showDeniedForeverDialog();
      }
      return false;
    }

    return true;
  }

  Future<void> _showDeniedForeverDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Location Permission Required'),
        content: const Text(
          'ContractorHub needs location access to capture the job site GPS '
          'coordinates. Please enable it in app settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await Geolocator.openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // ── Overwrite guard ───────────────────────────────────────────────────────

  /// Returns true if capture should proceed, false if user cancelled.
  Future<bool> _confirmOverwriteIfNeeded() async {
    final hasExistingAddress = widget.job.gpsAddress != null ||
        (widget.job.gpsLatitude != null && widget.job.gpsLongitude != null);

    if (!hasExistingAddress) return true;
    if (!mounted) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace existing location?'),
        content: const Text(
          'A location is already saved for this job. '
          'Replace it with the current GPS position?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  // ── Capture flow ──────────────────────────────────────────────────────────

  Future<void> _captureLocation() async {
    // Permission check.
    final permitted = await _checkAndRequestPermission();
    if (!permitted) return;

    // Overwrite guard.
    final proceed = await _confirmOverwriteIfNeeded();
    if (!proceed) return;

    setState(() => _isLoading = true);

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final jobDao = getIt<JobDao>();
      await jobDao.updateJobGps(
        jobId: widget.job.id,
        latitude: position.latitude,
        longitude: position.longitude,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location captured. Address will update after sync.'),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('[GpsCaptureButton._captureLocation] Error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to capture location: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // GPS data display
        _GpsDisplay(job: widget.job),
        const SizedBox(height: 8),
        // Capture button
        ElevatedButton.icon(
          icon: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.my_location),
          label: Text(_isLoading ? 'Getting location...' : 'Capture Location'),
          onPressed: _isLoading ? null : _captureLocation,
        ),
      ],
    );
  }
}

// ─── GPS display ──────────────────────────────────────────────────────────────

/// Displays the current GPS state below the address field.
///
/// - If gpsAddress is set: shows the geocoded address.
/// - If only lat/lng are set: shows "Coordinates: {lat}N {lng}W (address pending sync)".
/// - If no GPS data: renders nothing.
class _GpsDisplay extends StatelessWidget {
  final JobEntity job;

  const _GpsDisplay({required this.job});

  @override
  Widget build(BuildContext context) {
    if (job.gpsAddress != null) {
      return _GpsRow(
        icon: Icons.place,
        text: job.gpsAddress!,
      );
    }

    if (job.gpsLatitude != null && job.gpsLongitude != null) {
      final lat = job.gpsLatitude!;
      final lng = job.gpsLongitude!;
      final latStr =
          '${lat.abs().toStringAsFixed(5)}${lat >= 0 ? 'N' : 'S'}';
      final lngStr =
          '${lng.abs().toStringAsFixed(5)}${lng >= 0 ? 'E' : 'W'}';

      return _GpsRow(
        icon: Icons.gps_not_fixed,
        text: 'Coordinates: $latStr $lngStr (address pending sync)',
        italic: true,
      );
    }

    return const SizedBox.shrink();
  }
}

class _GpsRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool italic;

  const _GpsRow({
    required this.icon,
    required this.text,
    this.italic = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontStyle: italic ? FontStyle.italic : FontStyle.normal,
                ),
          ),
        ),
      ],
    );
  }
}

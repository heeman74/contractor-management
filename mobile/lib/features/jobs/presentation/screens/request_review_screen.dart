import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/routing/route_names.dart';
import '../../../../features/auth/domain/auth_state.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../domain/job_request_entity.dart';
import '../providers/crm_providers.dart';

/// Admin review queue for incoming job requests.
///
/// Watches [pendingRequestsNotifierProvider] for reactive updates — any change
/// to the Drift [JobRequests] table is reflected immediately (offline-first).
///
/// Per request, three actions are available:
///   1. **Accept** — POST /api/v1/jobs/requests/{id}/review with action='accepted'.
///      On success, navigate to the job wizard pre-filled with the created job data.
///      Backend handles the atomic job creation + request status update.
///   2. **Decline** — POST with action='declined', decline_reason, decline_message.
///   3. **Request Info** — POST with action='info_requested'.
///
/// Requests are sorted oldest-first (highest review priority).
/// Empty state shows a checkmark — no pending requests to review.
class RequestReviewScreen extends ConsumerWidget {
  const RequestReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final companyId =
        authState is AuthAuthenticated ? authState.companyId : '';

    final requestsAsync =
        ref.watch(pendingRequestsNotifierProvider(companyId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Requests'),
        backgroundColor:
            Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      body: requestsAsync.when(
        data: (requests) {
          // Oldest first = highest review priority (context decision)
          final sorted = List<JobRequestEntity>.from(requests)
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

          if (sorted.isEmpty) {
            return const _EmptyRequestsState();
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: sorted.length,
            itemBuilder: (context, index) {
              final request = sorted[index];
              return _RequestCard(request: request);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              Text('Failed to load requests: $error'),
            ],
          ),
        ),
      ),
    );
  }
}

/// Request card with Accept / Decline / Request Info actions.
class _RequestCard extends ConsumerWidget {
  final JobRequestEntity request;

  const _RequestCard({required this.request});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final isUrgent = request.urgency == 'urgent';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: urgency badge + date
            Row(
              children: [
                if (isUrgent)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'URGENT',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                        fontSize: 11,
                      ),
                    ),
                  ),
                const Spacer(),
                Text(
                  _formatDate(request.createdAt),
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Client name (from CRM profile or submitted anonymously)
            Text(
              request.submittedName ?? request.clientId ?? 'Unknown client',
              style:
                  textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),

            // Description
            Text(
              request.description,
              style: textTheme.bodyMedium,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),

            // Trade type + preferred dates
            Wrap(
              spacing: 8,
              children: [
                if (request.tradeType != null)
                  _InfoChip(
                    icon: Icons.build_outlined,
                    label: request.tradeType!,
                  ),
                if (request.preferredDateStart != null)
                  _InfoChip(
                    icon: Icons.calendar_today_outlined,
                    label: _formatDate(request.preferredDateStart!),
                  ),
                if (request.budgetMin != null || request.budgetMax != null)
                  _InfoChip(
                    icon: Icons.attach_money,
                    label: _formatBudget(
                        request.budgetMin, request.budgetMax),
                  ),
              ],
            ),

            // Photo thumbnails (placeholder grid)
            if (request.photos.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 60,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount:
                      request.photos.length > 5 ? 5 : request.photos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 4),
                  itemBuilder: (context, index) => Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                      image: DecorationImage(
                        image: NetworkImage(request.photos[index]),
                        fit: BoxFit.cover,
                        onError: (_, __) {},
                      ),
                    ),
                    child: const Icon(Icons.image_outlined, size: 24),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _showInfoRequestedDialog(context, ref),
                  icon: const Icon(Icons.help_outline, size: 16),
                  label: const Text('Request Info'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.orange,
                  ),
                ),
                const SizedBox(width: 4),
                OutlinedButton.icon(
                  onPressed: () => _showDeclineDialog(context, ref),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Decline'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _showAcceptDialog(context, ref),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Accept'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Accept ───────────────────────────────────────────────────────────────

  void _showAcceptDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Accept Request'),
        content: Text(
          'Accept this request from '
          '${request.submittedName ?? request.clientId ?? 'the client'}? '
          'A new job will be created and you\'ll be taken to the job wizard '
          'to complete the setup.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _acceptRequest(context, ref);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  Future<void> _acceptRequest(BuildContext context, WidgetRef ref) async {
    final dioClient = getIt<DioClient>();

    try {
      // POST to backend — backend atomically creates the Job and updates request status.
      // Do NOT create the job client-side (CONTEXT.md locked decision).
      final response = await dioClient.instance.post<dynamic>(
        '/jobs/requests/${request.id}/review',
        data: {'action': 'accepted'},
      );

      if (!context.mounted) return;

      // Extract created job data from response for wizard pre-fill.
      final responseData = response.data;
      String? createdJobDescription;
      String? createdJobTradeType;
      String? createdJobClientId;
      String? createdJobId;

      if (responseData is Map<String, dynamic>) {
        // Backend returns {request: {...}, job: {...}} on accept
        final jobData = responseData['job'];
        if (jobData is Map<String, dynamic>) {
          createdJobId = jobData['id'] as String?;
          createdJobDescription = jobData['description'] as String?;
          createdJobTradeType = jobData['trade_type'] as String?;
          createdJobClientId = jobData['client_id'] as String?;
        }
      }

      // Navigate to the pre-filled job wizard (Steps 3-4: contractor + schedule).
      // Using go() with query params — wizard reads them in initState.
      final params = {
        if (createdJobId != null) 'jobId': createdJobId,
        if (createdJobClientId != null) 'clientId': createdJobClientId,
        if (createdJobDescription != null) 'description': createdJobDescription,
        if (createdJobTradeType != null) 'tradeType': createdJobTradeType,
      };

      final queryString = params.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');

      context.go('${RouteNames.jobNew}${queryString.isNotEmpty ? '?$queryString' : ''}');
    } on DioException catch (e) {
      if (!context.mounted) return;
      final statusCode = e.response?.statusCode;
      final message = switch (statusCode) {
        401 => 'Not authorised. Please log in again.',
        403 => 'You do not have permission to accept requests.',
        404 => 'Request not found — it may have already been reviewed.',
        422 => 'Invalid request data. Please contact support.',
        final code when code != null && code >= 500 =>
          'Server error. Please try again.',
        _ => 'Failed to accept request. Please try again.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unexpected error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ── Decline ──────────────────────────────────────────────────────────────

  static const _declineReasons = [
    'Outside service area',
    'Fully booked',
    'Service not offered',
    'Budget too low',
    'Duplicate request',
    'Other',
  ];

  void _showDeclineDialog(BuildContext context, WidgetRef ref) {
    String selectedReason = _declineReasons.first;
    final messageController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Decline Request'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Reason for declining:'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedReason,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
                items: _declineReasons
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => selectedReason = v);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: messageController,
                decoration: const InputDecoration(
                  labelText: 'Optional message to client',
                  hintText: 'Add any details for the client…',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _declineRequest(
                  context,
                  ref,
                  reason: selectedReason,
                  message: messageController.text.isEmpty
                      ? null
                      : messageController.text,
                );
              },
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Decline'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _declineRequest(
    BuildContext context,
    WidgetRef ref, {
    required String reason,
    String? message,
  }) async {
    final dioClient = getIt<DioClient>();

    try {
      await dioClient.instance.post<dynamic>(
        '/jobs/requests/${request.id}/review',
        data: {
          'action': 'declined',
          'decline_reason': reason,
          if (message != null) 'decline_message': message,
        },
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request declined')),
      );
    } on DioException catch (e) {
      if (!context.mounted) return;
      final statusCode = e.response?.statusCode;
      final msg = statusCode != null && statusCode >= 500
          ? 'Server error. Please try again.'
          : 'Failed to decline request.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unexpected error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ── Request Info ─────────────────────────────────────────────────────────

  void _showInfoRequestedDialog(BuildContext context, WidgetRef ref) {
    final messageController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request More Information'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ask the client to provide more details before you can review.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: messageController,
              decoration: const InputDecoration(
                labelText: 'Message to client',
                hintText: 'What information do you need?',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _requestMoreInfo(
                context,
                ref,
                message: messageController.text.isEmpty
                    ? null
                    : messageController.text,
              );
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestMoreInfo(
    BuildContext context,
    WidgetRef ref, {
    String? message,
  }) async {
    final dioClient = getIt<DioClient>();

    try {
      await dioClient.instance.post<dynamic>(
        '/jobs/requests/${request.id}/review',
        data: {
          'action': 'info_requested',
          if (message != null) 'message': message,
        },
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Information requested from client')),
      );
    } on DioException catch (e) {
      if (!context.mounted) return;
      final statusCode = e.response?.statusCode;
      final msg = statusCode != null && statusCode >= 500
          ? 'Server error. Please try again.'
          : 'Failed to send request.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unexpected error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _formatDate(DateTime date) =>
      '${date.day}/${date.month}/${date.year}';

  String _formatBudget(double? min, double? max) {
    if (min != null && max != null) {
      return '\$${min.toStringAsFixed(0)} – \$${max.toStringAsFixed(0)}';
    } else if (min != null) {
      return 'From \$${min.toStringAsFixed(0)}';
    } else if (max != null) {
      return 'Up to \$${max.toStringAsFixed(0)}';
    }
    return 'No budget range';
  }
}

// ─── Info chip ────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyRequestsState extends StatelessWidget {
  const _EmptyRequestsState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 80,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 24),
            const Text(
              'No pending requests',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'All incoming job requests have been reviewed. '
              'New requests will appear here when clients submit them.',
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

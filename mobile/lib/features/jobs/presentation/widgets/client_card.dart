import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/client_profile_entity.dart';
import '../../domain/job_entity.dart';
import '../../domain/job_status.dart';

/// Inline expandable card for a single client in the CRM list.
///
/// Per CONTEXT.md locked decision — inline expansion (not navigation) for
/// quick scanning without context switches. Tap to expand/collapse.
///
/// Collapsed state: client name, email, phone, average rating, job count.
/// Expanded state: recent jobs (last 3), saved properties count, tags,
///   admin notes preview, referral source, preferred contractor.
///
/// Action buttons:
/// - "View Full Profile" — navigates to ClientDetailScreen
/// - "Create Job" — navigates to job wizard pre-filled with this client
class ClientCard extends StatefulWidget {
  final ClientProfileEntity profile;

  /// Display name for this client (from User entity — shown as email fallback
  /// until full user join is available).
  final String displayName;

  /// Email address for collapsed header display.
  final String? email;

  /// Phone number for collapsed header display.
  final String? phone;

  /// Count of jobs associated with this client.
  final int jobCount;

  /// Recent jobs for expanded view (up to 3).
  final List<JobEntity> recentJobs;

  /// Count of saved properties for this client.
  final int savedPropertyCount;

  /// Called when "View Full Profile" is tapped.
  final VoidCallback? onViewProfile;

  /// Called when "Create Job" is tapped.
  final VoidCallback? onCreateJob;

  const ClientCard({
    super.key,
    required this.profile,
    required this.displayName,
    this.email,
    this.phone,
    required this.jobCount,
    required this.recentJobs,
    required this.savedPropertyCount,
    this.onViewProfile,
    this.onCreateJob,
  });

  @override
  State<ClientCard> createState() => _ClientCardState();
}

class _ClientCardState extends State<ClientCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Collapsed header — always visible ──
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar with initials
                  CircleAvatar(
                    backgroundColor:
                        colorScheme.primaryContainer,
                    foregroundColor: colorScheme.onPrimaryContainer,
                    child: Text(
                      widget.displayName.isNotEmpty
                          ? widget.displayName[0].toUpperCase()
                          : '?',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Name, email, phone
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.displayName,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (widget.email != null)
                          Text(
                            widget.email!,
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        if (widget.phone != null)
                          Text(
                            widget.phone!,
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Rating + job count
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (widget.profile.averageRating != null) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star,
                              size: 16,
                              color: Colors.amber[700],
                            ),
                            const SizedBox(width: 2),
                            Text(
                              widget.profile.averageRating!
                                  .toStringAsFixed(1),
                              style: textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        '${widget.jobCount} job${widget.jobCount == 1 ? '' : 's'}',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded content — animated ──
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tags row
                      if (widget.profile.tags.isNotEmpty) ...[
                        _SectionLabel(label: 'Tags'),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: widget.profile.tags
                              .map(
                                (tag) => Chip(
                                  label: Text(tag),
                                  padding: EdgeInsets.zero,
                                  labelPadding:
                                      const EdgeInsets.symmetric(horizontal: 6),
                                  visualDensity: VisualDensity.compact,
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Admin notes preview
                      if (widget.profile.adminNotes != null &&
                          widget.profile.adminNotes!.isNotEmpty) ...[
                        _SectionLabel(label: 'Admin Notes'),
                        const SizedBox(height: 4),
                        Text(
                          widget.profile.adminNotes!,
                          style: textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Referral source
                      if (widget.profile.referralSource != null) ...[
                        _SectionLabel(label: 'Referral Source'),
                        const SizedBox(height: 4),
                        Text(
                          widget.profile.referralSource!,
                          style: textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Saved properties count
                      if (widget.savedPropertyCount > 0) ...[
                        _SectionLabel(label: 'Saved Properties'),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.savedPropertyCount} saved address${widget.savedPropertyCount == 1 ? '' : 'es'}',
                          style: textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Recent jobs (last 3)
                      if (widget.recentJobs.isNotEmpty) ...[
                        _SectionLabel(label: 'Recent Jobs'),
                        const SizedBox(height: 4),
                        ...widget.recentJobs.take(3).map(
                              (job) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  children: [
                                    _StatusChip(status: job.jobStatus),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        job.description,
                                        style: textTheme.bodySmall,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),

                // Action buttons
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: widget.onViewProfile,
                        icon: const Icon(Icons.person_outline, size: 16),
                        label: const Text('View Profile'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: widget.onCreateJob,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Create Job'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small bold label used as a section header inside the expanded card.
class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
    );
  }
}

/// Small status badge for job rows in the expanded section.
class _StatusChip extends StatelessWidget {
  final JobStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      JobStatus.quote => (Colors.grey, 'Quote'),
      JobStatus.scheduled => (Colors.blue, 'Scheduled'),
      JobStatus.inProgress => (Colors.orange, 'In Progress'),
      JobStatus.complete => (Colors.green, 'Complete'),
      JobStatus.invoiced => (Colors.purple, 'Invoiced'),
      JobStatus.cancelled => (Colors.red, 'Cancelled'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

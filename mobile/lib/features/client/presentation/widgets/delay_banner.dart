import 'package:flutter/material.dart';

/// Orange/amber warning banner displayed when a job has delay entries.
///
/// Shows the latest delay by default: reason text and original vs new ETA
/// comparison. When multiple delays exist, an expandable section shows prior
/// delay history.
///
/// [delayEntries] should be pre-filtered from [JobEntity.statusHistory]
/// where entry['type'] == 'delay'. Pass an empty list to hide the banner.
class DelayBanner extends StatefulWidget {
  final List<Map<String, dynamic>> delayEntries;

  const DelayBanner({required this.delayEntries, super.key});

  @override
  State<DelayBanner> createState() => _DelayBannerState();
}

class _DelayBannerState extends State<DelayBanner> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.delayEntries.isEmpty) return const SizedBox.shrink();

    // Latest delay is the last entry (chronological order).
    final latest = widget.delayEntries.last;
    final previousDelays = widget.delayEntries.length > 1
        ? widget.delayEntries
            .sublist(0, widget.delayEntries.length - 1)
            .reversed
            .toList()
        : <Map<String, dynamic>>[];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Latest delay entry
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.amber.shade800, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Delay Reported',
                      style: TextStyle(
                        color: Colors.amber.shade800,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (latest['reason'] != null)
                  Text(
                    latest['reason'] as String,
                    style: TextStyle(
                      color: Colors.amber.shade900,
                      fontSize: 13,
                    ),
                  ),
                const SizedBox(height: 4),
                _EtaComparison(entry: latest),
              ],
            ),
          ),

          // "View previous delays" expandable section
          if (previousDelays.isNotEmpty) ...[
            const Divider(height: 1),
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.amber.shade700,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _expanded
                          ? 'Hide previous delays'
                          : 'View previous delays (${previousDelays.length})',
                      style: TextStyle(
                        color: Colors.amber.shade800,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded)
              Padding(
                padding:
                    const EdgeInsets.only(left: 12, right: 12, bottom: 12),
                child: Column(
                  children: previousDelays
                      .map(
                        (entry) => Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (entry['reason'] != null)
                                Text(
                                  entry['reason'] as String,
                                  style: TextStyle(
                                    color: Colors.amber.shade900,
                                    fontSize: 12,
                                  ),
                                ),
                              _EtaComparison(entry: entry),
                              const Divider(height: 12),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Shows "Original ETA: X → New ETA: Y" for a single delay entry.
///
/// [entry] is a status history map with keys: new_eta, original_eta (optional),
/// timestamp.
class _EtaComparison extends StatelessWidget {
  final Map<String, dynamic> entry;

  const _EtaComparison({required this.entry});

  @override
  Widget build(BuildContext context) {
    final newEta = entry['new_eta'] as String?;
    final originalEta = entry['original_eta'] as String?;
    final timestamp = entry['timestamp'] as String?;

    String dateLabel = '';
    if (timestamp != null) {
      try {
        final dt = DateTime.parse(timestamp).toLocal();
        dateLabel =
            '${dt.day}/${dt.month}/${dt.year}';
      } catch (e) {
        debugPrint('[DelayBanner] Invalid timestamp format: $e');
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (originalEta != null && newEta != null)
          RichText(
            text: TextSpan(
              style: TextStyle(color: Colors.amber.shade900, fontSize: 12),
              children: [
                const TextSpan(text: 'Original ETA: '),
                TextSpan(
                  text: originalEta,
                  style: const TextStyle(
                      decoration: TextDecoration.lineThrough),
                ),
                const TextSpan(text: '  →  New ETA: '),
                TextSpan(
                  text: newEta,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          )
        else if (newEta != null)
          Text(
            'New ETA: $newEta',
            style: TextStyle(
              color: Colors.amber.shade900,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        if (dateLabel.isNotEmpty)
          Text(
            'Reported $dateLabel',
            style: TextStyle(color: Colors.amber.shade700, fontSize: 11),
          ),
      ],
    );
  }
}

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Google Places Autocomplete field with debounced type-ahead suggestions.
///
/// Uses a standalone [Dio] instance (not the app's authenticated [DioClient])
/// since Google APIs don't need the app's auth tokens.
class AddressAutocompleteField extends StatefulWidget {
  const AddressAutocompleteField({
    required this.controller,
    super.key,
    this.decoration,
    this.onChanged,
  });

  final TextEditingController controller;
  final InputDecoration? decoration;
  final ValueChanged<String>? onChanged;

  @override
  State<AddressAutocompleteField> createState() =>
      _AddressAutocompleteFieldState();
}

class _AddressAutocompleteFieldState extends State<AddressAutocompleteField> {
  final _dio = Dio();
  final _focusNode = FocusNode();
  final _apiKey = dotenv.get('GOOGLE_PLACES_API_KEY', fallback: '');
  Timer? _debounce;
  List<_PlaceSuggestion> _suggestions = [];
  bool _isLoading = false;
  bool _suppressSearch = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _dio.close();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      // Delay clearing so tap on suggestion registers first.
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) setState(() => _suggestions = []);
      });
    }
  }

  void _onTextChanged(String input) {
    widget.onChanged?.call(input);
    _suppressSearch = false;
    _debounce?.cancel();

    if (input.trim().length < 3 || _apiKey.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!_suppressSearch) _fetchSuggestions(input.trim());
    });
  }

  Future<void> _fetchSuggestions(String input) async {
    setState(() => _isLoading = true);

    try {
      // Uses Places API (New) — POST with JSON body.
      final response = await _dio.post<Map<String, dynamic>>(
        'https://places.googleapis.com/v1/places:autocomplete',
        options: Options(headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,
        }),
        data: {
          'input': input,
          'includedRegionCodes': ['us'],
          'includedPrimaryTypes': [
            'street_address',
            'subpremise',
            'route',
          ],
        },
      );

      final data = response.data;
      if (data == null) {
        if (mounted) setState(() => _suggestions = []);
        return;
      }

      final suggestions = data['suggestions'];
      if (suggestions is! List) {
        if (mounted) setState(() => _suggestions = []);
        return;
      }

      if (mounted) {
        setState(() {
          _suggestions = suggestions
              .whereType<Map<String, dynamic>>()
              .where((s) => s['placePrediction'] is Map<String, dynamic>)
              .map((s) {
            final prediction = s['placePrediction'] as Map<String, dynamic>;
            final text = prediction['text'] as Map<String, dynamic>?;
            return _PlaceSuggestion(
              placeId: prediction['placeId'] as String? ?? '',
              description: text?['text'] as String? ?? '',
            );
          }).toList();
        });
      }
    } on DioException catch (e) {
      debugPrint('Places API error: ${e.message}');
      if (mounted) setState(() => _suggestions = []);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSuggestionTap(_PlaceSuggestion suggestion) {
    _suppressSearch = true;
    widget.controller.text = suggestion.description;
    widget.onChanged?.call(suggestion.description);
    setState(() => _suggestions = []);
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          controller: widget.controller,
          focusNode: _focusNode,
          decoration: (widget.decoration ?? const InputDecoration()).copyWith(
            suffixIcon: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          textInputAction: TextInputAction.next,
          onChanged: _onTextChanged,
        ),
        if (_suggestions.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(top: 4),
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final suggestion = _suggestions[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_on, size: 20),
                    title: Text(
                      suggestion.description,
                      style: const TextStyle(fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _onSuggestionTap(suggestion),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _PlaceSuggestion {
  const _PlaceSuggestion({
    required this.placeId,
    required this.description,
  });

  final String placeId;
  final String description;
}

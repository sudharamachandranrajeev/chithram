import 'package:flutter/material.dart';

import '../../theme.dart';

/// Side margin of every phone page.
const phoneGutter = 16.0;

/// A text field for the system keyboard, with a search button. Submitting from
/// the keyboard ("search" action) or tapping the button runs [onSearch].
class PhoneSearchBar extends StatelessWidget {
  const PhoneSearchBar({
    super.key,
    required this.controller,
    required this.hint,
    required this.onSearch,
    this.autofocus = false,
    this.fieldKey = const ValueKey('search-field'),
    this.goKey = const ValueKey('search-go'),
  });

  final TextEditingController controller;
  final String hint;
  final void Function(String text) onSearch;

  /// Raise the keyboard when the page opens (a search page opened on its own).
  final bool autofocus;
  final Key fieldKey;
  final Key goKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(phoneGutter, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => TextField(
                key: fieldKey,
                controller: controller,
                autofocus: autofocus,
                textInputAction: TextInputAction.search,
                keyboardType: TextInputType.text,
                onSubmitted: onSearch,
                decoration: InputDecoration(
                  hintText: hint,
                  filled: true,
                  fillColor: ChithramColors.surface,
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: controller.clear,
                        ),
                ),
              ),
            ),
          ),
          IconButton(
            key: goKey,
            tooltip: 'Search',
            icon: const Icon(Icons.arrow_forward_rounded),
            onPressed: () => onSearch(controller.text),
          ),
        ],
      ),
    );
  }
}

/// A small heading above a group of rows.
class PhoneSectionTitle extends StatelessWidget {
  const PhoneSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(phoneGutter, 16, phoneGutter, 4),
    child: Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: ChithramColors.accent)),
    ),
  );
}

/// A line of dim explanatory text.
class PhoneNote extends StatelessWidget {
  const PhoneNote(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: phoneGutter, vertical: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color ?? ChithramColors.textDim),
    ),
  );
}

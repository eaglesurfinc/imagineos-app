import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Typed words belong to the creator. Never autocorrect or truncate them.
class StoryWordsField extends StatelessWidget {
  const StoryWordsField(
      {super.key,
      required this.controller,
      required this.label,
      required this.helper,
      required this.onChanged,
      required this.maxLength,
      this.minLines = 1});
  final TextEditingController controller;
  final String label, helper;
  final ValueChanged<String> onChanged;
  final int maxLength, minLines;
  @override
  Widget build(BuildContext context) => Semantics(
      container: true,
      child: TextField(
          controller: controller,
          minLines: minLines,
          maxLines: null,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.none,
          maxLength: maxLength,
          maxLengthEnforcement: MaxLengthEnforcement.none,
          decoration: InputDecoration(
              labelText: label, helperText: helper, helperMaxLines: 4),
          onChanged: onChanged));
}

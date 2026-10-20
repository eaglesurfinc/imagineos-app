import 'package:flutter/material.dart';

import 'drawing_selection.dart';

class DrawingSelectionToolbar extends StatelessWidget {
  const DrawingSelectionToolbar(
      {super.key,
      required this.count,
      required this.busy,
      required this.hasArea,
      required this.onDeselect,
      required this.onDelete,
      required this.onResize,
      required this.onReorder,
      required this.onKeepArea});
  final int count;
  final bool busy, hasArea;
  final VoidCallback onDeselect, onDelete, onKeepArea;
  final ValueChanged<double> onResize;
  final ValueChanged<DrawingLayerOrder> onReorder;

  @override
  Widget build(BuildContext context) => Material(
      color: const Color(0xffe1f4f8),
      child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight:
                  (MediaQuery.sizeOf(context).height * .22).clamp(80, 180)),
          child: SingleChildScrollView(
              primary: false,
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(count == 0
                            ? 'Area selected'
                            : '$count ${count == 1 ? 'item' : 'items'} selected'),
                        if (count > 0) ...[
                          TextButton.icon(
                              onPressed: busy ? null : () => onResize(1 / 1.2),
                              icon: const Icon(Icons.zoom_out),
                              label: const Text('Smaller')),
                          TextButton.icon(
                              onPressed: busy ? null : () => onResize(1.2),
                              icon: const Icon(Icons.zoom_in),
                              label: const Text('Larger')),
                          for (final action in const {
                            DrawingLayerOrder.backward: 'Send backward',
                            DrawingLayerOrder.forward: 'Bring forward',
                            DrawingLayerOrder.back: 'Send to back',
                            DrawingLayerOrder.front: 'Bring to front',
                          }.entries)
                            TextButton(
                                onPressed:
                                    busy ? null : () => onReorder(action.key),
                                child: Text(action.value)),
                        ],
                        TextButton.icon(
                            onPressed: busy ? null : onDelete,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Delete selection')),
                        if (hasArea)
                          TextButton(
                              onPressed: busy ? null : onKeepArea,
                              child: const Text('Keep only selection')),
                        TextButton(
                            onPressed: busy ? null : onDeselect,
                            child: const Text('Deselect')),
                      ])))));
}

import 'package:flutter/material.dart';

Future<void> showPenSetup(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
            scrollable: true,
            title: const Text('Connect your drawing pen'),
            content: const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '1. Check that your pen is compatible with this tablet or drawing display. Charge it if needed.'),
                  SizedBox(height: 12),
                  Text(
                      '2. Follow the pen maker’s pairing steps. For Bluetooth models, open your device Settings → Bluetooth (or Bluetooth & devices), turn Bluetooth on, and pair the pen. Some pens need a cable, magnetic attachment, or no Bluetooth pairing.'),
                  SizedBox(height: 12),
                  Text(
                      '3. Return here and draw on the canvas. “Pen input received” confirms that the app is receiving pen strokes. The percentage shows pressure reported by your device.'),
                  SizedBox(height: 12),
                  Text(
                      'Turn on Pen only to avoid finger marks while drawing. Fingers can still move the canvas; two fingers zoom. An eraser tip works when the device reports it.'),
                  SizedBox(height: 12),
                  Text(
                      'Pairing is managed by your device. This page cannot scan your system’s paired pens or confirm a Bluetooth connection. If strokes appear as touch or mouse input, check the pen, tablet and browser compatibility. Bluetooth pairing alone does not add pen support to an incompatible screen.'),
                ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Return and test pen'))
            ]));

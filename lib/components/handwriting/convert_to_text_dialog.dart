import 'package:flutter/material.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/handwriting/handwriting_recognizer.dart';
import 'package:saber/i18n/strings.g.dart';

enum ConvertToTextAction { copy, replace }

typedef ConvertToTextResult = ({ConvertToTextAction action, String text});

/// Recognizes the handwriting in [strokes] and shows the text,
/// which can be edited, then copied or used to replace the strokes.
class ConvertToTextDialog extends StatefulWidget {
  const new({super.key, required this.strokes});

  final List<Stroke> strokes;

  @override
  State<ConvertToTextDialog> createState() => _ConvertToTextDialogState();
}

class _ConvertToTextDialogState extends State<ConvertToTextDialog> {
  final controller = TextEditingController();
  var recognizing = true;

  @override
  void initState() {
    super.initState();
    HandwritingRecognizer.instance.recognize(widget.strokes).then((text) {
      if (!mounted) return;
      setState(() {
        controller.text = text;
        recognizing = false;
      });
    });
  }

  void _pop(ConvertToTextAction action) => Navigator.pop<ConvertToTextResult>(
    context,
    (action: action, text: controller.text),
  );

  @override
  Widget build(BuildContext context) {
    final hasText = !recognizing && controller.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(t.handwriting.convert.convertToText),
      content: SizedBox(
        width: 400,
        child: recognizing
            ? Row(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(width: 24),
                  Expanded(child: Text(t.handwriting.convert.recognizing)),
                ],
              )
            : TextField(
                controller: controller,
                autofocus: true,
                minLines: 1,
                maxLines: 8,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: t.handwriting.convert.nothingRecognized,
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.common.cancel),
        ),
        TextButton(
          onPressed: hasText ? () => _pop(.copy) : null,
          child: Text(t.handwriting.convert.copy),
        ),
        FilledButton(
          onPressed: hasText ? () => _pop(.replace) : null,
          child: Text(t.handwriting.convert.replace),
        ),
      ],
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

import 'package:flutter/material.dart';
import 'package:saber/data/handwriting/handwriting_recognizer.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';

/// Turns on handwriting recognition, asking before the language model
/// is downloaded.
abstract final class HandwritingSetup {
  /// Returns whether handwriting recognition is turned on and ready,
  /// asking the user to turn it on (and download the model) if needed.
  static Future<bool> ensureEnabled(BuildContext context) async {
    final recognizer = HandwritingRecognizer.instance;
    if (!recognizer.isSupported) return false;
    if (stows.handwritingRecognition.value &&
        await recognizer.isModelDownloaded()) {
      return true;
    }
    if (!context.mounted) return false;

    final ready = await ensureModel(context);
    stows.handwritingRecognition.value = ready;
    return ready;
  }

  /// Makes sure the language model is downloaded,
  /// asking the user before downloading it.
  ///
  /// Returns whether the model is ready.
  static Future<bool> ensureModel(BuildContext context) async {
    final recognizer = HandwritingRecognizer.instance;
    if (!recognizer.isSupported) return false;
    if (await recognizer.isModelDownloaded()) return true;
    if (!context.mounted) return false;

    final download = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.handwriting.setup.title),
        content: Text(t.handwriting.setup.description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.handwriting.setup.download),
          ),
        ],
      ),
    );
    if (download != true || !context.mounted) return false;

    final downloaded = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DownloadDialog(recognizer: recognizer),
    );
    if (downloaded != true && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(t.handwriting.setup.downloadFailed)),
      );
    }
    return downloaded ?? false;
  }
}

class _DownloadDialog extends StatefulWidget {
  const new({required this.recognizer});

  final HandwritingRecognizer recognizer;

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  @override
  void initState() {
    super.initState();
    widget.recognizer.downloadModel().then((success) {
      if (mounted) Navigator.pop(context, success);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Row(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 24),
          Expanded(child: Text(t.handwriting.setup.downloading)),
        ],
      ),
    );
  }
}

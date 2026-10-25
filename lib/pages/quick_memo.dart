import 'package:flutter/cupertino.dart' show CupertinoLocalizations;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:intl/intl.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/i18n/extensions/redirecting_localization_delegate.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

/// A quick memo, which Android can show over the lock screen
/// (like Samsung's Screen Off Memo), see `QuickMemoActivity.kt`.
///
/// It only creates a new memo: other notes can't be seen or opened from
/// here, so nothing is revealed while the device is locked.
class QuickMemoApp extends StatelessWidget {
  const new({super.key});

  /// A dark theme, so the memo looks like writing on a screen that's off.
  static final theme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.white,
      brightness: .dark,
    ).copyWith(surface: Colors.black),
    scaffoldBackgroundColor: Colors.black,
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: t.quickMemo.title,
      theme: theme,
      locale: TranslationProvider.of(context).flutterLocale,
      supportedLocales: AppLocaleUtils.supportedLocales,
      localizationsDelegates: const [
        RedirectingLocalizationDelegate<CupertinoLocalizations>(
          GlobalCupertinoLocalizations.delegate,
        ),
        RedirectingLocalizationDelegate<MaterialLocalizations>(
          GlobalMaterialLocalizations.delegate,
        ),
        RedirectingLocalizationDelegate<WidgetsLocalizations>(
          GlobalWidgetsLocalizations.delegate,
        ),
        RedirectingLocalizationDelegate<FlutterQuillLocalizations>(
          FlutterQuillLocalizations.delegate,
        ),
      ],
      home: const QuickMemoPage(),
    );
  }
}

/// Creates a new memo in [folder] and shows it in a restricted editor.
class QuickMemoPage extends StatefulWidget {
  const new({super.key, this.close = SystemNavigator.pop});

  /// Closes the quick memo (on Android, finishes the activity so the
  /// lock screen is shown again).
  final Future<void> Function() close;

  /// The folder that memos are saved in.
  static const folder = '/Quick memos';

  /// A new, unique path for a memo, e.g. "/Quick memos/Memo 25-10-26 09.41".
  static Future<String> newMemoPath() async {
    final name = 'Memo ${DateFormat('yy-MM-dd HH.mm').format(DateTime.now())}';
    await FileManager.createFolder(folder);
    return FileManager.suffixFilePathToMakeItUnique('$folder/$name');
  }

  @override
  State<QuickMemoPage> createState() => _QuickMemoPageState();
}

class _QuickMemoPageState extends State<QuickMemoPage> {
  late final _path = QuickMemoPage.newMemoPath();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _path,
      builder: (context, snapshot) {
        final path = snapshot.data;
        if (path == null) {
          return const Scaffold(backgroundColor: Colors.black);
        }
        return Editor(
          path: path,
          customTitle: t.quickMemo.title,
          quickMemo: true,
          onQuickMemoDone: widget.close,
        );
      },
    );
  }
}

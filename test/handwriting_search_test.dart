import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/canvas_gesture_detector.dart';
import 'package:saber/components/home/note_search.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/handwriting/handwriting_index.dart';
import 'package:saber/data/handwriting/handwriting_indexer.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:sbn/tool_id.dart';

import 'utils/fake_handwriting_recognizer.dart';
import 'utils/test_mock_channel_handlers.dart';

void main() {
  FlavorConfig.setup();

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('handwriting_index'));
  tearDown(() => dir.deleteSync(recursive: true));
  File indexFile() => File('${dir.path}/handwriting_index.json');

  group('IndexedPage.signatureOf', () {
    test('changes when the handwriting changes', () {
      final a = _word(const Offset(10, 10));
      final b = _word(const Offset(10, 50));
      expect(
        IndexedPage.signatureOf([a]),
        IndexedPage.signatureOf([_word(const Offset(10, 10))]),
        reason: 'Same strokes, same signature',
      );
      expect(
        IndexedPage.signatureOf([a]),
        isNot(IndexedPage.signatureOf([a, b])),
      );
    });

    test('ignores strokes that are not handwriting', () {
      final a = _word(const Offset(10, 10));
      final highlight = _word(const Offset(10, 10), toolId: .highlighter);
      expect(
        IndexedPage.signatureOf([a, highlight]),
        IndexedPage.signatureOf([a]),
      );
    });
  });

  group('HandwritingIndex', () {
    test('search finds pages and shows a snippet', () {
      final index = HandwritingIndex(file: indexFile())
        ..setPages('/maths', const [
          IndexedPage(signature: 1, text: 'nothing here'),
          IndexedPage(
            signature: 2,
            text:
                'the derivative of\nsin x is cos x, which is easy to '
                'remember once you have seen the unit circle',
          ),
        ])
        ..setPages('/shopping', const [
          IndexedPage(signature: 3, text: 'Cosmetics'),
        ]);

      final results = index.search('COS');
      expect(results, hasLength(2));
      final maths = results.firstWhere((r) => r.filePath == '/maths');
      expect(maths.pageIndex, 1);
      expect(maths.snippet, endsWith('…'));
      expect(maths.snippet, contains('sin x is cos x'));
      expect(maths.snippet, isNot(contains('\n')));
      expect(index.search('   '), isEmpty);
    });

    test('save and load', () async {
      final index = HandwritingIndex(file: indexFile())
        ..setPages('/note', const [IndexedPage(signature: 42, text: 'hi')]);
      await index.save();

      final loaded = HandwritingIndex(file: indexFile());
      await loaded.load();
      expect(loaded.pagesOf('/note')?.single.text, 'hi');
      expect(loaded.pagesOf('/note')?.single.signature, 42);

      await loaded.clear();
      expect(indexFile().existsSync(), isFalse);
    });

    test('a corrupt index file starts over', () async {
      indexFile().writeAsStringSync('not json');
      final index = HandwritingIndex(file: indexFile());
      await index.load();
      expect(index.filePaths, isEmpty);
    });
  });

  group('HandwritingIndexer', () {
    late Map<String, List<List<Stroke>>> notes;
    late FakeHandwritingRecognizer recognizer;
    late StreamController<FileOperation> fileOperations;
    late HandwritingIndexer indexer;

    setUp(() {
      notes = {
        '/a': [
          [_word(const Offset(10, 10))],
          [_word(const Offset(10, 10)), _word(const Offset(10, 100))],
        ],
        '/b': [[]],
      };
      recognizer = FakeHandwritingRecognizer(
        textForLine: (line) => 'word at ${line.first.centerline.first.dy}',
      );
      fileOperations = StreamController.broadcast();
      indexer = HandwritingIndexer(
        index: HandwritingIndex(file: indexFile()),
        recognizer: recognizer,
        loadNote: (filePath) async {
          final coreInfo = EditorCoreInfo(filePath: filePath);
          for (final strokes in notes[filePath] ?? const <List<Stroke>>[]) {
            final page = EditorPage();
            for (final stroke in strokes) {
              page.strokes.add(stroke.copy()..page = page);
            }
            coreInfo.pages.add(page);
          }
          return coreInfo;
        },
        fileOperations: fileOperations.stream,
        getAllNotes: () async => notes.keys.toList(),
        debounce: Duration.zero,
      );
    });
    tearDown(() async {
      await indexer.stop();
      await fileOperations.close();
    });

    test('indexes all notes when started', () async {
      await indexer.start();
      await indexer.idle;

      final pages = indexer.index.pagesOf('/a')!;
      expect(pages.map((page) => page.text), [
        'word at 10.0',
        'word at 10.0\nword at 100.0',
      ]);
      expect(indexer.index.pagesOf('/b')!.single.text, '');
      expect(indexer.index.search('100').single.pageIndex, 1);
    });

    test('only changed pages are recognized again', () async {
      await indexer.start();
      await indexer.idle;
      final linesRecognized = recognizer.recognizedLines.length;

      // add a word to the first page of /a
      notes['/a']![0].add(_word(const Offset(10, 200)));
      fileOperations.add(const FileOperation(.write, '/a'));
      await pumpEventQueue();
      await indexer.idle;

      // only the 2 lines of the changed page are recognized
      expect(recognizer.recognizedLines.length - linesRecognized, 2);
      expect(indexer.index.search('200').single.pageIndex, 0);
    });

    test('assets are ignored and deleted notes are removed', () async {
      await indexer.start();
      await indexer.idle;
      final linesRecognized = recognizer.recognizedLines.length;

      fileOperations.add(const FileOperation(.write, '/a.sbn2.p'));
      fileOperations.add(const FileOperation(.write, '/a.sbn2.0'));
      await pumpEventQueue();
      await indexer.idle;
      expect(recognizer.recognizedLines.length, linesRecognized);

      fileOperations.add(const FileOperation(.delete, '/a'));
      await pumpEventQueue();
      expect(indexer.index.pagesOf('/a'), isNull);
    });

    test('stopping clears the index', () async {
      await indexer.start();
      await indexer.idle;
      await indexer.index.save();
      expect(indexFile().existsSync(), isTrue);

      await indexer.stop(clearIndex: true);
      expect(indexer.index.filePaths, isEmpty);
      expect(indexFile().existsSync(), isFalse);
    });
  });

  testWidgets('Search shows note names and handwriting matches', (
    tester,
  ) async {
    FileManager.documentsDirectory =
        '$tmpDir/handwriting_search_test/'
        '${FileManager.appRootDirectoryPrefix}';
    stows.handwritingRecognition.value = true;
    addTearDown(() => stows.handwritingRecognition.value = false);

    final indexer = HandwritingIndexer(
      index: HandwritingIndex(file: indexFile())
        ..setPages('/Biology', const [
          IndexedPage(signature: 1, text: ''),
          IndexedPage(signature: 2, text: 'mitochondria is the powerhouse'),
        ]),
      recognizer: FakeHandwritingRecognizer(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showSearch(
                context: context,
                delegate: NoteSearch(
                  indexer: indexer,
                  getAllNotes: () async => ['/Biology', '/Power plants'],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'power');
    await tester.pumpAndSettle();

    expect(find.text('Power plants'), findsOneWidget, reason: 'Name match');
    expect(find.text('Biology'), findsOneWidget, reason: 'Handwriting match');
    expect(
      find.textContaining('Page 2 · mitochondria is the powerhouse'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'xyz');
    await tester.pumpAndSettle();
    expect(find.text('No results'), findsOneWidget);

    // let the index's delayed save finish
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('Opening a search result scrolls to its page', (tester) async {
    FileManager.documentsDirectory =
        '$tmpDir/handwriting_search_page_test/'
        '${FileManager.appRootDirectoryPrefix}';
    const filePath = '/three pages';
    final coreInfo = EditorCoreInfo(filePath: filePath)
      ..pages.addAll([EditorPage(), EditorPage(), EditorPage()]);
    for (final page in coreInfo.pages) {
      page.strokes.add(_word(const Offset(10, 10))..page = page);
    }
    final (bson, _) = coreInfo.saveToBinary(currentPageIndex: 0);
    await tester.runAsync(
      () => FileManager.writeFile(
        filePath + Editor.extension,
        bson,
        awaitWrite: true,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: Editor(path: filePath, initialPageIndex: 2)),
    );
    final state = tester.state<EditorState>(find.byType(Editor));
    addTearDown(state.cancelAutosaveAndMarkSaved);
    // wait for the note to load
    for (var i = 0; i < 50 && state.coreInfo.filePath.isEmpty; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(state.coreInfo.initialPageIndex, 2);
    await tester.pump();
    // the top of the third page is just below the top of the screen
    final topOfPage = CanvasGestureDetector.getTopOfPage(
      pageIndex: 2,
      pages: state.coreInfo.pages,
      screenWidth:
          tester.view.physicalSize.width / tester.view.devicePixelRatio,
    );
    expect(-state.scrollY, closeTo(topOfPage - 50, 1));
  });
}

/// A small scribble 60 wide and 20 tall, starting at [topLeft].
Stroke _word(Offset topLeft, {ToolId toolId = .fountainPen}) =>
    Stroke(
      color: Colors.black,
      pressureEnabled: false,
      options: StrokeOptions(size: 2, isComplete: true),
      pageIndex: 0,
      page: EditorPage(),
      toolId: toolId,
    )..addPoints([
      for (var i = 0; i <= 12; ++i)
        topLeft + Offset(i * 5.0, i.isEven ? 0 : 20),
    ]);

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:player_flutter/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('media library groups videos by folder', () {
    const sourceId = 'source';
    const items = [
      MediaItem(
        id: '$sourceId:/media/低智商犯罪/01~4K.mp4',
        sourceId: sourceId,
        sourceName: '低智商犯罪',
        type: SourceType.local,
        title: '01~4K',
        uri: '/media/低智商犯罪/01~4K.mp4',
        folderTitle: '低智商犯罪',
      ),
      MediaItem(
        id: '$sourceId:/media/低智商犯罪/02~4K.mp4',
        sourceId: sourceId,
        sourceName: '低智商犯罪',
        type: SourceType.local,
        title: '02~4K',
        uri: '/media/低智商犯罪/02~4K.mp4',
        folderTitle: '低智商犯罪',
      ),
    ];

    final groups = mediaFolderGroups(items);

    expect(groups, hasLength(1));
    expect(groups.single.title, '低智商犯罪');
    expect(groups.single.items, hasLength(2));
  });

  test('extracts explicit TMDB id from folder or file names', () {
    expect(explicitTmdbIdFromText('Friends tmdb-1668'), 1668);
    expect(explicitTmdbIdFromText('Friends TMDBID=1668'), 1668);
    expect(explicitTmdbIdFromText('Movie tmdbid-550 1080p'), 550);
    expect(explicitTmdbIdFromText('Movie tmdb=550 1080p'), 550);

    const item = MediaItem(
      id: 'source:/TV/Friends tmdb-1668/Season 1/S01E21.mkv',
      sourceId: 'source',
      sourceName: 'source',
      type: SourceType.local,
      title: 'S01E21',
      uri: '/TV/Friends tmdb-1668/Season 1/S01E21.mkv',
      folderTitle: 'Season 1',
    );

    expect(explicitTmdbId(item), 1668);
  });

  test('uses series folder when video is inside a season folder', () {
    const item = MediaItem(
      id: 'source:C:/media/Low IQ Crime/Season 1/S01E01.mkv',
      sourceId: 'source',
      sourceName: 'source',
      type: SourceType.local,
      title: 'S01E01',
      uri: 'C:/media/Low IQ Crime/Season 1/S01E01.mkv',
    );

    expect(mediaFolderTitle(item), 'Low IQ Crime');
    expect(mediaGroupDisplayTitle(item), 'Low IQ Crime');
    expect(mediaFolderKey(item), 'source:local:C:/media/Low IQ Crime');
  });

  test('normalizes Chinese titles without dropping them', () {
    expect(
      normalizeMatchText('\u4f4e\u667a\u5546\u72af\u7f6a'),
      '\u4f4e\u667a\u5546\u72af\u7f6a',
    );
    expect(normalizeMatchText('Low.IQ-Crime S01E01'), 'low iq crime s01e01');
  });

  test('normalizes self-hosted tmdb proxy endpoints', () {
    expect(
      normalizeTmdbApiBaseUrl('tmdb.ansky.top'),
      'https://tmdb.ansky.top/3',
    );
    expect(
      normalizeTmdbApiBaseUrl('https://tmdb.ansky.top/'),
      'https://tmdb.ansky.top/3',
    );
    expect(
      tmdbImageBaseUrlForApiBaseUrl('https://tmdb.ansky.top'),
      'https://tmdb.ansky.top/t/p',
    );
    expect(
      const TmdbConfig(apiBaseUrl: 'https://tmdb.ansky.top')
          .toJson()['apiBaseUrl'],
      'https://tmdb.ansky.top/3',
    );
  });

  testWidgets(
      'resource library starts empty and add page only offers supported source types',
      (WidgetTester tester) async {
    final store = AppStore()..loaded = true;

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerShell(store: store),
      ),
    );
    await tester.pump();

    expect(find.text('媒体库'), findsOneWidget);
    expect(find.text('资源库'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);

    await tester.tap(find.text('资源库'));
    await tester.pump();

    expect(find.text('暂无文件源'), findsOneWidget);
    expect(find.text('添加新文件源'), findsOneWidget);
    expect(find.text('本地视频'), findsNothing);
    expect(find.text('我的 WebDAV'), findsNothing);

    await tester.tap(find.byTooltip('添加源'));
    await tester.pumpAndSettle();

    expect(find.text('本地目录'), findsOneWidget);
    expect(find.text('WebDAV'), findsOneWidget);
  });
}

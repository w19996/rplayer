import 'dart:async';

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

  test('single unmatched media group displays file title', () {
    const item = MediaItem(
      id: 'source:/media/Parent/Movie Name.mp4',
      sourceId: 'source',
      sourceName: 'source',
      type: SourceType.local,
      title: 'Movie Name',
      uri: '/media/Parent/Movie Name.mp4',
      folderTitle: 'Parent',
      matchTitle: 'Parent',
      groupPath: '/media/Parent',
    );

    final groups = mediaFolderGroups(const [item]);

    expect(groups.single.title, 'Movie Name');
  });

  test('separates manually selected files in the same folder', () {
    const items = [
      MediaItem(
        id: 'source:/media/Parent/A.mp4',
        sourceId: 'source',
        sourceName: 'source',
        type: SourceType.local,
        title: 'A',
        uri: '/media/Parent/A.mp4',
        folderTitle: 'Parent',
        matchTitle: 'Parent',
        groupPath: '/media/Parent',
      ),
      MediaItem(
        id: 'source:/media/Parent/B.mp4',
        sourceId: 'source',
        sourceName: 'source',
        type: SourceType.local,
        title: 'B',
        uri: '/media/Parent/B.mp4',
        folderTitle: 'Parent',
        matchTitle: 'Parent',
        groupPath: '/media/Parent',
      ),
    ];

    expect(mediaFolderGroups(items), hasLength(1));
    expect(
      mediaFolderGroups(
        items,
        separateItemIds: items.map((item) => item.id).toSet(),
      ),
      hasLength(2),
    );
  });

  test('normalizes webdav folder keys like the database', () {
    const item = MediaItem(
      id: 'source:/media/Show/01.mp4',
      sourceId: 'source',
      sourceName: 'WebDAV',
      type: SourceType.webdav,
      title: '01',
      uri: 'https://example.com/dav/media/Show/01.mp4',
    );

    expect(mediaFolderKey(item), 'source:webdav:/media/Show');
    expect(
      normalizeMediaFolderKey('source:webdav:/dav/media/Show/'),
      'source:webdav:/media/Show',
    );
  });

  test('groups different quality directories under one show folder', () {
    const sourceId = 'source';
    const items = [
      MediaItem(
        id: '$sourceId:/夸克/来自：分享/小城大事/4K HDR/01.mkv',
        sourceId: sourceId,
        sourceName: 'WebDAV',
        type: SourceType.webdav,
        title: '01',
        uri: 'https://example.com/dav/夸克/来自：分享/小城大事/4K%20HDR/01.mkv',
        folderTitle: '小城大事',
        matchTitle: '小城大事',
        groupPath: '夸克/来自：分享/小城大事',
        versionName: '4K HDR',
        versionDirPath: '夸克/来自：分享/小城大事/4K HDR',
      ),
      MediaItem(
        id: '$sourceId:/夸克/来自：分享/小城大事/4K DV杜比视界 高码率/01.mkv',
        sourceId: sourceId,
        sourceName: 'WebDAV',
        type: SourceType.webdav,
        title: '01',
        uri: 'https://example.com/dav/夸克/来自：分享/小城大事/4K%20DV杜比视界%20高码率/01.mkv',
        folderTitle: '小城大事',
        matchTitle: '小城大事',
        groupPath: '夸克/来自：分享/小城大事',
        versionName: '4K DV杜比视界 高码率',
        versionDirPath: '夸克/来自：分享/小城大事/4K DV杜比视界 高码率',
      ),
    ];

    final groups = mediaFolderGroups(items);

    expect(groups, hasLength(1));
    expect(groups.single.key, 'source:webdav:/夸克/来自：分享/小城大事');
    expect(groups.single.title, '小城大事');
    expect(groups.single.items, hasLength(2));
  });

  test('filters version and episode noise from TMDB search queries', () {
    expect(tmdbSearchQueryFromText('01'), '');
    expect(
      tmdbSearchQueryFromText(
        'S01E01.2026.2160p.WEB-DL.HQ.H265.25fps.10bit.AAC',
      ),
      '',
    );
    expect(
      tmdbSearchQueryFromText('.2026.2160p.WEB-DL.HQ.H265.25fps.10bit.AAC'),
      '',
    );
    expect(tmdbSearchQueryFromText('1080P 内封简繁英字幕'), '');
    expect(
      tmdbSearchQueryFromText('去有风的地方（2023）全40集 内封字幕 4K+1080P'),
      '去有风的地方',
    );
    expect(
      tmdbSearchQueryFromText('X 喜羊羊与灰太狼之古古怪界有古怪'),
      '喜羊羊与灰太狼之古古怪界有古怪',
    );
    expect(tmdbSearchQueryFromText('Q 去有风的地方'), '去有风的地方');
    expect(isUsefulTmdbSearchQuery('简繁字幕'), isFalse);
    expect(isUsefulTmdbSearchQuery('第3章 CMake主要语法'), isFalse);
  });

  test('tmdb auto-match failed item key changes when file changes', () {
    const item = MediaItem(
      id: 'source:/media/Show/01.mp4',
      sourceId: 'source',
      sourceName: 'source',
      type: SourceType.local,
      title: '01',
      uri: '/media/Show/01.mp4',
      folderTitle: 'Show',
      matchTitle: 'Show',
      season: 1,
      episode: 1,
      mediaKind: 'TvEpisode',
      groupPath: '/media/Show',
      size: 100,
    );

    expect(
      tmdbAutoMatchItemFingerprint(item),
      isNot(equals(tmdbAutoMatchItemFingerprint(item.copyWith(size: 200)))),
    );
    expect(
      tmdbAutoMatchFailedItemKey(item),
      tmdbAutoMatchFailedItemKey(
        item.copyWith(
          folderTitle: 'Other',
          matchTitle: 'Other',
          groupPath: '/media/Other',
        ),
      ),
    );
    expect(
      tmdbAutoMatchFailedItemKey(item),
      isNot(equals(tmdbAutoMatchFailedItemKey(item.copyWith(size: 200)))),
    );
  });

  test('webdav parent removal covers descendant selections', () {
    final source = MediaSourceConfig.webdav(
      id: 'source',
      name: 'WebDAV',
      baseUrl: 'https://example.com/dav',
      username: '',
      password: '',
      directory: '/',
      selectedPaths: const [
        '/Shows/A/',
        '/Shows/B/01.mp4',
        '/Other/C/',
      ],
    );

    expect(
      selectedPathsCoveredBy(source, '/Shows/'),
      {'/Shows/A/', '/Shows/B/01.mp4'},
    );
  });

  test('imports database folder orientation keys for playback lookup', () {
    final store = AppStore();
    store.importMediaStateJson(const {
      'folderOrientations': {
        'source:webdav:/dav/media/Show/': 'landscape',
      },
    });
    const item = MediaItem(
      id: 'source:/media/Show/01.mp4',
      sourceId: 'source',
      sourceName: 'WebDAV',
      type: SourceType.webdav,
      title: '01',
      uri: 'https://example.com/dav/media/Show/01.mp4',
    );

    expect(store.folderOrientations[mediaFolderKey(item)], 'landscape');
  });

  test('normalizes Chinese titles without dropping them', () {
    expect(
      normalizeMatchText('\u4f4e\u667a\u5546\u72af\u7f6a'),
      '\u4f4e\u667a\u5546\u72af\u7f6a',
    );
    expect(normalizeMatchText('Low.IQ-Crime S01E01'), 'low iq crime s01e01');
  });

  test('uses one media category policy for TMDB type and genres', () {
    expect(
      mediaCategoryLabel(mediaCategoryKey(
        mediaType: 'tv',
        tmdbType: 'Reality',
        genres: const ['Comedy'],
      )),
      '\u7efc\u827a',
    );
    expect(
      mediaCategoryLabel(mediaCategoryKey(
        mediaType: 'tv',
        tmdbType: 'Talk Show',
        genres: const [],
      )),
      '\u8bbf\u8c08',
    );
    expect(
      mediaCategoryLabel(mediaCategoryKey(
        mediaType: 'tv',
        tmdbType: 'Scripted',
        genres: const ['Animation'],
      )),
      '\u52a8\u6f2b',
    );
    expect(
      mediaCategoryLabel(mediaCategoryKey(
        mediaType: 'movie',
        genres: const ['\u52a8\u753b'],
      )),
      '\u52a8\u6f2b',
    );
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

  test('treats cached tv episode metadata as complete without still image', () {
    final store = AppStore();
    const item = MediaItem(
      id: 'source:/Shows/Example/S01E02.mkv',
      sourceId: 'source',
      sourceName: 'source',
      type: SourceType.local,
      title: 'S01E02',
      uri: '/Shows/Example/S01E02.mkv',
      folderTitle: 'Example',
      season: 1,
      episode: 2,
      mediaKind: 'TvEpisode',
    );
    final metadata = MediaMetadata(
      itemId: item.id,
      tmdbId: 100,
      mediaType: 'tv',
      title: 'Example',
      posterPath: '/poster.jpg',
      episodeTmdbId: 2002,
      episodeName: 'Episode 2',
      schemaVersion: currentMetadataSchemaVersion,
    );

    expect(store.metadataCompleteForItem(item, metadata), isTrue);
  });

  test('treats persisted season episode list as complete metadata', () {
    final store = AppStore();
    const item = MediaItem(
      id: 'source:/Shows/Example/S01E03.mkv',
      sourceId: 'source',
      sourceName: 'source',
      type: SourceType.local,
      title: 'S01E03',
      uri: '/Shows/Example/S01E03.mkv',
      folderTitle: 'Example',
      season: 1,
      episode: 3,
      mediaKind: 'TvEpisode',
    );
    final metadata = MediaMetadata(
      itemId: item.id,
      tmdbId: 100,
      mediaType: 'tv',
      title: 'Example',
      posterPath: '/poster.jpg',
      seasonEpisodes: [
        {'seasonNumber': 1, 'episodeNumber': 3},
      ],
      schemaVersion: currentMetadataSchemaVersion,
    );

    expect(store.metadataCompleteForItem(item, metadata), isTrue);
  });

  test('rescan keeps current items until replacement scan completes', () async {
    final scanner = _BlockingScanner();
    final source = MediaSourceConfig.local(
      id: 'source',
      name: 'source',
      directory: '/media',
    ).copyWith(selectedPaths: const ['/media']);
    const item = MediaItem(
      id: 'source:/media/Show/01.mp4',
      sourceId: 'source',
      sourceName: 'source',
      type: SourceType.local,
      title: '01',
      uri: '/media/Show/01.mp4',
    );
    final store = AppStore(scanner: scanner)
      ..sources.add(source)
      ..items.add(item)
      ..rebuildItemIndex();

    final rescan = store.rescanAll();
    await scanner.started.future.timeout(const Duration(seconds: 1));

    expect(store.items.single.id, item.id);

    scanner.release.complete();
    await expectLater(rescan, throwsA(isA<StateError>()));
    expect(store.items.single.id, item.id);
  });

  test('normalizes danmu api endpoints', () {
    expect(
      normalizeDanmuApiBaseUrl('danmu.example.com/87654321/api/v2/'),
      'https://danmu.example.com',
    );
    expect(
      normalizeDanmuApiBaseUrl('https://danmu.example.com/api/v2'),
      'https://danmu.example.com',
    );
    expect(
      buildDanmuRequestBaseUrl('https://danmu.example.com', '87654321'),
      'https://danmu.example.com',
    );
    final config = DanmuConfig.fromJson(const {
      'enabled': true,
      'apiBaseUrl': 'https://danmu.example.com/87654321/api/v2',
      'maxLines': 10,
      'topPadding': 36,
    });
    expect(config.normalizedApiBaseUrl, 'https://danmu.example.com');
    expect(config.normalizedApiToken, '87654321');
    expect(config.maxLines, 10);
    expect(config.topPadding, 36);
    expect(config.toJson()['maxLines'], 10);
    expect(config.toJson()['topPadding'], 36);
    expect(
      const DanmuConfig(
        enabled: true,
        apiBaseUrl: 'https://danmu.example.com',
        apiToken: '87654321',
      ).requestBaseUrl,
      'https://danmu.example.com',
    );
  });

  test('does not resume playback from the end', () {
    expect(resumablePlaybackPositionMs(10558777, 10558777), 0);
    expect(resumablePlaybackPositionMs(10556000, 10558777), 0);
    expect(resumablePlaybackPositionMs(60000, 10558777), 60000);
    expect(resumablePlaybackPositionMs(60000, 0), 60000);
  });

  test('single selected file uses filename for unmatched TMDB lookup', () {
    final source = MediaSourceConfig.local(
      id: 'source',
      name: 'source',
      directory: '/media',
    ).copyWith(selectedPaths: const ['/media/Folder/Movie Name.mp4']);
    const item = MediaItem(
      id: 'source:/media/Folder/Movie Name.mp4',
      sourceId: 'source',
      sourceName: 'source',
      type: SourceType.local,
      title: 'Movie Name',
      uri: '/media/Folder/Movie Name.mp4',
      folderTitle: 'Folder',
      matchTitle: 'Folder',
      groupPath: '/media/Folder',
    );
    final group = MediaFolderGroup(
      key: mediaFolderKey(item),
      title: 'Folder',
      items: const [item],
      representative: item,
      latestPlayedAt: 0,
    );
    final store = AppStore()..sources.add(source);

    final lookupGroup = store.tmdbLookupGroup(group);

    expect(itemExplicitlySelectedFile(source, item), isTrue);
    expect(lookupGroup.title, 'Movie Name');
    expect(lookupGroup.representative.matchTitle, 'Movie Name');

    final cachedGroup = store.tmdbLookupGroup(
      group,
      cachedTitle: MediaMetadata(
        itemId: item.id,
        tmdbId: 1,
        mediaType: 'movie',
        title: 'Folder Match',
        schemaVersion: currentMetadataSchemaVersion,
      ),
    );
    expect(cachedGroup.title, 'Folder');
    expect(cachedGroup.representative.matchTitle, 'Folder');
  });

  test('single selected webdav file uses filename for unmatched TMDB lookup',
      () {
    final source = MediaSourceConfig.webdav(
      id: 'source',
      name: 'WebDAV',
      baseUrl: 'https://example.com/dav',
      username: '',
      password: '',
      directory: '/',
      selectedPaths: const ['/本机/001 Qt环境搭建.ts'],
    );
    const item = MediaItem(
      id: 'source:/本机/001 Qt环境搭建.ts',
      sourceId: 'source',
      sourceName: 'WebDAV',
      type: SourceType.webdav,
      title: '001 Qt环境搭建',
      uri:
          'https://example.com/dav/%E6%9C%AC%E6%9C%BA/001%20Qt%E7%8E%AF%E5%A2%83%E6%90%AD%E5%BB%BA.ts',
      folderTitle: '本机',
      matchTitle: '本机',
      groupPath: '/本机',
    );
    final group = MediaFolderGroup(
      key: mediaFolderKey(item),
      title: '本机',
      items: const [item],
      representative: item,
      latestPlayedAt: 0,
    );
    final store = AppStore()..sources.add(source);

    final lookupGroup = store.tmdbLookupGroup(group);

    expect(itemExplicitlySelectedFile(source, item), isTrue);
    expect(lookupGroup.title, '001 Qt环境搭建');
    expect(lookupGroup.representative.matchTitle, '001 Qt环境搭建');
  });

  test('single restored webdav file uses filename when folder was restored',
      () {
    final source = MediaSourceConfig.webdav(
      id: 'source',
      name: 'WebDAV',
      baseUrl: 'https://example.com/dav',
      username: '',
      password: '',
      directory: '/',
      selectedPaths: const ['/本机/'],
    );
    const item = MediaItem(
      id: 'source:/本机/001 Qt环境搭建.ts',
      sourceId: 'source',
      sourceName: 'WebDAV',
      type: SourceType.webdav,
      title: '001 Qt环境搭建',
      uri:
          'https://example.com/dav/%E6%9C%AC%E6%9C%BA/001%20Qt%E7%8E%AF%E5%A2%83%E6%90%AD%E5%BB%BA.ts',
      folderTitle: '本机',
      matchTitle: '本机',
      groupPath: '/本机',
    );
    final group = MediaFolderGroup(
      key: mediaFolderKey(item),
      title: '本机',
      items: const [item],
      representative: item,
      latestPlayedAt: 0,
    );
    final store = AppStore()..sources.add(source);

    final lookupGroup = store.tmdbLookupGroup(group);

    expect(itemExplicitlySelectedFile(source, item), isFalse);
    expect(lookupGroup.title, '001 Qt环境搭建');
    expect(lookupGroup.representative.matchTitle, '001 Qt环境搭建');
  });

  test('only persists confirmed playback progress', () {
    expect(
      shouldPersistPlaybackProgress(
        ready: false,
        positionConfirmed: true,
        positionMs: 60000,
      ),
      isFalse,
    );
    expect(
      shouldPersistPlaybackProgress(
        ready: true,
        positionConfirmed: false,
        positionMs: 60000,
      ),
      isFalse,
    );
    expect(
      shouldPersistPlaybackProgress(
        ready: true,
        positionConfirmed: true,
        positionMs: 0,
      ),
      isFalse,
    );
    expect(
      shouldPersistPlaybackProgress(
        ready: true,
        positionConfirmed: true,
        positionMs: 60000,
      ),
      isTrue,
    );
  });

  test('builds danmu match filename with tmdb episode hints', () {
    expect(
      buildDanmuMatchFileName(
        title: '宝莲灯',
        sourceFileName: '24 4K.mp4',
        season: 1,
        episode: 1,
      ),
      '宝莲灯.S01E01',
    );
    expect(
      buildDanmuMatchFileNames(
        title: '无忧渡',
        sourceFileName: '08 4K.mkv',
        season: 2,
        episode: 8,
      ),
      ['无忧渡.S02E08', '08 4K.mkv'],
    );
    expect(
      buildDanmuMatchFileNames(
        title: '无忧渡',
        sourceFileName: '无忧渡.S02E08.1080p.WEB-DL.mkv',
        season: 2,
        episode: 8,
      ),
      ['无忧渡.S02E08', '无忧渡.S02E08.1080p.WEB-DL.mkv'],
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

  testWidgets('added source browser uses a pop guard',
      (WidgetTester tester) async {
    final store = AppStore()
      ..sources.add(MediaSourceConfig.local(
        id: 'source',
        name: 'source',
        directory: '/media',
      ));

    await tester.pumpWidget(MaterialApp(
      home:
          AddedSourceSelectionsPage(store: store, source: store.sources.first),
    ));

    expect(
      find.byWidgetPredicate(
        (widget) => widget is PopScope<void> && widget.canPop,
      ),
      findsOneWidget,
    );
  });
}

class _BlockingScanner extends MediaScanService {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Stream<MediaItem> scanSourceStream(MediaSourceConfig source) async* {
    started.complete();
    await release.future;
    throw StateError('scan stopped');
  }
}

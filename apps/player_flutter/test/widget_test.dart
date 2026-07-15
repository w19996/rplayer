import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:player_flutter/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory testAppFilesDir;

  setUp(() async {
    testAppFilesDir =
        await Directory.systemTemp.createTemp('player_flutter_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appChannel, (call) async {
      if (call.method == 'appFilesDir') return testAppFilesDir.path;
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appChannel, null);
    if (await testAppFilesDir.exists()) {
      await testAppFilesDir.delete(recursive: true);
    }
  });

  test('libmpv remains the compatible default backend', () {
    expect(libmpvCapabilities.supportsNativeDolbyVision, isFalse);
    expect(libmpvCapabilities.supportsAssSubtitles, isTrue);
    expect(libmpvCapabilities.supportsCustomHttpHeaders, isTrue);
    expect(libmpvCapabilities.supportsWebDav, isTrue);
  });

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

  test('recent media keeps only newest item per media group', () {
    const first = MediaItem(
      id: 'source:/media/Show/01.mkv',
      sourceId: 'source',
      sourceName: 'source',
      type: SourceType.local,
      title: '01',
      uri: '/media/Show/01.mkv',
      folderTitle: 'Show',
    );
    const second = MediaItem(
      id: 'source:/media/Show/02.mkv',
      sourceId: 'source',
      sourceName: 'source',
      type: SourceType.local,
      title: '02',
      uri: '/media/Show/02.mkv',
      folderTitle: 'Show',
    );
    const other = MediaItem(
      id: 'source:/media/Other/01.mkv',
      sourceId: 'source',
      sourceName: 'source',
      type: SourceType.local,
      title: '01',
      uri: '/media/Other/01.mkv',
      folderTitle: 'Other',
    );
    const firstRecent = LibraryRecentEntry(
      fileId: 1,
      itemId: 'source:/media/Show/01.mkv',
      relativePath: 'Show/01.mkv',
      filename: '01.mkv',
      positionMs: 1000,
      lastPlayedAt: 300,
    );
    const secondRecent = LibraryRecentEntry(
      fileId: 2,
      itemId: 'source:/media/Show/02.mkv',
      relativePath: 'Show/02.mkv',
      filename: '02.mkv',
      positionMs: 1000,
      lastPlayedAt: 200,
    );
    const otherRecent = LibraryRecentEntry(
      fileId: 3,
      itemId: 'source:/media/Other/01.mkv',
      relativePath: 'Other/01.mkv',
      filename: '01.mkv',
      positionMs: 1000,
      lastPlayedAt: 100,
    );
    const staleRecent = LibraryRecentEntry(
      fileId: 4,
      itemId: 'missing',
      relativePath: 'Missing/01.mkv',
      filename: '01.mkv',
      positionMs: 1000,
      lastPlayedAt: 400,
    );
    final store = AppStore()
      ..addOrReplaceItem(first)
      ..addOrReplaceItem(second)
      ..addOrReplaceItem(other);

    expect(
      filterRecentByMediaGroup(
        store,
        const [staleRecent, firstRecent, secondRecent, otherRecent],
      ),
      [firstRecent, otherRecent],
    );
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

  test('infers episode from generic EP tokens', () {
    for (final entry in const {
      'A-B-EP68': 68,
      'Show.E126.1080p': 126,
      'name-ep007': 7,
      'S01E02': 2,
    }.entries) {
      expect(
        inferredEpisodeNumber(MediaItem(
          id: 'source:/media/Show/${entry.key}.mp4',
          sourceId: 'source',
          sourceName: 'source',
          type: SourceType.local,
          title: entry.key,
          uri: '/media/Show/${entry.key}.mp4',
          folderTitle: 'Show',
        )),
        entry.value,
      );
    }
  });

  test('persists custom episode regex settings', () {
    final store = AppStore();

    store.importSettingsJson(const {
      'episodeRegexes': [' ^Part-(\\d+)\$ ', '^Part-(\\d+)\$'],
    });

    expect(store.episodeRegexes, [r'^Part-(\d+)$']);
    expect(
      (jsonDecode(store.exportSettings())
          as Map<String, dynamic>)['episodeRegexes'],
      [r'^Part-(\d+)$'],
    );
  });

  test('persists mpv advanced preset settings', () async {
    final store = AppStore();

    await store.setMpvAdvancedPreset(mpvAdvancedPresetPower);

    expect(store.mpvAdvancedPreset, mpvAdvancedPresetPower);
    expect(
        store.effectiveMpvAdvancedOptions()['demuxer-max-bytes'], '33554432');

    await store.setMpvAdvancedOption('hr-seek', 'yes');

    expect(store.mpvAdvancedPreset, mpvAdvancedPresetCustom);
    expect(
      (jsonDecode(store.exportSettings())
          as Map<String, dynamic>)['mpvAdvancedPreset'],
      mpvAdvancedPresetCustom,
    );
    expect(
      ((jsonDecode(store.exportSettings())
              as Map<String, dynamic>)['mpvAdvancedOptions']
          as Map<String, dynamic>)['hr-seek'],
      'yes',
    );
    expect(
      mpvAdvancedOptions(
        preset: mpvAdvancedPresetAuto,
        deviceClass: AppDeviceClass.mobile,
        softwareDecoderFallback: false,
      )['hwdec'],
      'mediacodec,mediacodec-copy,no',
    );
    expect(
      mpvAdvancedOptions(
        preset: mpvAdvancedPresetCompat,
        deviceClass: AppDeviceClass.mobile,
        softwareDecoderFallback: false,
        forceHardwareDecoder: true,
      )['hwdec'],
      'mediacodec,mediacodec-copy,no',
    );
  });

  test('documents every mpv advanced option', () {
    for (final spec in mpvAdvancedOptionSpecs) {
      expect(spec.description.trim(), isNotEmpty, reason: spec.key);
    }
  });

  test('persists player backend preference', () async {
    final store = AppStore();

    await store.setPlayerBackendPreference(
      PlayerBackendPreference.nativeForDolbyVisionOnly,
    );
    final exported = jsonDecode(store.exportSettings()) as Map<String, dynamic>;
    final restored = AppStore()..importSettingsJson(exported);

    expect(
      restored.playerBackendPreference,
      PlayerBackendPreference.nativeForDolbyVisionOnly,
    );
  });

  test('mpv video metadata distinguishes normal and Dolby Vision tracks',
      () async {
    Future<String> normal(String property) async =>
        {
          'track-list/count': '2',
          'track-list/0/type': 'video',
          'track-list/0/dolby-vision-profile': '',
          'track-list/1/type': 'audio',
        }[property] ??
        '';
    Future<String> dolby(String property) async =>
        {
          'track-list/count': '2',
          'track-list/0/type': 'audio',
          'track-list/1/type': 'video',
          'track-list/1/dolby-vision-profile': '5',
        }[property] ??
        '';

    expect(
      (await readMpvMediaInfo(normal)).dolbyVisionProfile,
      isNull,
    );
    expect(
      await readMpvMediaInfo(dolby),
      isA<MediaInfo>()
          .having((value) => value.isDolbyVision, 'isDolbyVision', true)
          .having((value) => value.dolbyVisionProfile, 'profile', 5),
    );
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

  test('webdav video covers fetch one queued remote frame', () async {
    final id = DateTime.now().microsecondsSinceEpoch;
    final store = AppStore();
    final dir = await Directory.systemTemp.createTemp('rplayer-cover-test-');
    var thumbnailCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appChannel, (call) async {
      if (call.method == 'appFilesDir') return dir.path;
      if (call.method == 'videoThumbnail') {
        thumbnailCalls++;
        expect((call.arguments as Map<dynamic, dynamic>)['remote'], true);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return Uint8List.fromList([1, 2, 3]);
      }
      throw MissingPluginException();
    });
    final item = MediaItem(
      id: 'source:/media/Parent/Movie-$id.mp4',
      sourceId: 'source',
      sourceName: 'WebDAV',
      type: SourceType.webdav,
      title: 'Movie',
      uri: 'https://example.com/dav/Parent/Movie-$id.mp4',
      folderTitle: 'Parent',
    );

    final results = await Future.wait([
      store.videoCoverBytes(item),
      store.videoCoverBytes(item),
    ]);

    expect(results[0], [1, 2, 3]);
    expect(results[1], [1, 2, 3]);
    expect(thumbnailCalls, 1);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appChannel, null);
    await dir.delete(recursive: true);
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

  test('manual series path overrides title grouping and keeps child versions',
      () {
    final source = MediaSourceConfig.local(
      id: 'source',
      name: 'source',
      directory: '/media',
    ).copyWith(
      selectedPaths: const ['/media/Manual Show'],
      seriesPaths: const ['/media/Manual Show'],
    );
    const item = MediaItem(
      id: 'source:/media/Manual Show/4K/01.mp4',
      sourceId: 'source',
      sourceName: 'source',
      type: SourceType.local,
      title: '01',
      uri: '/media/Manual Show/4K/01.mp4',
      folderTitle: '4K',
      matchTitle: '01',
      groupPath: '/media/Manual Show/4K',
    );

    final manual = applyManualSeriesPath(source, item);

    expect(manual.folderTitle, 'Manual Show');
    expect(manual.matchTitle, 'Manual Show');
    expect(manual.mediaKind, 'TvEpisode');
    expect(manual.groupPath, '/media/Manual Show');
    expect(manual.versionName, '4K');
    expect(manual.versionDirPath, '/media/Manual Show/4K');
    expect(manual.manualSeries, isTrue);
    expect(mediaFolderKey(manual), 'source:local:/media/Manual Show');
    expect(source.toJson()['seriesPaths'], ['/media/Manual Show']);
  });

  test('manual series changes tmdb retry identity', () {
    const item = MediaItem(
      id: 'source:/media/Course/Chapter 01/001.mp4',
      sourceId: 'source',
      sourceName: 'source',
      type: SourceType.local,
      title: '001',
      uri: '/media/Course/Chapter 01/001.mp4',
      folderTitle: 'Chapter 01',
      matchTitle: '001',
      groupPath: '/media/Course/Chapter 01',
      size: 100,
    );
    final manual = item.copyWith(
      folderTitle: 'Course',
      matchTitle: 'Course',
      groupPath: '/media/Course',
      manualSeries: true,
    );

    expect(
      tmdbAutoMatchItemFingerprint(item),
      isNot(tmdbAutoMatchItemFingerprint(manual)),
    );
    expect(
      tmdbAutoMatchFailedItemKey(item),
      isNot(tmdbAutoMatchFailedItemKey(manual)),
    );
    expect(
      tmdbAutoMatchFailedItemKey(item),
      equals(tmdbAutoMatchFailedItemKey(item.copyWith(title: '002'))),
    );
  });

  test('reads previous TMDB auto-match failures', () {
    expect(
      tmdbAutoMatchFailedItems(const {
        'failedItems': ['a', 'b', 1, 'a'],
      }),
      {'a', 'b'},
    );
    expect(tmdbAutoMatchFailedItems(null), isEmpty);
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
      isNot(equals(tmdbAutoMatchFailedItemKey(item.copyWith(size: 200)))),
    );
    expect(
      tmdbAutoMatchFailedItemKey(item),
      equals(tmdbAutoMatchFailedItemKey(item.copyWith(title: '02'))),
    );
    expect(
      tmdbAutoMatchFailedItemKey(item),
      isNot(equals(tmdbAutoMatchFailedItemKey(item.copyWith(
        matchTitle: 'Other',
        groupPath: '/media/Other',
      )))),
    );
    expect(
      tmdbAutoMatchFailedItemKey(item),
      isNot(equals(tmdbAutoMatchFailedItemKey(item.copyWith(
        manualSeries: true,
      )))),
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

  test('library entry removal prefers explicitly selected single file', () {
    final source = MediaSourceConfig.local(
      id: 'source',
      name: 'source',
      directory: '/media',
    ).copyWith(
      selectedPaths: const ['/media/Parent/Movie.mp4', '/media/Parent/'],
    );
    const item = MediaItem(
      id: 'source:/media/Parent/Movie.mp4',
      sourceId: 'source',
      sourceName: 'source',
      type: SourceType.local,
      title: 'Movie',
      uri: '/media/Parent/Movie.mp4',
      folderTitle: 'Parent',
    );
    const entry = LibraryHomeEntry(
      folderId: 1,
      sourceId: 'source',
      folderPath: '/media/Parent',
      itemId: 'source:/media/Parent/Movie.mp4',
      showId: 1,
      tmdbId: 1,
      title: 'Movie',
      localFileCount: 1,
    );
    final store = AppStore()
      ..sources.add(source)
      ..addOrReplaceItem(item);

    expect(libraryEntryRemovePath(store, source, entry),
        '/media/Parent/Movie.mp4');
  });

  test('multi-file library entry removal uses covering folder', () {
    final source = MediaSourceConfig.local(
      id: 'source',
      name: 'source',
      directory: '/media',
    ).copyWith(
      selectedPaths: const ['/media/Show/03.mp4', '/media/Show'],
    );
    const item = MediaItem(
      id: 'source:/media/Show/03.mp4',
      sourceId: 'source',
      sourceName: 'source',
      type: SourceType.local,
      title: '03',
      uri: '/media/Show/03.mp4',
      folderTitle: 'Show',
    );
    const entry = LibraryHomeEntry(
      folderId: 1,
      sourceId: 'source',
      folderPath: '/media/Show',
      itemId: 'source:/media/Show/03.mp4',
      showId: 1,
      tmdbId: 1,
      title: 'Show',
      localFileCount: 40,
    );
    final store = AppStore()
      ..sources.add(source)
      ..addOrReplaceItem(item);

    expect(libraryEntryRemovePath(store, source, entry), '/media/Show');
  });

  test('media group removal uses covering selected folder', () {
    final source = MediaSourceConfig.local(
      id: 'source',
      name: 'source',
      directory: '/media',
    ).copyWith(selectedPaths: const ['/media/Show']);
    const item = MediaItem(
      id: 'source:/media/Show/01.mp4',
      sourceId: 'source',
      sourceName: 'source',
      type: SourceType.local,
      title: '01',
      uri: '/media/Show/01.mp4',
      folderTitle: 'Show',
      groupPath: '/media/Show',
    );
    final group = mediaFolderGroups(const [item]).single;

    expect(mediaGroupRemovePath(source, group), '/media/Show');
  });

  test('multi-file media group removal uses group folder', () {
    final source = MediaSourceConfig.local(
      id: 'source',
      name: 'source',
      directory: '/media',
    ).copyWith(selectedPaths: const ['/media/Show/01.mp4', '/media/Show']);
    const items = [
      MediaItem(
        id: 'source:/media/Show/01.mp4',
        sourceId: 'source',
        sourceName: 'source',
        type: SourceType.local,
        title: '01',
        uri: '/media/Show/01.mp4',
        folderTitle: 'Show',
        groupPath: '/media/Show',
      ),
      MediaItem(
        id: 'source:/media/Show/02.mp4',
        sourceId: 'source',
        sourceName: 'source',
        type: SourceType.local,
        title: '02',
        uri: '/media/Show/02.mp4',
        folderTitle: 'Show',
        groupPath: '/media/Show',
      ),
    ];
    final group = mediaFolderGroups(items).single;

    expect(mediaGroupRemovePath(source, group), '/media/Show');
  });

  test('removing a webdav folder removes its scanned children', () async {
    const selectedPath = '/dav/Q Show/';
    final source = MediaSourceConfig.webdav(
      id: 'source',
      name: 'WebDAV',
      baseUrl: 'https://example.com',
      username: '',
      password: '',
      directory: '/',
      selectedPaths: const [selectedPath],
    );
    const removed = MediaItem(
      id: 'source:/dav/Q Show/1080P/01.mkv',
      sourceId: 'source',
      sourceName: 'WebDAV',
      type: SourceType.webdav,
      title: '01',
      uri: 'https://example.com/dav/Q%20Show/1080P/01.mkv',
    );
    const kept = MediaItem(
      id: 'source:/dav/Other/01.mkv',
      sourceId: 'source',
      sourceName: 'WebDAV',
      type: SourceType.webdav,
      title: '01',
      uri: 'https://example.com/dav/Other/01.mkv',
    );
    final store = AppStore()
      ..sources.add(source)
      ..items.addAll(const [removed, kept])
      ..progress[removed.id] = 1
      ..metadata[removed.id] = MediaMetadata(
        itemId: removed.id,
        tmdbId: 1,
        mediaType: 'tv',
        title: 'Q Show',
        schemaVersion: currentMetadataSchemaVersion,
      )
      ..rebuildItemIndex();

    await store.removeSelectedPath(source, selectedPath);

    expect(store.sources.single.selectedPaths, isEmpty);
    expect(store.items, [kept]);
    expect(store.progress, isEmpty);
    expect(store.metadata, isEmpty);
  });

  test('removing a selection notifies before slow save finishes', () async {
    const selectedPath = '/dav/Q Show/';
    final source = MediaSourceConfig.webdav(
      id: 'source',
      name: 'WebDAV',
      baseUrl: 'https://example.com',
      username: '',
      password: '',
      directory: '/',
      selectedPaths: const [selectedPath],
    );
    const removed = MediaItem(
      id: 'source:/dav/Q Show/01.mkv',
      sourceId: 'source',
      sourceName: 'WebDAV',
      type: SourceType.webdav,
      title: '01',
      uri: 'https://example.com/dav/Q%20Show/01.mkv',
    );
    const kept = MediaItem(
      id: 'source:/dav/Other/01.mkv',
      sourceId: 'source',
      sourceName: 'WebDAV',
      type: SourceType.webdav,
      title: '01',
      uri: 'https://example.com/dav/Other/01.mkv',
    );
    final store = _SlowSaveStore()
      ..sources.add(source)
      ..items.addAll(const [removed, kept])
      ..rebuildItemIndex();
    store.metadataRefreshing = true;
    var notified = false;
    store.addListener(() {
      notified = true;
      expect(store.items, [kept]);
      expect(store.metadataRefreshing, isFalse);
    });

    final pending = store.removeSelectedPath(source, selectedPath);

    expect(notified, isTrue);
    expect(store.sources.single.selectedPaths, isEmpty);
    await store.saveStarted.future;
    store.finishSave.complete();
    await pending;
  });

  test('removing a source notifies before slow save finishes', () async {
    final source = MediaSourceConfig.local(
      id: 'source',
      name: 'source',
      directory: '/media',
    );
    final keptSource = MediaSourceConfig.local(
      id: 'kept',
      name: 'kept',
      directory: '/other',
    );
    const removed = MediaItem(
      id: 'source:/media/Show/01.mkv',
      sourceId: 'source',
      sourceName: 'source',
      type: SourceType.local,
      title: '01',
      uri: '/media/Show/01.mkv',
      folderTitle: 'Show',
    );
    const kept = MediaItem(
      id: 'kept:/other/Show/01.mkv',
      sourceId: 'kept',
      sourceName: 'kept',
      type: SourceType.local,
      title: '01',
      uri: '/other/Show/01.mkv',
      folderTitle: 'Show',
    );
    final store = _SlowSaveStore()
      ..sources.addAll([source, keptSource])
      ..items.addAll(const [removed, kept])
      ..progress[removed.id] = 1
      ..durations[removed.id] = 2
      ..lastPlayedAt[removed.id] = 3
      ..folderOrientations[mediaFolderKey(removed)] = 'landscape'
      ..rebuildItemIndex();
    store.metadataRefreshing = true;
    var notified = false;
    store.addListener(() {
      notified = true;
      expect(store.sources, [keptSource]);
      expect(store.items, [kept]);
      expect(store.metadataRefreshing, isFalse);
      expect(store.progress, isEmpty);
      expect(store.durations, isEmpty);
      expect(store.lastPlayedAt, isEmpty);
      expect(store.folderOrientations, isEmpty);
    });

    final pending = store.removeSource(source);

    expect(notified, isTrue);
    await store.saveStarted.future;
    store.finishSave.complete();
    await pending;
  });

  test('library home hides stale database entries after in-memory removal', () {
    final source = MediaSourceConfig.local(
      id: 'source',
      name: 'source',
      directory: '/media',
    ).copyWith(selectedPaths: const ['/media/Show']);
    const liveItem = MediaItem(
      id: 'source:/media/Show/01.mkv',
      sourceId: 'source',
      sourceName: 'source',
      type: SourceType.local,
      title: '01',
      uri: '/media/Show/01.mkv',
      folderTitle: 'Show',
    );
    const liveEntry = LibraryHomeEntry(
      folderId: 1,
      sourceId: 'source',
      folderPath: '/media/Show',
      showId: 1,
      tmdbId: 1,
      title: 'Show',
      localFileCount: 1,
    );
    const staleEntry = LibraryHomeEntry(
      folderId: 2,
      sourceId: 'source',
      folderPath: '/media/Removed',
      itemId: 'source:/media/Removed/01.mkv',
      showId: 2,
      tmdbId: 2,
      title: 'Removed',
      localFileCount: 1,
    );
    final store = AppStore()
      ..sources.add(source)
      ..addOrReplaceItem(liveItem);

    expect(filterLiveLibraryHome(store, const [staleEntry, liveEntry]),
        [liveEntry]);
  });

  test('removing a selection deletes cached video covers', () async {
    const selectedPath = '/media/Show';
    final source = MediaSourceConfig.local(
      id: 'source',
      name: 'source',
      directory: '/media',
    ).copyWith(selectedPaths: const [selectedPath]);
    const item = MediaItem(
      id: 'source:/media/Show/01.mp4',
      sourceId: 'source',
      sourceName: 'source',
      type: SourceType.local,
      title: '01',
      uri: '/media/Show/01.mp4',
      folderTitle: 'Show',
    );
    final dir = await Directory.systemTemp.createTemp('rplayer-cover-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appChannel, (call) async {
      if (call.method == 'appFilesDir') return dir.path;
      if (call.method == 'videoThumbnail') return Uint8List.fromList([1, 2, 3]);
      throw MissingPluginException();
    });
    final store = AppStore()
      ..sources.add(source)
      ..items.add(item)
      ..rebuildItemIndex();

    try {
      await store.videoCoverBytes(item);
      final coverDir = Directory('${dir.path}/video_covers');

      expect(coverDir.listSync(), isNotEmpty);

      await store.removeSelectedPath(source, selectedPath);

      expect(coverDir.existsSync(), isTrue);
      expect(coverDir.listSync(), isEmpty);
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(appChannel, null);
      await dir.delete(recursive: true);
    }
  });

  test('removing a webdav folder clears stale scanned children', () async {
    const selectedPath = '/dav/Q Show/';
    final source = MediaSourceConfig.webdav(
      id: 'source',
      name: 'WebDAV',
      baseUrl: 'https://example.com',
      username: '',
      password: '',
      directory: '/',
    );
    const removed = MediaItem(
      id: 'source:/dav/Q Show/1080P/01.mkv',
      sourceId: 'source',
      sourceName: 'WebDAV',
      type: SourceType.webdav,
      title: '01',
      uri: 'https://example.com/dav/Q%20Show/1080P/01.mkv',
    );
    const kept = MediaItem(
      id: 'source:/dav/Other/01.mkv',
      sourceId: 'source',
      sourceName: 'WebDAV',
      type: SourceType.webdav,
      title: '01',
      uri: 'https://example.com/dav/Other/01.mkv',
    );
    final store = AppStore()
      ..sources.add(source)
      ..items.addAll(const [removed, kept])
      ..rebuildItemIndex();

    await store.removeSelectedPath(source, selectedPath);

    expect(store.items, [kept]);
  });

  test('removing a webdav folder also matches parsed group path', () async {
    const selectedPath = '/dav/Q Show/';
    final source = MediaSourceConfig.webdav(
      id: 'source',
      name: 'WebDAV',
      baseUrl: 'https://example.com',
      username: '',
      password: '',
      directory: '/',
    );
    const removed = MediaItem(
      id: 'source:/dav/Encoded%20Name/1080P/01.mkv',
      sourceId: 'source',
      sourceName: 'WebDAV',
      type: SourceType.webdav,
      title: '01',
      uri: 'https://example.com/dav/Encoded%20Name/1080P/01.mkv',
      groupPath: selectedPath,
    );
    const kept = MediaItem(
      id: 'source:/dav/Other/01.mkv',
      sourceId: 'source',
      sourceName: 'WebDAV',
      type: SourceType.webdav,
      title: '01',
      uri: 'https://example.com/dav/Other/01.mkv',
    );
    final store = AppStore()
      ..sources.add(source)
      ..items.addAll(const [removed, kept])
      ..rebuildItemIndex();

    await store.removeSelectedPath(source, selectedPath);

    expect(store.items, [kept]);
  });

  test('removing a webdav folder ignores overlapping selections', () async {
    const selectedPath = '/dav/Parent/Q Show/';
    final source = MediaSourceConfig.webdav(
      id: 'source',
      name: 'WebDAV',
      baseUrl: 'https://example.com',
      username: '',
      password: '',
      directory: '/',
      selectedPaths: const ['/dav/Parent/', selectedPath],
    );
    const removed = MediaItem(
      id: 'source:/dav/Parent/Q Show/1080P/01.mkv',
      sourceId: 'source',
      sourceName: 'WebDAV',
      type: SourceType.webdav,
      title: '01',
      uri: 'https://example.com/dav/Parent/Q%20Show/1080P/01.mkv',
    );
    const kept = MediaItem(
      id: 'source:/dav/Parent/Other/01.mkv',
      sourceId: 'source',
      sourceName: 'WebDAV',
      type: SourceType.webdav,
      title: '01',
      uri: 'https://example.com/dav/Parent/Other/01.mkv',
    );
    final store = AppStore()
      ..sources.add(source)
      ..items.addAll(const [removed, kept])
      ..rebuildItemIndex();

    await store.removeSelectedPath(source, selectedPath);

    expect(store.sources.single.selectedPaths, ['/dav/Parent/']);
    expect(store.items, [kept]);
  });

  test('removing only child under selected webdav parent clears parent',
      () async {
    const selectedPath = '/dav/Parent/Q Show/';
    final source = MediaSourceConfig.webdav(
      id: 'source',
      name: 'WebDAV',
      baseUrl: 'https://example.com',
      username: '',
      password: '',
      directory: '/',
      selectedPaths: const ['/dav/Parent/'],
    );
    const removed = MediaItem(
      id: 'source:/dav/Parent/Q Show/01.mkv',
      sourceId: 'source',
      sourceName: 'WebDAV',
      type: SourceType.webdav,
      title: '01',
      uri: 'https://example.com/dav/Parent/Q%20Show/01.mkv',
    );
    const keptOutsideParent = MediaItem(
      id: 'source:/dav/Other/01.mkv',
      sourceId: 'source',
      sourceName: 'WebDAV',
      type: SourceType.webdav,
      title: '01',
      uri: 'https://example.com/dav/Other/01.mkv',
    );
    final store = AppStore()
      ..sources.add(source)
      ..items.addAll(const [removed, keptOutsideParent])
      ..rebuildItemIndex();

    await store.removeSelectedPath(source, selectedPath);

    expect(store.sources.single.selectedPaths, isEmpty);
    expect(store.items, [keptOutsideParent]);
    expect(
      store.sourcePathAdded(store.sources.single, '/dav/Parent/', isDir: true),
      isFalse,
    );
  });

  test('source path selection state separates none partial and full', () {
    final source = MediaSourceConfig.webdav(
      id: 'source',
      name: 'WebDAV',
      baseUrl: 'https://example.com',
      username: '',
      password: '',
      directory: '/',
      selectedPaths: const ['/dav/Full/'],
    );
    const partialItem = MediaItem(
      id: 'source:/dav/Partial/01.mkv',
      sourceId: 'source',
      sourceName: 'WebDAV',
      type: SourceType.webdav,
      title: '01',
      uri: 'https://example.com/dav/Partial/01.mkv',
    );
    final store = AppStore()
      ..sources.add(source)
      ..items.add(partialItem)
      ..rebuildItemIndex();

    expect(
      store.sourcePathSelectionState(source, '/dav/Full/', isDir: true),
      SourcePathSelectionState.full,
    );
    expect(
      store.sourcePathSelectionState(source, '/dav/Partial/', isDir: true),
      SourcePathSelectionState.partial,
    );
    expect(
      store.sourcePathSelectionState(source, '/dav/Empty/', isDir: true),
      SourcePathSelectionState.none,
    );
    expect(
      store.sourcePathSelectionState(
        source,
        '/dav/Partial/01.mkv',
        isDir: false,
      ),
      SourcePathSelectionState.full,
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

  test('adding a local directory creates a selectable root only', () async {
    final store = AppStore();

    final source = await store.addLocalDirectory('/media/Folder');

    expect(source.directory, '/media/Folder');
    expect(source.selectedPaths, isEmpty);
    expect(store.items, isEmpty);
  });

  test('adding a local selection creates draft source', () async {
    final store = _NoSaveStore();
    final source = MediaSourceConfig.local(
      id: 'draft',
      name: '本地存储',
      directory: '',
    );

    await store.addLocalSelection(
      source,
      const LocalEntry(
        name: 'Movie.mp4',
        path: '/media/Folder/Movie.mp4',
        isDir: false,
        size: 1,
      ),
    );

    expect(store.sources.single.id, 'draft');
    expect(store.sources.single.selectedPaths, ['/media/Folder/Movie.mp4']);
    expect(store.items.single.uri, '/media/Folder/Movie.mp4');
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
    expect(find.text('OpenList'), findsOneWidget);
  });

  testWidgets('opening local browser adds no source until a path is selected',
      (WidgetTester tester) async {
    final store = AppStore()..loaded = true;

    await tester.pumpWidget(
      MaterialApp(
        home: AddSourcePage(store: store),
      ),
    );

    await tester.tap(find.text('本地目录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(store.sources, isEmpty);
    expect(find.byType(LocalBrowserPage), findsOneWidget);
  });

  testWidgets('openlist form uses Chinese default name',
      (WidgetTester tester) async {
    final store = AppStore()..loaded = true;

    await tester.pumpWidget(
      MaterialApp(
        home: AddSourcePage(store: store),
      ),
    );

    await tester.tap(find.text('OpenList'));
    await tester.pumpAndSettle();

    expect(find.text('\u6211\u7684 OpenList'), findsOneWidget);
    expect(find.text('添加 OpenList 源'), findsOneWidget);
    expect(find.text('OTP Code\uFF08\u53EF\u9009\uFF09'), findsOneWidget);
    expect(
        find.text(
            '\u672A\u542F\u7528\u4E24\u6B65\u9A8C\u8BC1\u53EF\u7559\u7A7A'),
        findsOneWidget);
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

class _SlowSaveStore extends AppStore {
  final saveStarted = Completer<void>();
  final finishSave = Completer<void>();

  @override
  Future<void> save() async {
    if (!saveStarted.isCompleted) saveStarted.complete();
    await finishSave.future;
  }
}

class _NoSaveStore extends AppStore {
  @override
  Future<void> save() async {}
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

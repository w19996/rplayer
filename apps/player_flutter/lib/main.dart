import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

part 'app/player_app.dart';
part 'store/app_store.dart';
part 'app/player_shell.dart';
part 'pages/media_library_page.dart';
part 'pages/source_library_page.dart';
part 'pages/add_source_page.dart';
part 'pages/local_browser_page.dart';
part 'pages/profile_page.dart';
part 'pages/video_player_page.dart';
part 'widgets/common_widgets.dart';
part 'services/sync_service.dart';
part 'services/rust_core_service.dart';
part 'services/media_scan_service.dart';
part 'services/tmdb_metadata_service.dart';
part 'services/danmu_service.dart';
part 'core/utils.dart';
part 'models/media_models.dart';
part 'services/webdav_client.dart';

const videoExtensions = {
  '.mp4',
  '.mkv',
  '.mov',
  '.avi',
  '.flv',
  '.wmv',
  '.webm',
  '.m4v',
  '.ts',
  '.m2ts',
  '.mts',
  '.mpg',
  '.mpeg',
  '.3gp',
  '.rm',
  '.rmvb',
  '.vob',
  '.ogv',
  '.asf',
};

const appName = 'rplayer';
const appChannel = MethodChannel('rplayer/app');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const PlayerApp());
}

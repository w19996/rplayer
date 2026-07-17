# TVBoxOS-derived runtime

The Android TVBox Spider/JAR compatibility files in this repository are adapted from:

- Project: q215613905/TVBoxOS
- Source: https://github.com/q215613905/TVBoxOS
- Revision: 0409954033a44582b431d89934e3980900f4a265
- License: GNU Affero General Public License v3.0 only

Adapted files:

- `apps/player_flutter/android/app/src/main/java/com/github/catvod/crawler/Spider.java`
- `apps/player_flutter/android/app/src/main/java/com/github/catvod/crawler/SpiderApi.java`
- `apps/player_flutter/android/app/src/main/java/com/github/catvod/crawler/SpiderDebug.java`
- `apps/player_flutter/android/app/src/main/java/com/github/catvod/crawler/ProtectedInitJar.java`
- `apps/player_flutter/android/app/src/main/java/com/github/catvod/net/OkHttp.java`
- `apps/player_flutter/android/app/src/main/kotlin/com/example/player_flutter/TvboxBridge.kt`

Changes isolate the source-resolution runtime from TVBoxOS's UI and player so resolved media continues through rplayer's existing playback path. The complete corresponding source is distributed in this repository. The upstream copyright notices and AGPL-3.0 terms remain applicable to these files.

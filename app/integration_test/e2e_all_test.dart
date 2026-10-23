// The whole end-to-end suite in one file, so there is one APK build.
// Linux: `flutter test integration_test/e2e_all_test.dart -d linux`.
// Android TV emulator: `.github/e2e.sh android <out-dir>`.
import 'package:integration_test/integration_test.dart';

import 'e2e_find.dart';
import 'e2e_form.dart';
import 'e2e_home.dart';
import 'e2e_livetv.dart';
import 'e2e_player.dart';
import 'e2e_plugins.dart';
import 'e2e_receive.dart';
import 'e2e_torrent.dart';
import 'e2e_youtube.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  formE2e();
  homeE2e();
  findE2e();
  pluginsE2e();
  playerE2e();
  youtubeE2e();
  livetvE2e();
  torrentE2e();
  receiveE2e();
}

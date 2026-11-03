import 'dart:io';

import 'package:chithram_gateway/src/api.dart';
import 'package:chithram_gateway/src/cli.dart';
import 'package:chithram_gateway/src/config.dart';
import 'package:chithram_gateway/src/state.dart';
import 'package:chithram_gateway/src/tls.dart';
import 'package:shelf/shelf_io.dart' as io;

Future<void> main(List<String> args) async {
  final cfg = Config.fromEnv();
  final cmd = args.isEmpty ? 'serve' : args.first;
  switch (cmd) {
    case 'serve':
      final gw = Gateway(cfg, StateStore(cfg.stateDir));
      final server = await io.serve(
        gw.handler,
        InternetAddress.anyIPv4,
        cfg.port,
        securityContext: serverContext(cfg.tlsCertPath, cfg.tlsKeyPath),
      );
      server.autoCompress = false;
      server.idleTimeout = const Duration(seconds: 30);
      stdout.writeln('gateway listening (https) on :${cfg.port}');
      ProcessSignal.sigterm.watch().listen((_) async {
        await server.close(force: true);
        exit(0);
      });
    case 'healthcheck':
      exit(await healthcheck(cfg));
    default:
      exit(await runAdmin(args, cfg));
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:chithram/src/features/telegram/tg_range_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tdlib/tdlib.dart';

import 'support.dart';

class Reply {
  const Reply(this.status, this.headers, this.body);
  final int status;
  final HttpHeaders headers;
  final Uint8List body;
}

Future<Reply> get(String url, {String? range, String method = 'GET', String? host}) async {
  final c = HttpClient();
  try {
    final req = await c.openUrl(method, Uri.parse(url));
    if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
    if (host != null) req.headers.host = host;
    final res = await req.close();
    final b = BytesBuilder();
    await for (final chunk in res) {
      b.add(chunk);
    }
    return Reply(res.statusCode, res.headers, b.takeBytes());
  } finally {
    c.close(force: true);
  }
}

void main() {
  const size = 10000;
  late FakeTelegramClient fake;
  late TgRangeServer server;
  late String url;
  final data = bytes(size);

  setUp(() async {
    fake = FakeTelegramClient();
    fake.receive(media(1, name: 'a.mkv', size: size), bytes: data);
    server = TgRangeServer(fake, chunk: 1000, stall: const Duration(seconds: 5), aheadSlack: 2000);
    url = await server.urlFor(10, 'a.mkv');
  });
  tearDown(() => server.close());

  test('a fully downloaded file serves whole and by range', () async {
    fake.advance(10);
    final all = await get(url);
    expect(all.status, 200);
    expect(all.headers.contentLength, size);
    expect(all.headers.value('accept-ranges'), 'bytes');
    expect(all.headers.contentType?.mimeType, 'video/x-matroska');
    expect(all.body, data);

    final part = await get(url, range: 'bytes=100-299');
    expect(part.status, 206);
    expect(part.headers.value('content-range'), 'bytes 100-299/$size');
    expect(part.body, data.sublist(100, 300));

    final tail = await get(url, range: 'bytes=-50');
    expect(tail.body, data.sublist(size - 50));
    final open = await get(url, range: 'bytes=9990-');
    expect(open.body, data.sublist(9990));
    final head = await get(url, method: 'HEAD');
    expect(head.status, 200);
    expect(head.headers.contentLength, size);
    expect(head.body, isEmpty);
  });

  test('waits for bytes that are not on disk yet, then serves them', () async {
    final reply = get(url, range: 'bytes=0-');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    // The first request moved the download to offset 0.
    expect(fake.downloadOffsets, [0]);
    fake.advance(10, prefix: 3000);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    fake.advance(10, prefix: 7000);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    fake.advance(10);
    final r = await reply;
    expect(r.status, 206);
    expect(r.body, data);
  });

  test('a seek past the download moves it; the bytes match the offset', () async {
    // Downloading from 0 with 1000 bytes in; the player seeks to 8000.
    unawaited(fake.downloadFile(10));
    fake.advance(10, prefix: 1000);
    final reply = get(url, range: 'bytes=8000-8999');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(fake.downloadOffsets, [0, 8000]);
    fake.advance(10, prefix: 2000);
    final r = await reply;
    expect(r.body, data.sublist(8000, 9000));
  });

  test('a read just ahead of the frontier waits instead of restarting', () async {
    unawaited(fake.downloadFile(10));
    fake.advance(10, prefix: 1000);
    final reply = get(url, range: 'bytes=1500-1999');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(fake.downloadOffsets, [0]);
    fake.advance(10, prefix: 3000);
    expect((await reply).body, data.sublist(1500, 2000));
  });

  test('a range past the end is refused', () async {
    fake.advance(10);
    final r = await get(url, range: 'bytes=20000-');
    expect(r.status, 416);
    expect(r.headers.value('content-range'), 'bytes */$size');
  });

  test('wrong token, wrong host and unknown files are refused', () async {
    fake.advance(10);
    final bad = url.replaceFirst(server.token, 'f' * 32);
    expect((await get(bad)).status, 403);
    expect((await get(url, host: 'evil.example')).status, 403);
    final missing = url.replaceFirst('/tg/10/', '/tg/99/');
    expect((await get(missing)).status, 404);
    expect((await get('http://127.0.0.1:${server.port}/')).status, 403);
  });

  test('gives up when no bytes ever arrive', () async {
    final quick = TgRangeServer(fake, chunk: 1000, stall: const Duration(milliseconds: 200));
    addTearDown(quick.close);
    final u = await quick.urlFor(10, 'a.mkv');
    final r = await get(u, range: 'bytes=0-99');
    expect(r.status, 504);
    expect(r.body, isEmpty);
  });
}

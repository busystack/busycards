import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:busystack_dav/busystack_dav.dart';
import 'package:busystack_graph/busystack_graph.dart';
import 'package:http/http.dart' as http;

const total = 512 * 1024 * 1024;
const chunkSize = 64 * 1024;
Stream<List<int>> chunks() async* {
  for (var index = 0; index < total ~/ chunkSize; index++) {
    yield Uint8List(chunkSize)..[0] = index % 256;
  }
}

final class TransferFixture extends http.BaseClient {
  int uploadBytes = 0, requests = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    if (request.followRedirects) throw StateError('Operational redirect');
    if (request.method == 'GET')
      return http.StreamedResponse(chunks(), 200, contentLength: total);
    if (request.url.host == 'upload.example.test' &&
        request.headers.containsKey('authorization'))
      throw StateError('Upload credential leak');
    await for (final bytes in request.finalize()) {
      uploadBytes += bytes.length;
    }
    return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
  }
}

Future<Map<String, Object?>> measure(
  String label,
  Future<void> Function() work,
) async {
  final baseline = ProcessInfo.currentRss;
  var peak = baseline;
  final sampler = Timer.periodic(const Duration(milliseconds: 5), (_) {
    if (ProcessInfo.currentRss > peak) peak = ProcessInfo.currentRss;
  });
  final clock = Stopwatch()..start();
  await work();
  clock.stop();
  sampler.cancel();
  if (ProcessInfo.currentRss > peak) peak = ProcessInfo.currentRss;
  return {
    'operation': label,
    'bytes': total,
    'chunkBytes': chunkSize,
    'elapsedMs': clock.elapsedMilliseconds,
    'baselineRss': baseline,
    'sampledPeakRss': peak,
    'rssGrowth': peak - baseline,
  };
}

Future<void> main() async {
  final fixture = TransferFixture();
  final graph = GraphClient(
    httpClient: fixture,
    tokenProvider: ({String? claims}) async =>
        const GraphAuthorization('fixture'),
  );
  final dav = DavTransferClient(
    client: fixture,
    authority: Uri.parse('https://dav.example.test/'),
  );
  final credentials = DavBasicCredential(
    username: 'fixture',
    password: 'fixture',
  );
  final results = <Map<String, Object?>>[];
  Future<void> drain(Stream<List<int>> stream) async {
    var received = 0;
    await for (final bytes in stream) {
      received += bytes.length;
      if (received % (16 * 1024 * 1024) == 0)
        await Future<void>.delayed(Duration.zero);
    }
    if (received != total) throw StateError('Truncated transfer');
  }

  results.add(
    await measure(
      'graph-download',
      () =>
          drain(graph.download('me/messages/fixture/attachments/file/\$value')),
    ),
  );
  results.add(
    await measure(
      'dav-download',
      () => drain(
        dav.download(
          Uri.parse('https://dav.example.test/file'),
          credential: credentials,
          cancellation: DavCancellationToken(),
        ),
      ),
    ),
  );
  results.add(
    await measure('graph-preauthorized-upload', () async {
      await graph.upload(
        GraphUploadDestination(
          Uri.parse('https://upload.example.test/exact-capability'),
        ),
        source: chunks(),
        length: total,
        headers: {'Content-Range': 'bytes 0-${total - 1}/$total'},
      );
    }),
  );
  results.add(
    await measure('dav-upload', () async {
      await dav.upload(
        Uri.parse('https://dav.example.test/file'),
        source: chunks(),
        length: total,
        credential: credentials,
        cancellation: DavCancellationToken(),
      );
    }),
  );
  if (fixture.uploadBytes != total * 2 || fixture.requests != 4)
    throw StateError('Transfer accounting');
  graph.close();
  await File('validation/stream-contract.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'transport': 'deterministic HTTP stream fixture, no live network',
      'operations': results,
      'totalTransferredBytes': total * 4,
    }),
  );
  stdout.writeln(jsonEncode(results));
}

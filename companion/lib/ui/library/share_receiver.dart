/// Share-sheet entry seam (Story 2.3, Task 8 / AC6). The OS delivers `.txt`/`.md`
/// shared from other apps; this adapter funnels them into the **same**
/// `import_service.importFile` path as the file picker — never a second pipeline.
///
/// The platform plugin is hidden behind [ShareSource] so it is injectable: the
/// provider **defaults to a no-op**, so widget tests never touch the
/// `receive_sharing_intent` platform channels. Only `main.dart` overrides it with
/// [PluginShareSource] for the real app. This path is platform-bound and
/// verified manually (no automated test).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Abstracts `receive_sharing_intent` so it can be faked/disabled in tests.
abstract interface class ShareSource {
  /// Files shared while the app is already running (warm delivery).
  Stream<List<SharedMediaFile>> mediaStream();

  /// Files shared that cold-started the app.
  Future<List<SharedMediaFile>> initialMedia();

  /// Tells the plugin we have consumed the initial intent.
  void reset();
}

/// The real implementation — instantiated only in `main.dart`.
class PluginShareSource implements ShareSource {
  const PluginShareSource();

  @override
  Stream<List<SharedMediaFile>> mediaStream() =>
      ReceiveSharingIntent.instance.getMediaStream();

  @override
  Future<List<SharedMediaFile>> initialMedia() =>
      ReceiveSharingIntent.instance.getInitialMedia();

  @override
  void reset() => ReceiveSharingIntent.instance.reset();
}

/// Default: does nothing. Keeps widget tests off the platform channels.
class NoopShareSource implements ShareSource {
  const NoopShareSource();

  @override
  Stream<List<SharedMediaFile>> mediaStream() =>
      const Stream<List<SharedMediaFile>>.empty();

  @override
  Future<List<SharedMediaFile>> initialMedia() async =>
      const <SharedMediaFile>[];

  @override
  void reset() {}
}

/// No-op by default; `main.dart` overrides this with [PluginShareSource].
final shareSourceProvider =
    Provider<ShareSource>((ref) => const NoopShareSource());

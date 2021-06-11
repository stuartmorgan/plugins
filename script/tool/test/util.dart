// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_plugin_tools/src/common.dart';
import 'package:meta/meta.dart';
import 'package:quiver/collection.dart';

/// Creates a packages directory in the given location.
///
/// If [parentDir] is set the packages directory will be created there,
/// otherwise [fileSystem] must be provided and it will be created an arbitrary
/// location in that filesystem.
Directory createPackagesDirectory(
    {Directory? parentDir, FileSystem? fileSystem}) {
  assert(parentDir != null || fileSystem != null,
      'One of parentDir or fileSystem must be provided');
  assert(fileSystem == null || fileSystem is MemoryFileSystem,
      'If using a real filesystem, parentDir must be provided');
  final Directory packagesDir =
      (parentDir ?? fileSystem!.currentDirectory).childDirectory('packages');
  packagesDir.createSync();
  return packagesDir;
}

/// Details for platform support in a plugin.
@immutable
class PlatformDetails {
  const PlatformDetails(
    this.type, {
    this.variants = const <String>[],
  });

  /// The type of support for the platform.
  final PlatformSupport type;

  /// Any 'supportVariants' to list in the pubspec.
  final List<String> variants;
}

/// Creates a plugin package with the given [name] in [packagesDirectory].
///
/// [platformSupport] is a map of platform string to the support details for
/// that platform.
Directory createFakePlugin(
  String name,
  Directory packagesDirectory, {
  List<String> examples = const <String>['example'],
  List<List<String>> extraFiles = const <List<String>>[],
  Map<String, PlatformDetails> platformSupport =
      const <String, PlatformDetails>{},
  String? version = '0.0.1',
  String parentDirectoryName = '',
}) {
  Directory parentDirectory = packagesDirectory;
  if (parentDirectoryName != '') {
    parentDirectory = parentDirectory.childDirectory(parentDirectoryName);
  }
  final Directory pluginDirectory =
      createFakePackage(name, parentDirectory, extraFiles: extraFiles);

  createFakePubspec(pluginDirectory,
      name: name,
      isFlutter: true,
      platformSupport: platformSupport,
      version: version);
  createFakeCHANGELOG(pluginDirectory, '''
## $version
  * Some changes.
  ''');

  if (examples.length == 1) {
    final Directory exampleDir = pluginDirectory.childDirectory(examples.first)
      ..createSync();
    createFakePubspec(exampleDir,
        name: '${name}_example', isFlutter: true, publishTo: 'none');
  } else if (examples.isNotEmpty) {
    final Directory exampleDir = pluginDirectory.childDirectory('example')
      ..createSync();
    for (final String example in examples) {
      final Directory currentExample = exampleDir.childDirectory(example)
        ..createSync();
      createFakePubspec(currentExample,
          name: example, isFlutter: true, publishTo: 'none');
    }
  }

  return pluginDirectory;
}

/// Creates a plugin package with the given [name] in [packagesDirectory].
///
/// [platformSupport] is a map of platform string to the support details for
/// that platform.
Directory createFakePackage(
  String name,
  Directory parentDirectory, {
  List<List<String>> extraFiles = const <List<String>>[],
  bool isFlutter = false,
}) {
  final Directory packageDirectory = parentDirectory.childDirectory(name);
  packageDirectory.createSync(recursive: true);

  createFakePubspec(packageDirectory, name: name, isFlutter: isFlutter);

  final FileSystem fileSystem = packageDirectory.fileSystem;
  for (final List<String> file in extraFiles) {
    final List<String> newFilePath = <String>[packageDirectory.path, ...file];
    final File newFile = fileSystem.file(fileSystem.path.joinAll(newFilePath));
    newFile.createSync(recursive: true);
  }

  return packageDirectory;
}

void createFakeCHANGELOG(Directory parent, String texts) {
  parent.childFile('CHANGELOG.md').createSync();
  parent.childFile('CHANGELOG.md').writeAsStringSync(texts);
}

/// Creates a `pubspec.yaml` file with a flutter dependency.
///
/// [platformSupport] is a map of platform string to the support details for
/// that platform.
void createFakePubspec(
  Directory parent, {
  String name = 'fake_package',
  bool isFlutter = true,
  Map<String, PlatformDetails> platformSupport =
      const <String, PlatformDetails>{},
  String publishTo = 'http://no_pub_server.com',
  String? version,
}) {
  parent.childFile('pubspec.yaml').createSync();
  String yaml = '''
name: $name
flutter:
  plugin:
    platforms:
''';
  for (final MapEntry<String, PlatformDetails> platform
      in platformSupport.entries) {
    yaml += _pluginPlatformSection(platform.key, platform.value, name);
  }
  if (isFlutter) {
    yaml += '''
dependencies:
  flutter:
    sdk: flutter
''';
  }
  if (version != null) {
    yaml += '''
version: $version
''';
  }
  if (publishTo.isNotEmpty) {
    yaml += '''
publish_to: $publishTo # Hardcoded safeguard to prevent this from somehow being published by a broken test.
''';
  }
  parent.childFile('pubspec.yaml').writeAsStringSync(yaml);
}

String _pluginPlatformSection(
    String platform, PlatformDetails support, String packageName) {
  String entry = '';
  // Build the main plugin entry.
  if (support.type == PlatformSupport.federated) {
    entry = '''
      $platform:
        default_package: ${packageName}_$platform
''';
  } else {
    switch (platform) {
      case kPlatformAndroid:
        entry = '''
      android:
        package: io.flutter.plugins.fake
        pluginClass: FakePlugin
''';
        break;
      case kPlatformIos:
        entry = '''
      ios:
        pluginClass: FLTFakePlugin
''';
        break;
      case kPlatformLinux:
        entry = '''
      linux:
        pluginClass: FakePlugin
''';
        break;
      case kPlatformMacos:
        entry = '''
      macos:
        pluginClass: FakePlugin
''';
        break;
      case kPlatformWeb:
        entry = '''
      web:
        pluginClass: FakePlugin
        fileName: ${packageName}_web.dart
''';
        break;
      case kPlatformWindows:
        entry = '''
      windows:
        pluginClass: FakePlugin
''';
        break;
      default:
        assert(false, 'Unrecognized platform: $platform');
        break;
    }
  }

  // Add any variants.
  if (support.variants.isNotEmpty) {
    entry += '''
        supportedVariants:
''';
    for (final String variant in support.variants) {
      entry += '''
          - $variant
''';
    }
  }

  return entry;
}

typedef _ErrorHandler = void Function(Error error);

/// Run the command [runner] with the given [args] and return
/// what was printed.
/// A custom [errorHandler] can be used to handle the runner error as desired without throwing.
Future<List<String>> runCapturingPrint(
    CommandRunner<void> runner, List<String> args,
    {_ErrorHandler? errorHandler}) async {
  final List<String> prints = <String>[];
  final ZoneSpecification spec = ZoneSpecification(
    print: (_, __, ___, String message) {
      prints.add(message);
    },
  );
  try {
    await Zone.current
        .fork(specification: spec)
        .run<Future<void>>(() => runner.run(args));
  } on Error catch (e) {
    if (errorHandler == null) {
      rethrow;
    }
    errorHandler(e);
  }

  return prints;
}

/// A mock [ProcessRunner] which records process calls.
class RecordingProcessRunner extends ProcessRunner {
  io.Process? processToReturn;
  final List<ProcessCall> recordedCalls = <ProcessCall>[];

  /// Populate for [io.ProcessResult] to use a String [stdout] instead of a [List] of [int].
  String? resultStdout;

  /// Populate for [io.ProcessResult] to use a String [stderr] instead of a [List] of [int].
  String? resultStderr;

  @override
  Future<int> runAndStream(
    String executable,
    List<String> args, {
    Directory? workingDir,
    bool exitOnError = false,
  }) async {
    recordedCalls.add(ProcessCall(executable, args, workingDir?.path));
    return Future<int>.value(
        processToReturn == null ? 0 : await processToReturn!.exitCode);
  }

  /// Returns [io.ProcessResult] created from [processToReturn], [resultStdout], and [resultStderr].
  @override
  Future<io.ProcessResult> run(
    String executable,
    List<String> args, {
    Directory? workingDir,
    bool exitOnError = false,
    bool logOnError = false,
    Encoding stdoutEncoding = io.systemEncoding,
    Encoding stderrEncoding = io.systemEncoding,
  }) async {
    recordedCalls.add(ProcessCall(executable, args, workingDir?.path));

    final io.Process? process = processToReturn;
    final io.ProcessResult result = process == null
        ? io.ProcessResult(1, 1, '', '')
        : io.ProcessResult(process.pid, await process.exitCode,
            resultStdout ?? process.stdout, resultStderr ?? process.stderr);

    return Future<io.ProcessResult>.value(result);
  }

  @override
  Future<io.Process> start(String executable, List<String> args,
      {Directory? workingDirectory}) async {
    recordedCalls.add(ProcessCall(executable, args, workingDirectory?.path));
    return Future<io.Process>.value(processToReturn);
  }
}

/// A recorded process call.
@immutable
class ProcessCall {
  const ProcessCall(this.executable, this.args, this.workingDir);

  /// The executable that was called.
  final String executable;

  /// The arguments passed to [executable] in the call.
  final List<String> args;

  /// The working directory this process was called from.
  final String? workingDir;

  @override
  bool operator ==(dynamic other) {
    return other is ProcessCall &&
        executable == other.executable &&
        listsEqual(args, other.args) &&
        workingDir == other.workingDir;
  }

  @override
  int get hashCode =>
      (executable.hashCode) ^ (args.hashCode) ^ (workingDir?.hashCode ?? 0);

  @override
  String toString() {
    final List<String> command = <String>[executable, ...args];
    return '"${command.join(' ')}" in $workingDir';
  }
}

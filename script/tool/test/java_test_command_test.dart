// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:args/command_runner.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_plugin_tools/src/common.dart';
import 'package:flutter_plugin_tools/src/java_test_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'util.dart';

void main() {
  group('$JavaTestCommand', () {
    late FileSystem fileSystem;
    late Directory packagesDir;
    late CommandRunner<void> runner;
    late RecordingProcessRunner processRunner;

    setUp(() {
      fileSystem = MemoryFileSystem();
      packagesDir = createPackagesDirectory(fileSystem: fileSystem);
      processRunner = RecordingProcessRunner();
      final JavaTestCommand command =
          JavaTestCommand(packagesDir, processRunner: processRunner);

      runner =
          CommandRunner<void>('java_test_test', 'Test for $JavaTestCommand');
      runner.addCommand(command);
    });

    test('Should run Java tests in Android implementation folder', () async {
      final Directory plugin = createFakePlugin(
        'plugin1',
        packagesDir,
        extraFiles: <List<String>>[
          <String>['example/android', 'gradlew'],
          <String>['android/src/test', 'example_test.java'],
        ],
        platformSupport: <String, PlatformDetails>{
          kPlatformAndroid: const PlatformDetails(PlatformSupport.inline),
        },
      );

      await runner.run(<String>['java-test']);

      expect(
        processRunner.recordedCalls,
        orderedEquals(<ProcessCall>[
          ProcessCall(
            p.join(plugin.path, 'example/android/gradlew'),
            const <String>['testDebugUnitTest', '--info'],
            p.join(plugin.path, 'example/android'),
          ),
        ]),
      );
    });

    test('Should run Java tests in example folder', () async {
      final Directory plugin = createFakePlugin(
        'plugin1',
        packagesDir,
        extraFiles: <List<String>>[
          <String>['example/android', 'gradlew'],
          <String>['example/android/app/src/test', 'example_test.java'],
        ],
        platformSupport: <String, PlatformDetails>{
          kPlatformAndroid: const PlatformDetails(PlatformSupport.inline),
        },
      );

      await runner.run(<String>['java-test']);

      expect(
        processRunner.recordedCalls,
        orderedEquals(<ProcessCall>[
          ProcessCall(
            p.join(plugin.path, 'example/android/gradlew'),
            const <String>['testDebugUnitTest', '--info'],
            p.join(plugin.path, 'example/android'),
          ),
        ]),
      );
    });
  });
}

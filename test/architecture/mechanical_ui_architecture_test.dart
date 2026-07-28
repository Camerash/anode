import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('visible app UI does not depend on Material or content scrollables', () {
    final violations = <String>[];
    final banned = RegExp(
      r'\b('
      r'MaterialApp|Scaffold|AppBar|TabBar|TabBarView|MaterialBanner|'
      r'SnackBar|Switch|SwitchListTile|Slider|DropdownButton|'
      r'DropdownButtonFormField|PopupMenuButton|TextField|TextFormField|'
      r'ListView|PageView|SingleChildScrollView|ReorderableListView|'
      r'MaterialPageRoute'
      r')\b',
    );

    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      if (source.contains("package:flutter/material.dart") ||
          banned.hasMatch(source)) {
        violations.add(file.path);
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Mechanical UI boundary violated by: ${violations.join(', ')}',
    );
  });
}

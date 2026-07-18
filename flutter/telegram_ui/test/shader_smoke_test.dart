import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('liquid_glass.frag compiles and exposes the expected uniform layout',
      () async {
    // Key is unprefixed inside the package's own bundle, packages/-prefixed
    // when consumed from an app.
    ui.FragmentProgram program;
    try {
      program = await ui.FragmentProgram.fromAsset(
        'shaders/liquid_glass.frag',
      );
    } on Exception {
      program = await ui.FragmentProgram.fromAsset(
        'packages/telegram_ui/shaders/liquid_glass.frag',
      );
    }
    final ui.FragmentShader shader = program.fragmentShader();

    // Float uniforms after the engine-set u_size (indices 0-1):
    // u_center(2,3) u_half_size(4,5) u_radius(6-9) u_thickness(10)
    // u_refract_index(11) u_refract_intensity(12) u_foreground_color(13-16).
    shader.setFloat(0, 100);
    shader.setFloat(1, 100);
    for (int i = 2; i <= 16; i++) {
      shader.setFloat(i, i == 11 ? 1.5 : 0.5);
    }
    expect(() => shader.setFloat(17, 0), throwsRangeError);
    shader.dispose();
  });
}

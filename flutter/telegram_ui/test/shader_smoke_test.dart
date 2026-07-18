import 'dart:typed_data' show ByteData;
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

  test('SDF output clip: transparent outside the panel, composited inside',
      () async {
    // The BackdropFilterLayer paints the shader output across its whole
    // (rect, bleed-inflated) clip, so the shader itself must emit transparency
    // outside the panel — Android instead clips the effect node to the
    // rounded outline (BlurredBackgroundDrawableRenderNode.java:39, 79-85).
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

    const int extent = 200;
    // Green backdrop texture.
    final ui.PictureRecorder backdropRecorder = ui.PictureRecorder();
    ui.Canvas(backdropRecorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, 200, 200),
      ui.Paint()..color = const ui.Color(0xFF00FF00),
    );
    final ui.Picture backdropPicture = backdropRecorder.endRecording();
    final ui.Image backdrop = backdropPicture.toImageSync(extent, extent);

    shader
      ..setFloat(0, 200) // u_size
      ..setFloat(1, 200)
      ..setFloat(2, 30) // u_center: 60x60 panel at the origin
      ..setFloat(3, 30)
      ..setFloat(4, 30) // u_half_size
      ..setFloat(5, 30)
      ..setFloat(6, 8) // u_radius (RB, RT, LB, LT)
      ..setFloat(7, 8)
      ..setFloat(8, 8)
      ..setFloat(9, 8)
      ..setFloat(10, 10) // u_thickness
      ..setFloat(11, 1.5) // u_refract_index
      ..setFloat(12, 0) // u_refract_intensity: no displacement
      ..setFloat(13, 0.5) // u_foreground_color, premultiplied white @ 50%
      ..setFloat(14, 0.5)
      ..setFloat(15, 0.5)
      ..setFloat(16, 0.5)
      ..setImageSampler(0, backdrop);

    // Red destination, shader rect painted srcOver across the whole extent —
    // the stand-in for the backdrop layer painting over its full clip.
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 200, 200),
      ui.Paint()..color = const ui.Color(0xFFFF0000),
    );
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 200, 200),
      ui.Paint()..shader = shader,
    );
    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = picture.toImageSync(extent, extent);
    final ByteData bytes =
        (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;

    List<int> pixel(int x, int y) {
      final int offset = (y * extent + x) * 4;
      return <int>[
        bytes.getUint8(offset),
        bytes.getUint8(offset + 1),
        bytes.getUint8(offset + 2),
        bytes.getUint8(offset + 3),
      ];
    }

    // Inside the panel: srcOver(tint, green backdrop) = (128, 255, 128).
    expect(pixel(30, 30), <int>[128, 255, 128, 255]);
    // Outside the panel (sd >= 0): fully transparent output, red destination
    // preserved — the bug this guards against painted (128, 255, 128) here.
    expect(pixel(150, 100), <int>[255, 0, 0, 255]);
    expect(pixel(199, 199), <int>[255, 0, 0, 255]);
    expect(pixel(100, 150), <int>[255, 0, 0, 255]);

    shader.dispose();
    image.dispose();
    picture.dispose();
    backdrop.dispose();
    backdropPicture.dispose();
  });
}

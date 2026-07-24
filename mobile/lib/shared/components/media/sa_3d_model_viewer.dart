import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

/// Publicly-documented sample .glb models from Google's official
/// model-viewer.dev demos. Stand-ins until real SafeHer-branded 3D
/// assets (shield, ring, glasses, glove) are sourced — swap [Sa3DModelViewer.src]
/// once those exist in assets/models/.
abstract final class SaSampleModels {
  static const astronaut = 'https://modelviewer.dev/shared-assets/models/Astronaut.glb';
  static const shoe = 'https://modelviewer.dev/shared-assets/models/MaterialsVariantsShoe.glb';

  const SaSampleModels._();
}

/// Wraps `model_viewer_plus` with SafeHer defaults (auto-rotate, camera
/// controls, transparent background so it sits naturally on glass cards).
class Sa3DModelViewer extends StatelessWidget {
  const Sa3DModelViewer({
    required this.src,
    required this.alt,
    super.key,
    this.autoRotate = true,
    this.cameraControls = true,
    this.height = 220,
  });

  final String src;
  final String alt;
  final bool autoRotate;
  final bool cameraControls;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: alt,
      child: SizedBox(
        height: height,
        child: ModelViewer(
          src: src,
          alt: alt,
          autoRotate: autoRotate,
          cameraControls: cameraControls,
          backgroundColor: Colors.transparent,
        ),
      ),
    );
  }
}

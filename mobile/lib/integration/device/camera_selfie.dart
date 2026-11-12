import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:geolocator/geolocator.dart' show Geolocator;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';

import '../../features/punch/punch_models.dart';

/// Selfie pela câmera frontal do aparelho, com checagem de rosto LOCAL.
///
/// - Permissão: o app declara CAMERA, então o plugin PEDE a permissão na
///   primeira foto (diálogo do Android). Negada, a tela oferece abrir as
///   configurações do app.
/// - A foto é tirada na hora (câmera do sistema); não se escolhe da galeria.
/// - O ML Kit roda no aparelho e só confere que há UM rosto na foto. Ele não
///   identifica a pessoa e nada é enviado ao Google.
/// - A imagem sai reduzida (até 200 KB, o limite do servidor) e não é
///   guardada pelo app: segue direto para o envio.
/// - Cada falha volta com um código curto (sem imagem, caminho ou dado
///   pessoal), mostrado junto do aviso para diagnóstico.
class CameraSelfie implements SelfieCamera {
  CameraSelfie({ImagePicker? picker}) : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  static const maxBytes = 200000;

  @override
  Future<SelfieResult> capture() async {
    final XFile? photo;
    try {
      photo = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 640,
        maxHeight: 640,
        imageQuality: 60,
        requestFullMetadata: false,
      );
    } on PlatformException catch (e) {
      return switch (e.code) {
        'camera_access_denied' => SelfieResult.failed(SelfieProblem.cameraDenied, detail: 'picker:${e.code}'),
        'no_available_camera' => SelfieResult.failed(SelfieProblem.noCamera, detail: 'picker:${e.code}'),
        _ => SelfieResult.failed(SelfieProblem.unavailable, detail: 'picker:${e.code}'),
      };
    } catch (e) {
      return SelfieResult.failed(SelfieProblem.unavailable, detail: 'picker:${e.runtimeType}');
    }
    if (photo == null) return const SelfieResult.failed(SelfieProblem.cancelled);

    final Uint8List bytes;
    try {
      bytes = await photo.readAsBytes();
    } catch (e) {
      return SelfieResult.failed(SelfieProblem.unreadable, detail: 'read:${e.runtimeType}');
    }
    if (bytes.isEmpty) return const SelfieResult.failed(SelfieProblem.unreadable, detail: 'read:empty');

    final detector = FaceDetector(options: FaceDetectorOptions(minFaceSize: 0.15, performanceMode: FaceDetectorMode.accurate));
    try {
      final faces = await detector.processImage(InputImage.fromFilePath(photo.path));
      if (faces.isEmpty) return const SelfieResult.failed(SelfieProblem.noFace);
      if (faces.length > 1) return const SelfieResult.failed(SelfieProblem.manyFaces);
    } on PlatformException catch (e) {
      return SelfieResult.failed(SelfieProblem.checkFailed, detail: 'face:${e.code}');
    } catch (e) {
      return SelfieResult.failed(SelfieProblem.checkFailed, detail: 'face:${e.runtimeType}');
    } finally {
      await detector.close();
    }

    if (bytes.length > maxBytes) return const SelfieResult.failed(SelfieProblem.tooLarge);
    return SelfieResult.ok(bytes);
  }

  @override
  Future<void> openSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (_) {
      // Sem tela de configurações: a pessoa libera pelo próprio Android.
    }
  }
}

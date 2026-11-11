import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';

import '../../features/punch/punch_models.dart';

/// Selfie pela câmera frontal do aparelho, com checagem de rosto LOCAL.
///
/// - A foto é tirada na hora (câmera do sistema); não se escolhe da galeria.
/// - O ML Kit roda no aparelho e só confere que há UM rosto na foto. Ele não
///   identifica a pessoa e nada é enviado ao Google.
/// - A imagem sai reduzida (até 200 KB, o limite do servidor) e não é
///   guardada pelo app: segue direto para o envio.
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
    } catch (_) {
      return const SelfieResult.failed(SelfieProblem.unavailable);
    }
    if (photo == null) return const SelfieResult.failed(SelfieProblem.cancelled);

    final detector = FaceDetector(options: FaceDetectorOptions(minFaceSize: 0.2, performanceMode: FaceDetectorMode.accurate));
    try {
      final faces = await detector.processImage(InputImage.fromFilePath(photo.path));
      if (faces.isEmpty) return const SelfieResult.failed(SelfieProblem.noFace);
      if (faces.length > 1) return const SelfieResult.failed(SelfieProblem.manyFaces);
    } catch (_) {
      return const SelfieResult.failed(SelfieProblem.unavailable);
    } finally {
      await detector.close();
    }

    final bytes = await photo.readAsBytes();
    if (bytes.isEmpty) return const SelfieResult.failed(SelfieProblem.unavailable);
    if (bytes.length > maxBytes) return const SelfieResult.failed(SelfieProblem.tooLarge);
    return SelfieResult.ok(bytes);
  }
}

import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class ImageHelper {
  static final ImageHelper _instance = ImageHelper._internal();
  factory ImageHelper() => _instance;
  ImageHelper._internal();

  final ImagePicker _picker = ImagePicker();

  /// Selecciona múltiples imágenes (Galería).
  /// Si no se envían [minWidth]/[minHeight], se mantienen las dimensiones originales.
  Future<List<File>> pickMultipleImages({
    int quality = 70,
    int? minWidth,
    int? minHeight,
  }) async {
    try {
      final List<XFile> pickedFiles = await _picker.pickMultiImage();
      if (pickedFiles.isEmpty) return [];

      final List<Future<File?>> tasks = pickedFiles.map((xFile) {
        return compressFile(
          File(xFile.path),
          quality: quality,
          minWidth: minWidth,
          minHeight: minHeight,
        );
      }).toList();

      final results = await Future.wait(tasks);
      return results.whereType<File>().toList();
    } catch (e) {
      debugPrint("Error seleccionando imágenes: $e");
      return [];
    }
  }

  /// Selecciona una sola imagen (Cámara por defecto) y la comprime.
  /// Las dimensiones originales se preservan (sin minWidth/minHeight por defecto).
  Future<File?> pickImage({
    ImageSource source = ImageSource.camera,
    int quality = 70,
    int? minWidth,
    int? minHeight,
  }) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: source);
      if (pickedFile == null) return null;

      return compressFile(
        File(pickedFile.path),
        quality: quality,
        minWidth: minWidth,
        minHeight: minHeight,
      );
    } catch (e) {
      debugPrint("Error capturando imagen: $e");
      return null;
    }
  }

  /// Comprime un [Uint8List] (p.ej. bytes decodificados de Base64) y retorna
  /// los bytes comprimidos listos para subir a Supabase Storage.
  /// Las dimensiones originales se preservan; solo se reduce la calidad.
  Future<Uint8List?> compressBytes(List<int> bytes, {int quality = 70}) async {
    try {
      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final inputPath = '${dir.path}/img_in_$ts.jpg';
      final outputPath = '${dir.path}/img_out_$ts.jpg';

      await File(inputPath).writeAsBytes(bytes);

      final XFile? result = await FlutterImageCompress.compressAndGetFile(
        inputPath,
        outputPath,
        quality: quality,
        // Sin minWidth/minHeight → preserva dimensiones originales
      );

      if (result == null) return null;
      return await File(result.path).readAsBytes();
    } catch (e) {
      debugPrint("Error comprimiendo bytes: $e");
      return null;
    }
  }

  Future<File?> compressFile(
    File file, {
    required int quality,
    int? minWidth,
    int? minHeight,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final name = p.basenameWithoutExtension(file.path);
      final targetPath =
          '${dir.path}/${name}_c${DateTime.now().millisecondsSinceEpoch}.jpg';

      // No pasamos minWidth/minHeight cuando son null: la librería preserva
      // las dimensiones originales. Pasar 0 hace que retorne null (bug conocido).
      final XFile? result = (minWidth != null || minHeight != null)
          ? await FlutterImageCompress.compressAndGetFile(
              file.absolute.path,
              targetPath,
              quality: quality,
              minWidth: minWidth ?? 1920,
              minHeight: minHeight ?? 1080,
            )
          : await FlutterImageCompress.compressAndGetFile(
              file.absolute.path,
              targetPath,
              quality: quality,
            );

      if (result == null) return null;
      return File(result.path);
    } catch (e) {
      debugPrint("Error comprimiendo: $e");
      return null;
    }
  }
}

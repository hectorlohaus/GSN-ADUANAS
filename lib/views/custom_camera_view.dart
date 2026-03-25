import 'package:prueba_match/utils/app_colors.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

enum CameraMode { selfie, document, fullScreen }

class CustomCameraView extends StatefulWidget {
  final CameraMode mode;

  const CustomCameraView({super.key, required this.mode});

  @override
  State<CustomCameraView> createState() => _CustomCameraViewState();
}

class _CustomCameraViewState extends State<CustomCameraView> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        throw Exception('No se encontraron cámaras');
      }

      CameraDescription selectedCamera;
      if (widget.mode == CameraMode.selfie) {
        selectedCamera = _cameras!.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras!.first,
        );
      } else {
        selectedCamera = _cameras!.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => _cameras!.first,
        );
      }

      _controller = CameraController(
        selectedCamera,
        ResolutionPreset.max,
        enableAudio: false,
      );

      await _controller!.initialize();
      // Asegurar que la foto final se guarde siempre verticalmente (Portrait)
      await _controller!.lockCaptureOrientation(DeviceOrientation.portraitUp);

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    } catch (e) {
      debugPrint('Error al inicializar cámara: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al inicializar la cámara')),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_controller!.value.isTakingPicture) return;

    try {
      if (mounted) {
        setState(() {
          _isInitializing = true;
        });
      }

      final XFile image = await _controller!.takePicture();
      File finalFile = File(image.path);

      if (widget.mode == CameraMode.selfie) {
        final flippedFile = await compute(_flipImageHorizontally, finalFile.path);
        if (flippedFile != null) {
          finalFile = flippedFile;
        }
      }

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
        Navigator.pop(context, finalFile);
      }
    } catch (e) {
      debugPrint('Error capturando foto: $e');
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al tomar la foto')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing || _controller == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.textPrimary)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(child: _buildCameraPreview()),
          Positioned.fill(child: _buildOverlay()),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: Icon(Icons.close, color: AppColors.textPrimary, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),
                GestureDetector(
                  onTap: _takePicture,
                  child: Container(
                    height: 80,
                    width: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.textPrimary, width: 4),
                      color: AppColors.textPrimary.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                SizedBox(width: 48), // Spacer for alignment
              ],
            ),
          ),
          if (widget.mode != CameraMode.fullScreen)
            Positioned(
              top: 50,
              left: 0,
              right: 0,
              child: Text(
                widget.mode == CameraMode.selfie ? 'Centra tu rostro en el óvalo' : 'Centra el documento en el recuadro',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: AppColors.background, blurRadius: 4)],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    final size = MediaQuery.of(context).size;
    if (_controller == null || !_controller!.value.isInitialized) {
      return Container(color: AppColors.background);
    }

    // La relación de aspecto reportada por la cámara (generalmente apaisada, ej. 1.77)
    double cameraAspect = _controller!.value.aspectRatio;
    
    // Si la pantalla está en vertical, invertimos la proporción para que CameraPreview
    // la entienda como vertical.
    if (size.width < size.height) {
      cameraAspect = 1 / cameraAspect;
    }

    // Quitamos 'Transform.scale' para que CameraPreview no "haga zoom" en la pantalla,
    // de esta manera la previsualización coincide 100% con la foto final que se guarda.
    return Center(
      child: AspectRatio(
        aspectRatio: cameraAspect,
        child: CameraPreview(_controller!),
      ),
    );
  }

  Widget _buildOverlay() {
    if (widget.mode == CameraMode.fullScreen) {
      return const SizedBox.shrink(); // No overlay para fullScreen
    }

    final size = MediaQuery.of(context).size;
    final bool isSelfie = widget.mode == CameraMode.selfie;
    
    // Configuración para el tamaño del recorte
    final double holeWidth = isSelfie ? size.width * 0.85 : size.width * 0.9;
    final double holeHeight = isSelfie ? size.height * 0.65 : (size.width * 0.9) / 1.6;
    
    // Radio responsivo
    final BorderRadius borderRadius = isSelfie 
        ? BorderRadius.circular(holeHeight) // Forma ovalada/píldora
        : BorderRadius.circular(16.0); // Rectángulo redondeado

    return Stack(
      children: [
        // Capa oscura con recorte (hueco)
        ColorFiltered(
          colorFilter: const ColorFilter.mode(
            Colors.black54,
            BlendMode.srcOut,
          ),
          child: Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: Colors.transparent,
                ),
                child: Align(
                  alignment: Alignment.center,
                  child: Container(
                    width: holeWidth,
                    height: holeHeight,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: borderRadius,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Marco de color sobre el recorte para hacerlo visible
        Align(
          alignment: Alignment.center,
          child: SizedBox(
            width: holeWidth,
            height: holeHeight,
            child: CustomPaint(
              painter: DottedBorderPainter(
                color: Colors.blueAccent,
                strokeWidth: 2.0,
                gap: 6.0,
                borderRadius: borderRadius,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class DottedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;
  final BorderRadius borderRadius;

  DottedBorderPainter({
    required this.color,
    this.strokeWidth = 2.0,
    this.gap = 5.0,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final RRect rrect = borderRadius.toRRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final Path path = Path()..addRRect(rrect);
    
    final Path dashPath = Path();
    double distance = 0.0;
    for (ui.PathMetric pathMetric in path.computeMetrics()) {
      while (distance < pathMetric.length) {
        dashPath.addPath(
          pathMetric.extractPath(distance, distance + gap),
          Offset.zero,
        );
        distance += gap * 2;
      }
      distance = 0.0;
    }

    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(covariant DottedBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
           oldDelegate.strokeWidth != strokeWidth ||
           oldDelegate.gap != gap ||
           oldDelegate.borderRadius != borderRadius;
  }
}

Future<File?> _flipImageHorizontally(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    img.Image? decodedImage = img.decodeImage(bytes);
    if (decodedImage != null) {
      decodedImage = img.flipHorizontal(decodedImage);
      final newBytes = img.encodeJpg(decodedImage, quality: 100);
      final newFile = await File(path).writeAsBytes(newBytes);
      return newFile;
    }
  } catch (e) {
    debugPrint("Error flipping: $e");
  }
  return null;
}

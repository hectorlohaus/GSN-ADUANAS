import 'package:prueba_match/utils/app_colors.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:prueba_match/services/registro_service.dart';
import 'package:prueba_match/views/vehicle_data_view.dart';
import 'package:prueba_match/utils/image_helper.dart';
import 'package:prueba_match/views/custom_camera_view.dart';
import 'package:prueba_match/widgets/step_header.dart';

enum PhotoType { bl }

class TakePhotoView extends StatefulWidget {
  final int registroId;
  final PhotoType photoType;

  const TakePhotoView({
    super.key,
    required this.registroId,
    required this.photoType,
  });

  @override
  State<TakePhotoView> createState() => _TakePhotoViewState();
}

class _TakePhotoViewState extends State<TakePhotoView> {
  final RegistroService _registroService = RegistroService();
  final ImageHelper _imageHelper = ImageHelper();

  bool _isUploading = false;
  File? _capturedImage;
  String? _tipoVehiculo;
  bool _isLoadingType = true;

  @override
  void initState() {
    super.initState();
    _loadTipoVehiculo();
  }

  Future<void> _loadTipoVehiculo() async {
    final tipo = await _registroService.obtenerTipoVehiculo(widget.registroId);
    if (mounted) {
      setState(() {
        _tipoVehiculo = tipo;
        _isLoadingType = false;
      });
    }
  }

  Future<void> _takePicture() async {
    final File? image = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CustomCameraView(mode: CameraMode.fullScreen),
      ),
    );
    if (image != null) {
      final compressed = await _imageHelper.compressFile(image, quality: 80);
      setState(() => _capturedImage = compressed ?? image);
    }
  }

  Future<void> _confirmAndUpload() async {
    if (_capturedImage == null) return;
    setState(() => _isUploading = true);

    try {
      final imageBase64 = base64Encode(await _capturedImage!.readAsBytes());

      await _registroService.actualizarFoto(
        registroId: widget.registroId,
        fotoBase64: imageBase64,
        tipo: widget.photoType,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Foto del documento guardada.'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => VehicleDataView(registroId: widget.registroId),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar la foto: ${e.toString()}')),
        );
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      backgroundColor: AppColors.background, // Background
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const StepHeader(
              currentStep: 4,
              title: 'Documento de Transporte',
              subtitle: 'Captura el Bill of Lading o Guía de Despacho.',
            ),
            _buildInstructionCard(
              "Por favor, captura una foto clara del documento de transporte (BL o Guía).",
            ),
            const SizedBox(height: 24),
            _buildPhotoCard(
              "Documento (BL)",
              "Toca para capturar",
              _capturedImage,
              Icons.description,
              _takePicture,
            ),
            const SizedBox(height: 32),
            if (_isUploading || _isLoadingType)
              Column(
                children: [
                  const CircularProgressIndicator(color: AppColors.accent),
                  const SizedBox(height: 16),
                  Text(
                    _isUploading ? "Guardando documento..." : "Cargando...",
                    style: const TextStyle(
                      color: AppColors.textSecondary, // Text Secondary
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            else if (_capturedImage != null)
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _confirmAndUpload,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text(
                    "CONFIRMAR DOCUMENTO",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent, // Acento
                    foregroundColor: AppColors.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 4,
                  ),
                ),
              )
            else if (_tipoVehiculo == 'Vehiculo Menor')
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (context) => VehicleDataView(registroId: widget.registroId),
                      ),
                    );
                  },
                  icon: const Icon(Icons.skip_next),
                  label: const Text(
                    "NO APLICA AL BL",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent, // Acento enlace
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionCard(String text) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface, // Superficie
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.accent), // Acento
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary, // Blanco principal
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoCard(
    String title,
    String subtitle,
    File? file,
    IconData icon,
    VoidCallback onTap,
  ) {
    final bool hasFile = file != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 220,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surface, // Superficie en vez de blanco
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasFile ? AppColors.accent : AppColors.border,
            width: hasFile ? 2 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasFile)
                Image.file(file, fit: BoxFit.cover)
              else
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: AppColors.background, // Contraste interno
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        icon,
                        size: 40,
                        color: AppColors.accent, // Ícono destacado
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary, // Blanco principal
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              if (hasFile)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: AppColors.surface, // Superficie dark
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.edit, size: 20, color: AppColors.accent),
                  ),
                ),
              if (hasFile)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    color: AppColors.background26, // Overlay oscuro transparente
                    child: Text(
                      title.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

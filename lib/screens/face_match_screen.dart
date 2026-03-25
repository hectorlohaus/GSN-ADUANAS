import 'package:prueba_match/utils/app_colors.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:prueba_match/models/chofer_match_data.dart';
import 'package:prueba_match/services/face_match_service.dart';
import 'package:prueba_match/utils/image_helper.dart';
import 'package:prueba_match/views/confirmation_view.dart';
import 'package:prueba_match/models/license_data.dart';
import 'package:prueba_match/views/license_confirmation_view.dart';
import 'package:prueba_match/views/custom_camera_view.dart';

enum FaceMatchMode { match, scanOnly }

class FaceMatchScreen extends StatefulWidget {
  final int registroId;
  final FaceMatchMode mode;
  final ChoferMatchData? existingChoferData; // For scanOnly mode

  const FaceMatchScreen({
    super.key,
    required this.registroId,
    this.mode = FaceMatchMode.match,
    this.existingChoferData,
  });

  @override
  State<FaceMatchScreen> createState() => _FaceMatchScreenState();
}

class _FaceMatchScreenState extends State<FaceMatchScreen> {
  final FaceMatchService _faceMatchService = FaceMatchService();
  final ImageHelper _imageHelper = ImageHelper();

  // Files
  File? _selfieFile;
  File? _documentFile;

  // State
  bool _isProcessing = false;
  String? _statusMessage;

  Future<void> _pickPhoto(bool isSelfie) async {
    final File? file = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CustomCameraView(mode: isSelfie ? CameraMode.selfie : CameraMode.document),
      ),
    );
    if (file != null) {
      final compressedFile = await _imageHelper.compressFile(file, quality: 80);
      setState(() {
        if (isSelfie) {
          _selfieFile = compressedFile ?? file;
        } else {
          _documentFile = compressedFile ?? file;
        }
      });
    }
  }

  Future<void> _process() async {
    // Validation
    if (widget.mode == FaceMatchMode.match && _selfieFile == null) {
      _showSnack("Debes capturar la selfie.");
      return;
    }
    if (_documentFile == null) {
      _showSnack("Debes capturar el documento.");
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = "Procesando...";
    });

    try {
      if (widget.mode == FaceMatchMode.match) {
        // FULL VERIFICATION (Match + OCR)
        final response = await _faceMatchService.fullVerification(
          documentFile: _documentFile!,
          selfieFile: _selfieFile!,
        );

        final data = response['data'];
        final bool verified = data['identity_verified'] ?? false;
        final docData = data['document'];
        final matchData = data['face_match'];

        if (!verified) {
          final sim = matchData?['similarity_percentage'] ?? 0;
          _showSnack("Identidad no verificada. Similitud: $sim%");
          return;
        }

        // Convert files to Base64 to mimic FaceTec return
        final selfieBytes = await _selfieFile!.readAsBytes();
        final docBytes = await _documentFile!.readAsBytes();
        final String livenessImageBase64 = base64Encode(selfieBytes);
        final String idFaceBase64 = base64Encode(docBytes);

        // Map to ChoferMatchData
        final ocrData = ChoferMatchData(
          nombres: docData['nombres'],
          apellidos: docData['apellidos'],
          run: docData['rut'],
          nacionalidad: docData['nacionalidad'],
          fechaEmision: docData['fecha_vencimiento'],
          fechaNacimiento: docData['fecha_nacimiento'],
          fechaVencimiento: docData['fecha_vencimiento'],
          numeroDocumento: docData['numero_documento'],
          fotoMatch: livenessImageBase64,
          fotoCaraCarnet: idFaceBase64,
        );

        if (!mounted) return;

        // Navigate to ConfirmationView
        // We expect ConfirmationView to return confirmed data
        final ChoferMatchData? confirmedData = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ConfirmationView(
              initialData: ocrData,
              registroId: widget.registroId,
            ),
          ),
        );

        // If verified, pop with success data
        if (confirmedData != null && mounted) {
          Navigator.pop(context, confirmedData);
        }
      } else {
        // SCAN ONLY (OCR)
        final response = await _faceMatchService.processOCR(_documentFile!);
        final data = response['data'];
        final docBytes = await _documentFile!.readAsBytes();
        final String frontImageBase64 = base64Encode(docBytes);

        final licenseData = LicenseData(
          rut: data['rut'],
          nombres: data['nombres'],
          apellidos: data['apellidos'],
          fechaNacimiento: data['fecha_nacimiento'],
          fechaEmision: data['fecha_emision'],
          fechaVencimiento: data['fecha_vencimiento'],
          clase: data['clase_licencia'],
          direccion: data['direccion'],
          fotoLicencia: frontImageBase64,
        );

        if (!mounted) return;

        // Navigate to LicenseConfirmationView
        final LicenseData? confirmedData = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LicenseConfirmationView(
              initialData: licenseData,
              registroId: widget.registroId,
            ),
          ),
        );

        // If verified, pop with success data
        if (confirmedData != null && mounted) {
          Navigator.pop(context, confirmedData);
        }
      }
    } catch (e) {
      _showSnack("Error: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = null;
        });
      }
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final bool isMatchMode = widget.mode == FaceMatchMode.match;
    final String title = isMatchMode
        ? "Verificación Facial"
        : "Escaneo de Licencia";
    final String instruction = isMatchMode
        ? "Por favor, captura una selfie clara y una foto de tu documento de identidad."
        : "Captura una foto clara de la licencia de conducir.";

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      backgroundColor: AppColors.background, // Scaffold background
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildInstructionCard(instruction),
            const SizedBox(height: 24),
            if (isMatchMode) ...[
              _buildPhotoCard(
                "Selfie",
                "Toca para capturar",
                _selfieFile,
                Icons.face_retouching_natural,
                () => _pickPhoto(true),
              ),
              const SizedBox(height: 16),
            ],
            _buildPhotoCard(
              isMatchMode ? "Carnet / Documento" : "Licencia de Conducir",
              "Toca para capturar",
              _documentFile,
              Icons.credit_card,
              () => _pickPhoto(false),
            ),
            const SizedBox(height: 32),
            if (_isProcessing)
              Column(
                children: [
                  const CircularProgressIndicator(color: AppColors.accent),
                  const SizedBox(height: 16),
                  Text(
                    _statusMessage ?? "Procesando...",
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _process,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(
                    isMatchMode ? "VALIDAR IDENTIDAD" : "VALIDAR LICENCIA",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent, // Acento
                    foregroundColor: AppColors.background, // Contraste
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 4,
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
        color: AppColors.surface, // Superficie dark
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.accent), // Ícono destacado
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary, // Texto principal
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
          color: AppColors.surface, // Superficie interna
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
                        color: AppColors.background, // Contraste inverso
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        icon,
                        size: 40,
                        color: AppColors.accent, // Acento
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
                      color: AppColors.surface, // Ocultar superposición brillante
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
                    color: AppColors.background26, // Overlay semi-transparente oscuro
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

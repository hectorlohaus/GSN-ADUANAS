import 'package:prueba_match/utils/app_colors.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/image_helper.dart';
import '../utils/rut_utils.dart';
import '../services/face_match_service.dart';
import '../views/custom_camera_view.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  // Servicios y Controladores
  final _rutController = TextEditingController();
  final ImageHelper _imageHelper = ImageHelper();
  final FaceMatchService _apiService = FaceMatchService();

  // Archivos seleccionados
  File? _selfieFile;
  File? _documentFile;

  // Estados de salud del sistema
  bool _isHealthChecking = true;
  bool _isSystemHealthy = false;

  // Estados de carga por cada acción
  bool _isOcrProcessing = false;
  bool _isFaceMatchProcessing = false;
  bool _isFullVerificationProcessing = false;

  // Resultados de la API para mostrar en pantalla
  Map<String, dynamic>? _ocrData;
  Map<String, dynamic>? _faceMatchData;

  String? _rutError;

  @override
  void initState() {
    super.initState();
    _checkApiHealth();
  }

  /// Verifica el estado de la API y sus componentes
  Future<void> _checkApiHealth() async {
    if (!mounted) return;
    setState(() {
      _isHealthChecking = true;
    });

    try {
      final response = await _apiService.checkHealth();
      if (response['status'] == 'success') {
        final services = response['data']['services'] as Map<String, dynamic>;
        bool allOk = services.values.every((status) => status == true);

        if (mounted) {
          setState(() {
            _isSystemHealthy = allOk;
            _isHealthChecking = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSystemHealthy = false;
          _isHealthChecking = false;
        });
      }
    }
  }

  /// Inicia sesión automáticamente con las credenciales proporcionadas

  /// Maneja el cambio de texto en el RUT para formateo y validación inmediata
  void _handleRutChange(String value) {
    final cleaned = RutUtils.clean(value);
    final formatted = RutUtils.format(cleaned);

    _rutController.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );

    setState(() {
      _rutError = RutUtils.isValid(cleaned) ? null : "RUT no válido";
    });
  }

  /// Llama al helper para capturar y comprimir imágenes
  Future<void> _pickPhoto(bool isSelfie) async {
    final File? file = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CustomCameraView(mode: isSelfie ? CameraMode.selfie : CameraMode.document),
      ),
    );
    if (file != null) {
      final compressed = await _imageHelper.compressFile(file, quality: 80);
      setState(() {
        if (isSelfie) {
          _selfieFile = compressed ?? file;
        } else {
          _documentFile = compressed ?? file;
        }
        _ocrData = null;
        _faceMatchData = null;
      });
    }
  }

  /// Ejecuta solo la extracción de texto del documento (OCR)
  Future<void> _runOcrOnly() async {
    if (_documentFile == null) {
      _showSnackBar(
        "Por favor, selecciona la foto del documento primero.",
        AppColors.warning,
      );
      return;
    }
    setState(() {
      _isOcrProcessing = true;
      _ocrData = null;
    });

    try {
      final response = await _apiService.processOCR(_documentFile!);
      if (mounted) {
        setState(() => _ocrData = response['data']);
        _showSnackBar("OCR completado exitosamente.", AppColors.success);
      }
    } catch (e) {
      _showSnackBar(e.toString(), AppColors.danger);
    } finally {
      if (mounted) setState(() => _isOcrProcessing = false);
    }
  }

  /// Ejecuta solo la comparación facial
  Future<void> _runFaceMatchOnly() async {
    final rut = RutUtils.clean(_rutController.text);
    if (!RutUtils.isValid(rut) ||
        _selfieFile == null ||
        _documentFile == null) {
      _showSnackBar("RUT, Selfie y Documento son obligatorios.", AppColors.warning);
      return;
    }
    setState(() {
      _isFaceMatchProcessing = true;
      _faceMatchData = null;
    });

    try {
      final response = await _apiService.compareFaces(
        image1: _selfieFile!,
        image2: _documentFile!,
      );
      if (mounted) {
        setState(() => _faceMatchData = response['data']);
        _showSnackBar("Comparación finalizada.", AppColors.accent);
      }
    } catch (e) {
      _showSnackBar(e.toString(), AppColors.danger);
    } finally {
      if (mounted) setState(() => _isFaceMatchProcessing = false);
    }
  }

  /// Realiza la verificación completa y sube a Supabase
  Future<void> _runFullVerification() async {
    final rut = RutUtils.clean(_rutController.text);
    if (!RutUtils.isValid(rut) ||
        _selfieFile == null ||
        _documentFile == null) {
      _showSnackBar("Faltan datos para realizar la validación.", AppColors.warning);
      return;
    }

    // Asegurar que haya sesión activa antes de subir a Storage

    setState(() => _isFullVerificationProcessing = true);

    try {
      _showSnackBar("Iniciando validación integral...", AppColors.accent);

      final response = await _apiService.fullVerification(
        documentFile: _documentFile!,
        selfieFile: _selfieFile!,
      );

      final data = response['data'];
      final bool verified = data['identity_verified'] ?? false;

      if (!verified) {
        _showSnackBar("Identidad no verificada.", AppColors.danger);
        setState(() => _isFullVerificationProcessing = false);
        return;
      }

      final supabase = Supabase.instance.client;
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      _showFeedbackDialog("Identidad confirmada. Guardando archivos...");

      final selfiePath = 'verificados/$rut/selfie_$timestamp.jpg';
      await supabase.storage
          .from('documentos')
          .upload(selfiePath, _selfieFile!);
      final selfieUrl = supabase.storage
          .from('documentos')
          .getPublicUrl(selfiePath);

      final docPath = 'verificados/$rut/documento_$timestamp.jpg';
      await supabase.storage.from('documentos').upload(docPath, _documentFile!);
      final docUrl = supabase.storage.from('documentos').getPublicUrl(docPath);

      await supabase.from('registros').insert({
        'rut_ingresado': RutUtils.format(rut),
        'rut_ocr': data['document']['rut'],
        'nombre_completo': data['document']['nombre_completo'],
        'selfie_url': selfieUrl,
        'documento_url': docUrl,
        'similitud': data['face_match']?['similarity_percentage'] ?? 0,
        'fecha_registro': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        Navigator.pop(context); // Cerrar diálogo
        _showSnackBar("¡Registro oficial guardado con éxito!", AppColors.success);
        _resetForm();
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnackBar("Error en registro: $e", AppColors.danger);
    } finally {
      if (mounted) setState(() => _isFullVerificationProcessing = false);
    }
  }

  void _resetForm() {
    setState(() {
      _rutController.clear();
      _selfieFile = null;
      _documentFile = null;
      _ocrData = null;
      _faceMatchData = null;
      _rutError = null;
    });
  }

  void _showSnackBar(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showFeedbackDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text("Portal de Identidad"),
        centerTitle: true,
        actions: [_buildHealthIndicatorDot()],
      ),
      body: Column(
        children: [
          _buildSystemStatusBanner(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildPhotoCaptureSection(),
                  const SizedBox(height: 16),
                  _buildOcrSection(),
                  const SizedBox(height: 16),
                  _buildFaceMatchSection(),
                  const SizedBox(height: 16),
                  _buildRegistrationSection(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- COMPONENTES DE INTERFAZ ---

  Widget _buildSystemStatusBanner() {
    final color = _isSystemHealthy
        ? AppColors.success
        : AppColors.danger;
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(
                  _isSystemHealthy ? Icons.verified_user : Icons.report_problem,
                  color: AppColors.textPrimary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  _isSystemHealthy
                      ? "SISTEMA OPERATIVO"
                      : "SISTEMA CON PROBLEMAS",
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          if (_isHealthChecking)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.textPrimary,
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh, color: AppColors.textPrimary, size: 20),
              onPressed: _checkApiHealth,
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }

  Widget _buildHealthIndicatorDot() {
    return Container(
      width: 12,
      height: 12,
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _isSystemHealthy ? AppColors.success : AppColors.danger,
        boxShadow: [
          BoxShadow(
            color: (_isSystemHealthy ? AppColors.success : AppColors.danger).withValues(alpha: 
              0.5,
            ),
            blurRadius: 4,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoCaptureSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              "1. Captura de Imágenes",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildImageButton(
                    "Selfie",
                    _selfieFile,
                    Icons.face,
                    () => _pickPhoto(true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildImageButton(
                    "Carnet",
                    _documentFile,
                    Icons.credit_card,
                    () => _pickPhoto(false),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOcrSection() {
    return _FeatureCard(
      title: "2. Extracción de Datos (OCR)",
      icon: Icons.document_scanner,
      isLoading: _isOcrProcessing,
      onPressed: _runOcrOnly,
      buttonText: "Extraer Datos",
      content: _ocrData == null
          ? const Text(
              "Captura el documento para ver los datos.",
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow("RUT:", _ocrData!['rut']),
                _infoRow("Nombre:", _ocrData!['nombre_completo']),
                _infoRow("Tipo:", _ocrData!['document_type']),
                _infoRow("Nacionalidad:", _ocrData!['nacionalidad']),
              ],
            ),
    );
  }

  Widget _buildFaceMatchSection() {
    return _FeatureCard(
      title: "3. Comparación Biométrica",
      icon: Icons.face_retouching_natural,
      isLoading: _isFaceMatchProcessing,
      onPressed: _runFaceMatchOnly,
      buttonText: "Comparar Rostros",
      content: Column(
        children: [
          TextField(
            controller: _rutController,
            onChanged: _handleRutChange,
            decoration: InputDecoration(
              labelText: "RUT para auditoría",
              errorText: _rutError,
              prefixIcon: const Icon(Icons.fingerprint),
              isDense: true,
            ),
          ),
          if (_faceMatchData != null)
            Padding(
              padding: const EdgeInsets.only(top: 15),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _faceMatchData!['verified']
                      ? AppColors.success
                      : AppColors.danger,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _faceMatchData!['verified']
                        ? AppColors.success
                        : AppColors.danger,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _faceMatchData!['verified']
                          ? Icons.check_circle
                          : Icons.cancel,
                      color: _faceMatchData!['verified']
                          ? AppColors.success
                          : AppColors.danger,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      "Similitud: ${_faceMatchData!['similarity_percentage']}%",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRegistrationSection() {
    return _FeatureCard(
      title: "4. Registro de Identidad",
      icon: Icons.cloud_done,
      isLoading: _isFullVerificationProcessing,
      onPressed: _runFullVerification,
      buttonText: "Finalizar Registro",
      buttonColor: AppColors.accent,
      content: const Text(
        "Realiza la validación integral y guarda los archivos en Supabase.",
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _buildImageButton(
    String label,
    File? file,
    IconData icon,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          color: AppColors.textPrimary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: file == null ? AppColors.border : AppColors.accent,
            width: 2,
          ),
        ),
        child: file == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: AppColors.textSecondary, size: 35),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(file, fit: BoxFit.cover),
              ),
      ),
    );
  }

  Widget _infoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            "$label ",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          Expanded(
            child: Text(
              "${value ?? '---'}",
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget content;
  final bool isLoading;
  final VoidCallback onPressed;
  final String buttonText;
  final Color buttonColor;

  const _FeatureCard({
    required this.title,
    required this.icon,
    required this.content,
    required this.isLoading,
    required this.onPressed,
    required this.buttonText,
    this.buttonColor = Colors.blueAccent,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 22, color: buttonColor),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            content,
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: isLoading ? null : onPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: buttonColor,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textPrimary,
                        ),
                      )
                    : Text(
                        buttonText,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

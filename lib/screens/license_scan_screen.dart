import 'package:prueba_match/utils/app_colors.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:prueba_match/models/chofer_match_data.dart';
import 'package:prueba_match/services/face_match_service.dart';
import 'package:prueba_match/utils/image_helper.dart';
import 'package:prueba_match/utils/rut_utils.dart';
import 'package:prueba_match/models/license_data.dart';
import 'package:prueba_match/views/license_confirmation_view.dart';
import 'package:prueba_match/views/custom_camera_view.dart';
import 'package:prueba_match/widgets/step_header.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Estados posibles de la pantalla de escaneo de licencia.
enum _LicenseScreenState {
  /// Consultando la BD al inicio — pantalla de carga.
  checking,

  /// Se encontró licencia vigente en BD — resultado "ya verificado".
  alreadyVerified,

  /// No hay licencia en BD — flujo normal de escaneo OCR.
  scanning,
}

class LicenseScanScreen extends StatefulWidget {
  final int registroId;
  final ChoferMatchData? existingChoferData;

  const LicenseScanScreen({
    super.key,
    required this.registroId,
    this.existingChoferData,
  });

  @override
  State<LicenseScanScreen> createState() => _LicenseScanScreenState();
}

class _LicenseScanScreenState extends State<LicenseScanScreen>
    with SingleTickerProviderStateMixin {
  final FaceMatchService _faceMatchService = FaceMatchService();
  final ImageHelper _imageHelper = ImageHelper();
  final _supabase = Supabase.instance.client;

  // Estado principal de la pantalla
  _LicenseScreenState _screenState = _LicenseScreenState.checking;

  // Licencia encontrada en BD (para la vista "ya verificado")
  LicenseData? _foundLicense;

  // Archivos para el flujo de escaneo OCR
  File? _documentFile;

  // Procesamiento OCR
  bool _isProcessing = false;
  String? _statusMessage;

  // Animación de entrada del resultado
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  // ----------------------------------------------------------------
  // CICLO DE VIDA
  // ----------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _checkExistingLicense();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------------
  // VERIFICACIÓN PREVIA EN BD
  // ----------------------------------------------------------------

  Future<void> _checkExistingLicense() async {
    final String? rutChofer = widget.existingChoferData?.run;

    if (rutChofer == null || rutChofer.isEmpty) {
      if (mounted) setState(() => _screenState = _LicenseScreenState.scanning);
      return;
    }

    // Pequeña pausa para que el usuario vea la pantalla de carga
    await Future.delayed(const Duration(milliseconds: 800));

    try {
      // 1. Obtener id_chofer
      final choferRow = await _supabase
          .from('choferes')
          .select('id_chofer')
          .eq('rut_chofer', RutUtils.clean(rutChofer))
          .maybeSingle();

      if (choferRow == null) {
        if (mounted) setState(() => _screenState = _LicenseScreenState.scanning);
        return;
      }

      final int idChofer = choferRow['id_chofer'] as int;

      // 2. Buscar licencia vigente (fecha_vencimiento >= hoy)
      final today = DateTime.now();
      final todayStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final licenciaRow = await _supabase
          .from('licencias_conducir')
          .select(
            'id_licencia, rut, nombres, apellidos, direccion, clase, '
            'fecha_emision, fecha_vencimiento, foto_licencia',
          )
          .eq('id_chofer', idChofer)
          .gte('fecha_vencimiento', todayStr)
          .order('fecha_vencimiento', ascending: false)
          .limit(1)
          .maybeSingle();

      if (!mounted) return;

      if (licenciaRow != null) {
        // ✅ Licencia vigente → mostrar resultado "ya verificado"
        setState(() {
          _foundLicense = _licenseDataFromRow(licenciaRow);
          _screenState = _LicenseScreenState.alreadyVerified;
        });
        _animController.forward();
      } else {
        // ❌ Sin licencia vigente → flujo normal
        setState(() => _screenState = _LicenseScreenState.scanning);
      }
    } catch (e) {
      debugPrint('Error al verificar licencia existente: $e');
      if (mounted) setState(() => _screenState = _LicenseScreenState.scanning);
    }
  }

  LicenseData _licenseDataFromRow(Map<String, dynamic> row) {
    return LicenseData(
      rut: row['rut']?.toString(),
      nombres: row['nombres']?.toString(),
      apellidos: row['apellidos']?.toString(),
      direccion: row['direccion']?.toString(),
      clase: row['clase']?.toString(),
      fechaEmision: row['fecha_emision']?.toString(),
      fechaVencimiento: row['fecha_vencimiento']?.toString(),
      fotoLicencia: row['foto_licencia']?.toString(),
    );
  }

  String _formatDateDisplay(String? date) {
    if (date == null || date.isEmpty) return '—';
    try {
      final parts = date.split('-');
      if (parts.length == 3) return '${parts[2]}/${parts[1]}/${parts[0]}';
    } catch (_) {}
    return date;
  }

  // ----------------------------------------------------------------
  // FLUJO NORMAL DE ESCANEO OCR
  // ----------------------------------------------------------------

  Future<void> _pickPhoto() async {
    final File? file = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            const CustomCameraView(mode: CameraMode.document),
      ),
    );
    if (file != null) {
      final compressedFile =
          await _imageHelper.compressFile(file, quality: 80);
      setState(() => _documentFile = compressedFile ?? file);
    }
  }

  DateTime? _parseExpirationDate(String? sourceDate) {
    if (sourceDate == null || sourceDate.isEmpty) return null;
    try {
      const monthMap = {
        'ENE': 1, 'FEB': 2, 'MAR': 3, 'ABR': 4, 'MAY': 5, 'JUN': 6,
        'JUL': 7, 'AGO': 8, 'SEP': 9, 'OCT': 10, 'NOV': 11, 'DIC': 12,
        'JAN': 1, 'APR': 4, 'AUG': 8, 'DEC': 12,
      };
      final parts = sourceDate.trim().split(RegExp(r'[\s./-]+'));
      if (parts.length == 3) {
        int year, month, day;
        if (parts[0].length == 4) {
          year = int.parse(parts[0]);
          month = monthMap[parts[1].toUpperCase()] ?? int.parse(parts[1]);
          day = int.parse(parts[2]);
        } else {
          day = int.parse(parts[0]);
          month = monthMap[parts[1].toUpperCase()] ?? int.parse(parts[1]);
          year = parts[2].length == 2
              ? int.parse('20${parts[2]}')
              : int.parse(parts[2]);
        }
        return DateTime(year, month, day);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _process() async {
    if (_documentFile == null) {
      _showSnack("Debes capturar el documento.");
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = "Procesando...";
    });

    try {
      final response = await _faceMatchService.processOCR(_documentFile!);
      final data = response['data'];

      final String licenseRut = data['rut']?.toString() ?? '';
      final String? expectedRut = widget.existingChoferData?.run;
      final String? fechaControl = data['fecha_ultimo_control']?.toString();

      if (expectedRut != null &&
          RutUtils.clean(licenseRut) != RutUtils.clean(expectedRut)) {
        if (!mounted) return;
        await _showWarningDialog(
          'RUT no coincide',
          Icons.warning_amber_rounded,
          'La licencia escaneada no corresponde al conductor registrado. '
              'Por favor, asegúrese de escanear la licencia correcta.',
        );
        if (mounted) setState(() => _documentFile = null);
        return;
      }

      if (fechaControl == null || fechaControl.trim().isEmpty) {
        if (!mounted) return;
        await _showWarningDialog(
          'Fecha no detectada',
          Icons.warning_amber_rounded,
          'No se pudo extraer la fecha de emisión de la licencia. '
              'Por favor, asegúrese de escanear la licencia claramente, '
              'sin reflejos ni sombras.',
        );
        if (mounted) setState(() => _documentFile = null);
        return;
      }

      final String? fechaVencimiento = data['fecha_vencimiento']?.toString();
      final DateTime? parsedVencimiento =
          _parseExpirationDate(fechaVencimiento);

      if (parsedVencimiento != null) {
        final DateTime today = DateTime(
            DateTime.now().year, DateTime.now().month, DateTime.now().day);
        if (parsedVencimiento.isBefore(today)) {
          if (!mounted) return;
          await _showWarningDialog(
            'Licencia Vencida',
            Icons.block,
            'La licencia escaneada se encuentra vencida. No es posible '
                'autorizar el ingreso con una licencia expirada.',
          );
          if (mounted) setState(() => _documentFile = null);
          return;
        }
      }

      final docBytes = await _documentFile!.readAsBytes();
      final String frontImageBase64 = base64Encode(docBytes);

      final licenseData = LicenseData(
        rut: data['rut'],
        nombres: data['nombres'],
        apellidos: data['apellidos'],
        fechaNacimiento: data['fecha_nacimiento'],
        fechaEmision: data['fecha_ultimo_control'],
        fechaVencimiento: data['fecha_vencimiento'],
        clase: data['clase_licencia'],
        direccion: data['domicilio'],
        fotoLicencia: frontImageBase64,
      );

      if (!mounted) return;

      final LicenseData? confirmedData = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LicenseConfirmationView(
            initialData: licenseData,
            registroId: widget.registroId,
          ),
        ),
      );

      if (confirmedData != null && mounted) {
        Navigator.pop(context, confirmedData);
      }
    } catch (e) {
      _showSnack("Error en el proceso: ${e.toString()}");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _showWarningDialog(
      String title, IconData icon, String message) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: AppColors.surface,
        title: Row(
          children: [
            Icon(icon, color: AppColors.danger, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style:
                      const TextStyle(color: AppColors.textPrimary)),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(color: AppColors.textPrimary70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'ESCANEAR DE NUEVO',
              style: TextStyle(
                  color: AppColors.accent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
    );
  }

  // ----------------------------------------------------------------
  // BUILD PRINCIPAL
  // ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Escaneo de Licencia',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: switch (_screenState) {
        _LicenseScreenState.checking => _buildCheckingView(),
        _LicenseScreenState.alreadyVerified => _buildAlreadyVerifiedView(),
        _LicenseScreenState.scanning => _buildScanView(),
      },
    );
  }

  // ----------------------------------------------------------------
  // VISTA 1: REVISANDO BD (pantalla de carga)
  // ----------------------------------------------------------------

  Widget _buildCheckingView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Ícono animado
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border, width: 2),
              ),
              child: const Center(
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Revisando licencia',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Verificando si el conductor ya\ntiene una licencia registrada en el sistema.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
                height: 1.5,
              ),
            ),
            if (widget.existingChoferData?.run != null) ...[
              const SizedBox(height: 24),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  widget.existingChoferData!.run!,
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------
  // VISTA 2: LICENCIA YA VERIFICADA (resultado)
  // ----------------------------------------------------------------

  Widget _buildAlreadyVerifiedView() {
    final license = _foundLicense!;
    final String nombreCompleto =
        '${license.nombres ?? ''} ${license.apellidos ?? ''}'.trim();

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header paso 3
              const StepHeader(
                currentStep: 3,
                title: 'Licencia verificada',
                subtitle:
                    'Este conductor ya tiene una licencia vigente registrada en el sistema.',
              ),

              // Badge de éxito
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B3A1B),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    // Ícono de éxito
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.verified_rounded,
                        color: Color(0xFF4CAF50),
                        size: 44,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Licencia ya escaneada',
                      style: TextStyle(
                        color: Color(0xFF4CAF50),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'No es necesario volver a escanear',
                      style: TextStyle(
                        color: Color(0xFF81C784),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Datos de la licencia
              _buildDataCard(
                title: 'Datos del Conductor',
                icon: Icons.person_outline,
                items: [
                  if (nombreCompleto.isNotEmpty)
                    _DataItem('Nombre', nombreCompleto),
                  if (license.rut != null && license.rut!.isNotEmpty)
                    _DataItem('RUT', license.rut!),
                ],
              ),

              const SizedBox(height: 12),

              _buildDataCard(
                title: 'Detalles de Licencia',
                icon: Icons.credit_card_outlined,
                items: [
                  if (license.clase != null && license.clase!.isNotEmpty)
                    _DataItem('Clase', license.clase!),
                  if (license.fechaEmision != null)
                    _DataItem(
                      'Último Control',
                      _formatDateDisplay(license.fechaEmision),
                    ),
                  _DataItem(
                    'Vence',
                    _formatDateDisplay(license.fechaVencimiento),
                    valueColor: const Color(0xFF4CAF50),
                  ),
                ],
              ),

              if (license.direccion != null &&
                  license.direccion!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildDataCard(
                  title: 'Dirección',
                  icon: Icons.location_on_outlined,
                  items: [_DataItem('', license.direccion!)],
                ),
              ],

              const SizedBox(height: 32),

              // Botón CONTINUAR
              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, license),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text(
                    'CONTINUAR',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 4,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Opción de re-escanear (por si el guardia lo necesita)
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _screenState = _LicenseScreenState.scanning;
                    });
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Escanear de nuevo'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
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
      ),
    );
  }

  Widget _buildDataCard({
    required String title,
    required IconData icon,
    required List<_DataItem> items,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppColors.accent),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...items.map((item) => _buildDataRow(item)),
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(_DataItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.label.isNotEmpty) ...[
            SizedBox(
              width: 110,
              child: Text(
                item.label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
          ],
          Expanded(
            child: Text(
              item.value,
              style: TextStyle(
                color: item.valueColor ?? AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------
  // VISTA 3: ESCANEO NORMAL (OCR)
  // ----------------------------------------------------------------

  Widget _buildScanView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const StepHeader(
            currentStep: 3,
            title: 'Escaneo de Licencia',
            subtitle:
                'Captura una foto clara de la licencia de conducir del conductor.',
          ),
          _buildInstructionCard(
            'Asegúrate de que la licencia esté bien iluminada, sin reflejos ni sombras.',
          ),
          const SizedBox(height: 24),
          _buildPhotoCard(
            "Licencia de Conducir",
            "Toca para capturar",
            _documentFile,
            Icons.credit_card,
            _pickPhoto,
          ),
          const SizedBox(height: 32),
          if (_isProcessing)
            Column(
              children: [
                const CircularProgressIndicator(color: AppColors.accent),
                const SizedBox(height: 16),
                Text(
                  _statusMessage ?? 'Procesando...',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          else
            SizedBox(
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _documentFile != null ? _process : null,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text(
                  'VALIDAR LICENCIA',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.background,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 4,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInstructionCard(String text) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
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
          color: AppColors.surface,
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
                        color: AppColors.background,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 40, color: AppColors.accent),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
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
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.edit,
                        size: 20, color: AppColors.accent),
                  ),
                ),
              if (hasFile)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    color: AppColors.background26,
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

// ----------------------------------------------------------------
// Helpers internos
// ----------------------------------------------------------------

class _DataItem {
  final String label;
  final String value;
  final Color? valueColor;

  const _DataItem(this.label, this.value, {this.valueColor});
}

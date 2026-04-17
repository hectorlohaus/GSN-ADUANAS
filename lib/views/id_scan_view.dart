import 'package:flutter/material.dart';
import 'package:prueba_match/utils/app_colors.dart';
import 'package:prueba_match/models/license_data.dart';
import 'package:prueba_match/models/chofer_match_data.dart';
import 'package:prueba_match/services/registro_service.dart';
import 'package:prueba_match/widgets/step_header.dart';
import 'package:prueba_match/views/transport_document_view.dart';
import 'package:prueba_match/screens/license_scan_screen.dart';

class IDScanView extends StatefulWidget {
  final int registroId;
  final ChoferMatchData datosChoferCarnet;

  const IDScanView({
    super.key,
    required this.registroId,
    required this.datosChoferCarnet,
  });

  @override
  State<IDScanView> createState() => _IDScanViewState();
}

class _IDScanViewState extends State<IDScanView> {
  final RegistroService _registroService = RegistroService();

  String _statusMessage = 'Verificando estado de la licencia...';
  Color _statusColor = AppColors.textSecondary;
  bool _isLoading = true; // Cuando se está validando inicialmente
  bool _isSaving = false; // Cuando se guarda la nueva licencia
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _checkExistingLicense();
  }

  Future<void> _checkExistingLicense() async {
    final String? rut = widget.datosChoferCarnet.run;

    if (rut == null || rut.isEmpty) {
      if (mounted) {
        setState(() {
          _statusMessage = 'RUT no disponible. Escanee la licencia manualmente.';
          _statusColor = AppColors.danger;
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final resultado =
          await _registroService.verificarEstadoLicenciaPorRut(rut);

      if (!mounted) return;

      if (resultado.estado == EstadoVerificacionChofer.valido) {
        setState(() {
          _statusMessage =
              'Licencia ya verificada. Se procederá a documento de transporte.';
          _statusColor = AppColors.success;
          // Dejamos _isLoading true para que no puedan presionar el botón mientras esperamos
        });

        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => TransportDocumentView(
                registroId: widget.registroId,
                photoType: PhotoType.bl,
              ),
            ),
          );
        }
      } else {
        String message;
        switch (resultado.estado) {
          case EstadoVerificacionChofer.noExiste:
            message = 'Licencia no encontrada. Inicie el escaneo de licencia.';
            break;
          case EstadoVerificacionChofer.vencido:
            message = 'Licencia expirada. Inicie el proceso de nuevo.';
            break;
          default:
            message = 'Error de validación. Inicie el escaneo de licencia.';
            break;
        }

        setState(() {
          _statusMessage = message;
          _statusColor = AppColors.danger;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error verificando licencia: $e');
      if (mounted) {
        setState(() {
          _statusMessage =
              'Error al verificar la licencia. Inicie escaneo manual.';
          _statusColor = AppColors.danger;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _scanLicense() async {
    final LicenseData? confirmedData = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LicenseScanScreen(
          registroId: widget.registroId,
          existingChoferData: widget.datosChoferCarnet,
        ),
      ),
    );

    if (confirmedData == null || !mounted) return;

    setState(() {
      _isSaving = true;
      _statusMessage = 'Guardando datos de la licencia...';
      _statusColor = AppColors.accent;
    });

    try {
      await _registroService.guardarDatosLicenciaEscaneada(
        widget.datosChoferCarnet.run!,
        confirmedData,
      );

      if (!mounted) return;
      setState(() {
        _statusMessage = '¡Validación completada!';
        _statusColor = AppColors.success;
      });

      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => TransportDocumentView(
              registroId: widget.registroId,
              photoType: PhotoType.bl,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _statusMessage = 'Error al guardar. Inténtelo de nuevo.';
          _statusColor = AppColors.danger;
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
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
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const StepHeader(
              currentStep: 3,
              title: 'Escaneo de Licencia',
              subtitle:
                  'Por favor, escanea la licencia de conducir para validarla.',
            ),
            
            // Mensaje de estado visual (similar a verification_view)
            Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _statusColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  if (_isLoading || _isSaving)
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _statusColor,
                      ),
                    )
                  else
                    Icon(
                      _statusColor == AppColors.success
                          ? Icons.check_circle
                          : Icons.info_outline,
                      color: _statusColor,
                      size: 24,
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _statusMessage,
                      style: TextStyle(
                        color: _statusColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_errorMessage.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.3)),
                ),
                child: Text(
                  _errorMessage,
                  style: const TextStyle(color: AppColors.danger, fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
            ],

            _buildTipsCard(),
            const SizedBox(height: 32),

            ElevatedButton.icon(
              onPressed: (_isLoading || _isSaving) ? null : _scanLicense,
              icon: const Icon(Icons.document_scanner),
              label: const Text('ESCANEAR LICENCIA'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.background,
                disabledBackgroundColor: AppColors.surface,
                disabledForegroundColor: AppColors.textSecondary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipsCard() {
    return Card(
      elevation: 2,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Consejos para un buen escaneo:',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            _buildTip('Asegúrate de que la licencia esté vigente.'),
            const SizedBox(height: 12),
            _buildTip('Ilumina bien el documento.'),
            const SizedBox(height: 12),
            _buildTip('Evita reflejos o sombras sobre la licencia.'),
          ],
        ),
      ),
    );
  }

  Widget _buildTip(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle, color: AppColors.success, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}


import 'package:prueba_match/utils/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:prueba_match/models/license_data.dart';
import 'package:prueba_match/utils/rut_utils.dart';
import 'package:prueba_match/widgets/step_header.dart';
import 'package:prueba_match/utils/document_utils.dart';
import 'package:flutter/services.dart';

/// Una vista dedicada a confirmar los datos extraídos de una licencia de conducir.
class LicenseConfirmationView extends StatefulWidget {
  final LicenseData initialData;
  final int registroId;

  const LicenseConfirmationView({
    super.key,
    required this.initialData,
    required this.registroId,
  });

  @override
  State<LicenseConfirmationView> createState() =>
      _LicenseConfirmationViewState();
}

class _LicenseConfirmationViewState extends State<LicenseConfirmationView> {
  final _formKey = GlobalKey<FormState>();

  // Controladores para cada campo editable del formulario
  late final TextEditingController _nombresController;
  late final TextEditingController _apellidosController;
  late final TextEditingController _runController;
  late final TextEditingController _fechaNacimientoController; // Nuevo
  late final TextEditingController _fechaEmisionController;
  late final TextEditingController _fechaVencimientoController;
  late final TextEditingController _claseController;
  late final TextEditingController _direccionController;

  @override
  void initState() {
    super.initState();
    _nombresController = TextEditingController(
      text: widget.initialData.nombres,
    );
    _apellidosController = TextEditingController(
      text: widget.initialData.apellidos,
    );
    _runController = TextEditingController(text: widget.initialData.rut);
    _fechaNacimientoController = TextEditingController(
      text: widget.initialData.fechaNacimiento,
    );
    _fechaEmisionController = TextEditingController(
      text: widget.initialData.fechaEmision,
    );
    _fechaVencimientoController = TextEditingController(
      text: widget.initialData.fechaVencimiento,
    );
    _claseController = TextEditingController(text: widget.initialData.clase);
    _direccionController = TextEditingController(
      text: widget.initialData.direccion,
    );
  }

  @override
  void dispose() {
    _nombresController.dispose();
    _apellidosController.dispose();
    _runController.dispose();
    _fechaNacimientoController.dispose();
    _fechaEmisionController.dispose();
    _fechaVencimientoController.dispose();
    _claseController.dispose();
    _direccionController.dispose();
    super.dispose();
  }

  void _onConfirm() {
    if (_formKey.currentState!.validate()) {
      final confirmedData = widget.initialData.copyWith(
        nombres: _nombresController.text,
        apellidos: _apellidosController.text,
        rut: _runController.text,
        fechaNacimiento: _fechaNacimientoController.text,
        fechaEmision: _fechaEmisionController.text,
        fechaVencimiento: _fechaVencimientoController.text,
        clase: _claseController.text,
        direccion: _direccionController.text,
      );
      Navigator.of(context).pop(confirmedData);
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
      backgroundColor: AppColors.background, // Fondo principal
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const StepHeader(
                currentStep: 3,
                title: 'Revisar Licencia',
                subtitle: 'Verifique que los datos extraídos sean correctos.',
              ),
              _buildInstructionCard(),
              const SizedBox(height: 24),

              _buildSectionCard("Información del Conductor", [
                _buildTextFormField(
                  controller: _nombresController,
                  label: 'Nombres',
                ),
                _buildTextFormField(
                  controller: _apellidosController,
                  label: 'Apellidos',
                ),
              ]),

              const SizedBox(height: 24),

              _buildSectionCard("Detalles de la Licencia", [
                _buildTextFormField(controller: _runController, label: 'RUT'),
                _buildTextFormField(
                  controller: _fechaEmisionController,
                   label: 'Fecha Último Control',
                ),
                _buildTextFormField(
                  controller: _fechaVencimientoController,
                  label: 'Fecha de Vencimiento',
                ),
                _buildTextFormField(
                  controller: _claseController,
                  label: 'Clase',
                ),
              ]),

              const SizedBox(height: 24),

              _buildSectionCard("Dirección", [
                _buildTextFormField(
                  controller: _direccionController,
                   label: 'Dirección',
                  required: false,
                ),
              ]),

              const SizedBox(height: 32),

              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _onConfirm,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('CONFIRMAR DATOS'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent, // Acento primario
                    foregroundColor: AppColors.background, // Texto interno
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstructionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface, // Superficie dark
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.assignment_ind_outlined, color: AppColors.accent), // Acento
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Verifique que los datos extraídos sean correctos.',
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

  Widget _buildSectionCard(String title, List<Widget> children) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary, // Blanco principal
              ),
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildTextFormField({
    required TextEditingController controller,
    required String label,
    bool required = true,
  }) {
    List<TextInputFormatter>? formatters;
    TextInputType keyboardType = TextInputType.text;

    if (label.contains('Fecha')) {
      formatters = [DateTextFormatter()];
      keyboardType = TextInputType.number;
    } else if (label.contains('N° de Documento')) {
      formatters = [DocumentNumberTextFormatter()];
      keyboardType = TextInputType.text;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: formatters,
        decoration: InputDecoration(
          labelText: label,
          hintText: label.contains('Fecha') ? 'dd/mm/YYYY' : null,
          helperText: label.contains('Fecha') ? 'Formato: dd/mm/YYYY (Día/Mes/Año)' : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
          filled: true,
          fillColor: AppColors.background, // Contraste contra tarjeta surface
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
        validator: (value) {
          if (required && (value == null || value.trim().isEmpty)) {
            return 'Este campo es requerido';
          }
          if (label.contains('RUT') && value != null && value.isNotEmpty) {
            if (!RutUtils.isValid(value)) {
              return 'RUT inválido';
            }
          }
          return null;
        },
      ),
    );
  }
}

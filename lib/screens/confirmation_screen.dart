import 'package:prueba_match/utils/app_colors.dart';
import 'dart:convert';
import 'package:flutter/material.dart';

class ConfirmationScreen extends StatelessWidget {
  const ConfirmationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? data =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

    if (data == null) {
      return const Scaffold(body: Center(child: Text('No data received')));
    }

    final documentData = data['documentData'] as Map<String, dynamic>?;
    final scannedValues =
        documentData?['scannedValues'] as Map<String, dynamic>?;
    final groups = scannedValues?['groups'] as List<dynamic>?;
    final frontImageBase64 = data['frontImageBase64'] as String?;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verification Results'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF141E30), Color(0xFF243B55)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (frontImageBase64 != null && frontImageBase64.isNotEmpty)
                  Center(
                    child: Container(
                      height: 200,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppColors.background26,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.textPrimary24),
                        image: DecorationImage(
                          image: MemoryImage(base64Decode(frontImageBase64)),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  )
                else
                  Center(
                    child: Container(
                      height: 200,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppColors.textPrimary10,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.textPrimary24),
                      ),
                      child: const Center(
                        child: Icon(Icons.image_not_supported,
                            size: 50, color: AppColors.textPrimary54),
                      ),
                    ),
                  ),
                const SizedBox(height: 30),
                if (groups != null)
                  ...groups.map((group) {
                    final groupName = group['groupFriendlyName'] ?? 'Details';
                    final fields = group['fields'] as List<dynamic>?;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            groupName.toString().toUpperCase(),
                            style: const TextStyle(
                              color: Color(0xFF42A5F5),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.textPrimary.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.textPrimary10),
                            ),
                            child: Column(
                              children: fields?.map<Widget>((field) {
                                    final key = field['fieldKey'] ?? '';
                                    final value = field['value'] ?? '';
                                    final label = _formatLabel(key);

                                    return Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            flex: 2,
                                            child: Text(
                                              label,
                                              style: const TextStyle(
                                                color: AppColors.textPrimary70,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 3,
                                            child: Text(
                                              value.toString(),
                                              style: const TextStyle(
                                                color: AppColors.textPrimary,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList() ??
                                  [],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatLabel(String key) {
    // Convert camelCase to Title Case
    final RegExp exp = RegExp(r'(?<=[a-z])[A-Z]');
    String result = key.replaceAllMapped(exp, (Match m) => ' ${m.group(0)}');
    return result[0].toUpperCase() + result.substring(1);
  }
}

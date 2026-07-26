import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';
import 'family_setup_screen.dart';
import 'home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  PasswordSecurityResult _passSecurity = SecurityService.evaluatePassword('');

  void _onPasswordChanged(String val) {
    setState(() {
      _passSecurity = SecurityService.evaluatePassword(val);
    });
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_passSecurity.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.weakPassword),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.passwordsMismatch),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final db = context.read<DatabaseService>();
      await db.registerUser(
        nbCompleto: _fullNameController.text.trim(),
        nbUsuario: _usernameController.text.trim().isEmpty
            ? null
            : _usernameController.text.trim(),
        nbEmail: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      // Navegación según tenga familia asignada o no
      if (db.currentFamily != null) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const FamilySetupScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll("Exception: ", "")),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildSecurityCheck(String label, bool isMet) {
    return Row(
      children: [
        Icon(
          isMet ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
          color: isMet ? Colors.green : Colors.grey,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isMet ? Colors.green[800] : Colors.grey[700],
              fontWeight: isMet ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.registerTitle),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.registerSubtitle,
                  style: theme.textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
                ),
                const SizedBox(height: 24),

                // Nombre Completo
                TextFormField(
                  controller: _fullNameController,
                  decoration: InputDecoration(
                    labelText: l10n.fullName,
                    prefixIcon: const Icon(Icons.person_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? l10n.fullName : null,
                ),
                const SizedBox(height: 16),

                // Nombre de usuario (opcional)
                TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: l10n.usernameOptional,
                    prefixIcon: const Icon(Icons.alternate_email_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),

                // Correo Electrónico
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: l10n.email,
                    prefixIcon: const Icon(Icons.email_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return l10n.email;
                    if (!v.contains('@') || !v.contains('.')) return l10n.email;
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Contraseña con evaluador de seguridad
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  onChanged: _onPasswordChanged,
                  decoration: InputDecoration(
                    labelText: l10n.password,
                    prefixIcon: const Icon(Icons.lock_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),

                // Indicador visual de Fortaleza de Contraseña
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            l10n.passwordSecurityTitle,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const Spacer(),
                          Text(
                            _passSecurity.isValid ? "Segura ✓" : "Incompleta",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _passSecurity.isValid ? Colors.green : Colors.orange[800],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _passSecurity.score,
                          backgroundColor: Colors.grey[300],
                          color: _passSecurity.score < 0.5
                              ? Colors.red
                              : (_passSecurity.score < 1.0 ? Colors.orange : Colors.green),
                          minHeight: 6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildSecurityCheck(l10n.passRuleMinChars, _passSecurity.minLength),
                      const SizedBox(height: 4),
                      _buildSecurityCheck(l10n.passRuleUppercase, _passSecurity.hasUppercase),
                      const SizedBox(height: 4),
                      _buildSecurityCheck(l10n.passRuleNumber, _passSecurity.hasDigit),
                      const SizedBox(height: 4),
                      _buildSecurityCheck(l10n.passRuleSpecial, _passSecurity.hasSpecialChar),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Confirmar Contraseña
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  decoration: InputDecoration(
                    labelText: l10n.confirmPassword,
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirmPassword ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) {
                    if (v == null || v != _passwordController.text) {
                      return l10n.passwordsMismatch;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 28),

                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _isLoading ? null : _handleRegister,
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            l10n.btnRegister,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(l10n.alreadyHaveAccount),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        l10n.loginHere,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

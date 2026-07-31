import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/database_service.dart';
import '../services/security_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  int _currentStep = 1; // 1: Email, 2: PIN, 3: New Password
  bool _isLoading = false;

  final _emailController = TextEditingController();
  final _pinController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _formKeyEmail = GlobalKey<FormState>();
  final _formKeyPin = GlobalKey<FormState>();
  final _formKeyPass = GlobalKey<FormState>();

  String _targetEmail = "";
  bool _obscureNewPass = true;
  bool _obscureConfirmPass = true;
  PasswordSecurityResult _passSecurity = SecurityService.evaluatePassword('');

  void _onPasswordChanged(String val) {
    setState(() {
      _passSecurity = SecurityService.evaluatePassword(val);
    });
  }

  Timer? _timer;
  int _startSeconds = 600; // 10 minutos

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    _pinController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _startSeconds = 600);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_startSeconds <= 0) {
        timer.cancel();
      } else {
        setState(() => _startSeconds--);
      }
    });
  }

  String get _formattedTime {
    final minutes = (_startSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_startSeconds % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  Future<void> _handleRequestPin() async {
    if (!_formKeyEmail.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final l10n = AppLocalizations.of(context)!;
    final db = context.read<DatabaseService>();

    final res = await db.requestPasswordReset(_emailController.text.trim());
    if (!mounted) return;
    setState(() => _isLoading = false);

    _targetEmail = res['email'] ?? _emailController.text.trim();
    setState(() => _currentStep = 2);
    _startTimer();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.resetEmailSentMsg),
        backgroundColor: Colors.indigo[800],
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _handleVerifyPin() async {
    if (!_formKeyPin.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final l10n = AppLocalizations.of(context)!;
    final db = context.read<DatabaseService>();

    final isValid = await db.verifyResetPin(_targetEmail, _pinController.text.trim());
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (isValid) {
      _timer?.cancel();
      setState(() => _currentStep = 3);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.invalidOrExpiredPin),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.forgotPasswordTitle),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Indicador de pasos
              Row(
                children: [
                  _buildStepCircle(1, "1"),
                  _buildStepLine(1),
                  _buildStepCircle(2, "2"),
                  _buildStepLine(2),
                  _buildStepCircle(3, "3"),
                ],
              ),
              const SizedBox(height: 32),

              if (_currentStep == 1) _buildStep1Email(l10n, theme),
              if (_currentStep == 2) _buildStep2Pin(l10n, theme),
              if (_currentStep == 3) _buildStep3NewPassword(l10n, theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepCircle(int stepNumber, String label) {
    final isActive = _currentStep >= stepNumber;
    return CircleAvatar(
      radius: 18,
      backgroundColor: isActive ? Colors.deepPurple : Colors.grey[300],
      child: Text(
        label,
        style: TextStyle(
          color: isActive ? Colors.white : Colors.grey[600],
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildStepLine(int afterStep) {
    final isActive = _currentStep > afterStep;
    return Expanded(
      child: Container(
        height: 3,
        color: isActive ? Colors.deepPurple : Colors.grey[300],
      ),
    );
  }

  // --- PASO 1: INGRESAR CORREO / USUARIO ---
  Widget _buildStep1Email(AppLocalizations l10n, ThemeData theme) {
    return Form(
      key: _formKeyEmail,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.forgotPasswordTitle,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.enterEmailMsg,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
          const SizedBox(height: 28),

          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: "${l10n.email} / ${l10n.usernameOptional.split(' ').first}",
              prefixIcon: const Icon(Icons.email_outlined),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            validator: (v) => v == null || v.trim().isEmpty ? l10n.email : null,
          ),
          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isLoading ? null : _handleRequestPin,
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text(
                      l10n.sendCodeBtn,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // --- PASO 2: VERIFICAR PIN DE 6 DÍGITOS ---
  Widget _buildStep2Pin(AppLocalizations l10n, ThemeData theme) {
    return Form(
      key: _formKeyPin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.pinLabel,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.enterPinMsg(_targetEmail),
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 18, color: Colors.deepPurple),
              const SizedBox(width: 6),
              Text(
                l10n.expiresIn(_formattedTime),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          TextFormField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              counterText: "",
              hintText: "123456",
              hintStyle: const TextStyle(color: Colors.grey, letterSpacing: 8),
              prefixIcon: const Icon(Icons.lock_clock_outlined),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            validator: (v) {
              if (v == null || v.trim().length != 6) {
                return l10n.pinLabel;
              }
              return null;
            },
          ),
          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isLoading ? null : _handleVerifyPin,
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text(
                      l10n.verifyCodeBtn,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
            ),
          ),
          const SizedBox(height: 16),

          Center(
            child: TextButton(
              onPressed: _isLoading ? null : _handleRequestPin,
              child: Text(l10n.sendCodeBtn),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSaveNewPassword() async {
    if (!_formKeyPass.currentState!.validate()) return;

    final l10n = AppLocalizations.of(context)!;

    if (!_passSecurity.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.weakPassword),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_newPasswordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.passwordsMismatch),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    final db = context.read<DatabaseService>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final success = await db.resetPasswordWithPin(
      _targetEmail,
      _pinController.text.trim(),
      _newPasswordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.passwordResetSuccessMsg),
          backgroundColor: Colors.green,
        ),
      );
      navigator.pop();
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.invalidOrExpiredPin),
          backgroundColor: Colors.red,
        ),
      );
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
              color: isMet ? Colors.black87 : Colors.grey[600],
            ),
          ),
        ),
      ],
    );
  }

  // --- PASO 3: INGRESAR NUEVA CONTRASEÑA ---
  Widget _buildStep3NewPassword(AppLocalizations l10n, ThemeData theme) {
    return Form(
      key: _formKeyPass,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.newPasswordLabel,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
          ),
          const SizedBox(height: 24),

          TextFormField(
            controller: _newPasswordController,
            obscureText: _obscureNewPass,
            onChanged: _onPasswordChanged,
            decoration: InputDecoration(
              labelText: l10n.newPasswordLabel,
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscureNewPass ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscureNewPass = !_obscureNewPass),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return l10n.newPasswordLabel;
              return null;
            },
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
                      _passSecurity.isValid ? l10n.statusSecure : l10n.statusIncomplete,
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
                const SizedBox(height: 10),
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

          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPass,
            decoration: InputDecoration(
              labelText: l10n.confirmNewPasswordLabel,
              prefixIcon: const Icon(Icons.lock_reset_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirmPass ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscureConfirmPass = !_obscureConfirmPass),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            validator: (v) {
              if (v != _newPasswordController.text) {
                return l10n.passwordsMismatch;
              }
              return null;
            },
          ),
          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isLoading ? null : _handleSaveNewPassword,
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text(
                      l10n.saveNewPasswordBtn,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

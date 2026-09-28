import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';

import '../services/database_service.dart';
import 'home_screen.dart';
import 'family_setup_screen.dart';
import 'intro_slides_screen.dart';

class AccountActivationScreen extends StatefulWidget {
  const AccountActivationScreen({super.key});

  @override
  State<AccountActivationScreen> createState() => _AccountActivationScreenState();
}

class _AccountActivationScreenState extends State<AccountActivationScreen>
    with WidgetsBindingObserver {
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();

  bool _isLoadingStatus = true;
  bool _isVerifying = false;
  bool _isResending = false;
  bool _isDeleting = false;
  String? _errorMessage;

  int _pinRemainingSeconds = 0;
  int _blockRemainingSeconds = 0;
  int _sendCount = 1;
  static const int _maxSends = 5;

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInitialStatus();
    _startTicker();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _pinController.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadInitialStatus();
    }
  }

  void _startTicker() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_pinRemainingSeconds > 0) {
          _pinRemainingSeconds--;
        }
        if (_blockRemainingSeconds > 0) {
          _blockRemainingSeconds--;
        }
      });
    });
  }

  Future<void> _loadInitialStatus() async {
    final db = context.read<DatabaseService>();
    final info = await db.getActivationStatus();
    if (!mounted) return;

    setState(() {
      _sendCount = (info['sendCount'] as int?) ?? 1;
      _blockRemainingSeconds = (info['remainingBlockSeconds'] as int?) ?? 0;
      final pinSec = (info['remainingPinSeconds'] as int?) ?? 0;
      _pinRemainingSeconds = pinSec > 0 ? pinSec : 0;
      _isLoadingStatus = false;
    });
  }

  String _formatTime(int totalSeconds) {
    if (totalSeconds <= 0) return '00:00';
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final mStr = minutes.toString().padLeft(2, '0');
    final sStr = seconds.toString().padLeft(2, '0');
    return '$mStr:$sStr';
  }

  Future<void> _handleVerify() async {
    final pin = _pinController.text.trim();
    final l10n = AppLocalizations.of(context)!;

    if (pin.length != 6) {
      setState(() {
        _errorMessage = l10n.activationPinError;
      });
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    final db = context.read<DatabaseService>();
    final result = await db.verifyActivationCode(pin);

    if (!mounted) return;
    setState(() => _isVerifying = false);

    if (result['success'] == true) {
      if (db.currentUser?.idFamilia != null) {
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
    } else {
      final err = result['error'] as String?;
      setState(() {
        if (err == 'expired') {
          _errorMessage = l10n.activationExpired;
          _pinRemainingSeconds = 0;
        } else if (err == 'incorrect_pin') {
          _errorMessage = l10n.activationIncorrectPin;
        } else {
          _errorMessage = l10n.activationGenericError;
        }
      });
    }
  }

  Future<void> _handleResend() async {
    if (_blockRemainingSeconds > 0 || _isResending) return;

    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _isResending = true;
      _errorMessage = null;
    });

    final db = context.read<DatabaseService>();
    final result = await db.resendActivationCode();

    if (!mounted) return;
    setState(() => _isResending = false);

    if (result['success'] == true) {
      if (result['already_active'] == true) {
        if (db.currentUser?.idFamilia != null) {
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
        return;
      }

      setState(() {
        _sendCount = (result['sendCount'] as int?) ?? (_sendCount + 1);
        _pinRemainingSeconds = 600; // 10 minutos para el nuevo PIN
        if (result['isBlockedNow'] == true) {
          _blockRemainingSeconds = 600;
        }
        _pinController.clear();
        _errorMessage = null;
      });

      _pinFocusNode.requestFocus();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.activationResendSuccess),
          backgroundColor: Colors.teal,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      final err = result['error'] as String?;
      if (err == 'rate_limit_exceeded') {
        final sec = (result['remainingSeconds'] as int?) ?? 600;
        setState(() {
          _blockRemainingSeconds = sec;
        });
        final mins = (result['remainingMinutes'] as int?) ?? 10;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.activationRateLimitBlocked(mins)),
            backgroundColor: Colors.orange[800],
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        setState(() {
          _errorMessage = l10n.activationGenericError;
        });
      }
    }
  }

  Future<void> _handleDeleteUnactivatedAccount() async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: Colors.red, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.activationDeleteDialogTitle,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          l10n.activationDeleteDialogDesc,
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(l10n.deleteAccountConfirmDialogCancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(l10n.activationDeleteConfirm),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isDeleting = true);
    final db = context.read<DatabaseService>();
    final result = await db.deleteAccount(isPendingActivation: true);

    if (!mounted) return;
    setState(() => _isDeleting = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.activationDeleteSuccess),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const IntroSlidesScreen()),
        (route) => false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.deleteAccountError),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleLogout() async {
    final db = context.read<DatabaseService>();
    await db.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const IntroSlidesScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final db = context.watch<DatabaseService>();
    final userEmail = db.currentUser?.nbEmail ?? '';

    final isBlocked = _blockRemainingSeconds > 0;
    final isExpired = !_isLoadingStatus && _pinRemainingSeconds <= 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.activationTitle),
        actions: [
          IconButton(
            tooltip: l10n.menuLogout,
            icon: const Icon(Icons.logout_rounded),
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),

                  // Ícono decorativo con halo
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isExpired
                              ? [Colors.orange.shade700, Colors.deepOrangeAccent]
                              : [theme.colorScheme.primary, theme.colorScheme.secondary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (isExpired ? Colors.orange : theme.colorScheme.primary)
                                .withValues(alpha: 0.35),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(
                        isExpired
                            ? Icons.mark_email_unread_rounded
                            : Icons.mark_email_read_rounded,
                        size: 44,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Subtítulo descriptivo
                  Text(
                    l10n.activationSubtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),

                  // Chip con el correo del usuario
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.email_outlined,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              userEmail,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: theme.colorScheme.primary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Tarjeta informativa destacada si el código expiró (1 o varios días después)
                  if (isExpired) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2C1D10) : const Color(0xFFFFF8E7),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? Colors.orange.withValues(alpha: 0.5)
                              : Colors.orange.shade300,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.schedule_send_rounded,
                                color: Colors.orange,
                                size: 26,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l10n.activationExpiredNoticeTitle,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: isDark
                                            ? Colors.orange[200]
                                            : Colors.orange[900],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      l10n.activationExpiredNoticeDesc,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark ? Colors.grey[300] : Colors.grey[800],
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Botón primario y destacado en estado expirado
                          ElevatedButton.icon(
                            onPressed: (isBlocked || _isResending || _isDeleting)
                                ? null
                                : _handleResend,
                            icon: _isResending
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : Icon(
                                    isBlocked
                                        ? Icons.lock_clock_rounded
                                        : Icons.send_rounded,
                                    size: 18,
                                  ),
                            label: Text(
                              isBlocked
                                  ? l10n.activationLockCountdown(
                                      _formatTime(_blockRemainingSeconds))
                                  : l10n.activationSendNewEmailBtn,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  isDark ? Colors.orange[800] : Colors.orange[700],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Campo de PIN de 6 dígitos
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(
                        color: _errorMessage != null
                            ? Colors.red
                            : (isDark ? Colors.white12 : Colors.grey.shade300),
                        width: _errorMessage != null ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          isExpired
                              ? l10n.activationExpiredInputHint
                              : l10n.activationPinHint,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isExpired
                                ? (isDark ? Colors.orange[300] : Colors.orange[800])
                                : (isDark ? Colors.grey[400] : Colors.grey[600]),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _pinController,
                          focusNode: _pinFocusNode,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 6,
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 12,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            counterText: '',
                            border: InputBorder.none,
                            hintText: '------',
                            hintStyle: TextStyle(
                              letterSpacing: 12,
                              color: Colors.grey,
                            ),
                          ),
                          onChanged: (val) {
                            if (val.length == 6 && !isExpired) {
                              _handleVerify();
                            }
                          },
                        ),
                      ],
                    ),
                  ),

                  // Mensaje de error
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Contador de expiración del código o aviso de expirado
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        isExpired ? Icons.timer_off_outlined : Icons.timer_outlined,
                        size: 16,
                        color: isExpired ? Colors.orange[700] : Colors.grey[600],
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          isExpired
                              ? l10n.activationExpired
                              : l10n.activationCodeExpiresIn(
                                  _formatTime(_pinRemainingSeconds)),
                          style: TextStyle(
                            fontSize: 13,
                            color: isExpired ? Colors.orange[700] : Colors.grey[600],
                            fontWeight: isExpired ? FontWeight.bold : FontWeight.normal,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Botón principal: "Verificar y Activar Cuenta" (cuando el código está vigente)
                  // O secundario si expiró
                  if (!isExpired) ...[
                    ElevatedButton(
                      onPressed: _isVerifying || _isDeleting ? null : _handleVerify,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 2,
                      ),
                      child: _isVerifying
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              l10n.activationVerifyBtn,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),

                    // Botón secundario: Reenviar código
                    OutlinedButton.icon(
                      onPressed: (isBlocked || _isResending || _isDeleting)
                          ? null
                          : _handleResend,
                      icon: _isResending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              isBlocked
                                  ? Icons.lock_clock_rounded
                                  : Icons.refresh_rounded,
                              size: 18,
                            ),
                      label: Text(
                        isBlocked
                            ? l10n.activationLockCountdown(
                                _formatTime(_blockRemainingSeconds))
                            : l10n.activationResendBtn,
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ] else ...[
                    // Si ya expiró y el usuario ingresó 6 dígitos, permitimos verificar por si recién llegó
                    OutlinedButton(
                      onPressed: _isVerifying || _isDeleting ? null : _handleVerify,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _isVerifying
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              l10n.activationVerifyBtn,
                              style: const TextStyle(fontSize: 15),
                            ),
                    ),
                  ],

                  const SizedBox(height: 8),

                  // Indicador de tasa de envíos (X de 5)
                  Center(
                    child: Text(
                      l10n.activationRateLimitCounter(_sendCount, _maxSends),
                      style: TextStyle(
                        fontSize: 12,
                        color: _sendCount >= _maxSends
                            ? Colors.orange[800]
                            : Colors.grey[600],
                        fontWeight: _sendCount >= _maxSends
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),

                  const SizedBox(height: 36),
                  const Divider(),
                  const SizedBox(height: 20),

                  // Apartado para Eliminar Cuenta No Activada (Requisito 5)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF261818) : const Color(0xFFFFF4F4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: isDark ? 0.35 : 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.help_outline_rounded,
                              size: 20,
                              color: Colors.redAccent,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.activationDeleteAccount,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.red[200] : Colors.red[900],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _isDeleting || _isVerifying
                              ? null
                              : _handleDeleteUnactivatedAccount,
                          icon: _isDeleting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                                  ),
                                )
                              : const Icon(
                                  Icons.delete_outline_rounded,
                                  color: Colors.red,
                                  size: 20,
                                ),
                          label: Text(
                            l10n.activationDeleteAccountBtn,
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            backgroundColor: Colors.red.withValues(alpha: 0.08),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),

            // Overlay de carga general si se está eliminando
            if (_isDeleting)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

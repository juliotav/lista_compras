import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/coach_mark_service.dart';

/// Definición de un paso dentro de un recorrido de Coach Mark.
class CoachMarkStep {
  final GlobalKey targetKey;
  final String title;
  final String description;
  final double borderRadius;
  final EdgeInsets highlightPadding;
  final bool isCircle;
  final double scrollAlignment;

  const CoachMarkStep({
    required this.targetKey,
    required this.title,
    required this.description,
    this.borderRadius = 16.0,
    this.highlightPadding = const EdgeInsets.all(6.0),
    this.isCircle = false,
    this.scrollAlignment = 0.42,
  });
}

/// Controlador principal para desplegar recorridos interactivos sobre cualquier
/// pantalla o diálogo usando `showGeneralDialog` en el root Navigator.
class CoachMarkController {
  /// Muestra el recorrido guiado para los [steps] que estén actualmente montados.
  /// Retorna `true` si el usuario completó o cerró el recorrido (incluyendo omitir),
  /// y `false` si no había pasos válidos o ya existía otro recorrido activo.
  static Future<bool> show({
    required BuildContext context,
    required List<CoachMarkStep> steps,
    VoidCallback? onComplete,
  }) async {
    if (!context.mounted || CoachMarkService.isTourActive) return false;

    final validSteps = steps.where((s) {
      final ctx = s.targetKey.currentContext;
      if (ctx == null) return false;
      final ro = ctx.findRenderObject();
      return ro is RenderBox && ro.attached && ro.hasSize && !ro.size.isEmpty;
    }).toList();

    if (validSteps.isEmpty) {
      debugPrint('[COACH_MARK LOG] No hay widgets montados para mostrar la guía.');
      return false;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    CoachMarkService.setTourActive(true);

    try {
      await showGeneralDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        barrierLabel: 'CoachMark',
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          return _CoachMarkOverlayView(steps: validSteps);
        },
        transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            ),
            child: child,
          );
        },
      );
      onComplete?.call();
      return true;
    } catch (e) {
      debugPrint('[COACH_MARK LOG] Error mostrando overlay de Coach Mark: $e');
      return false;
    } finally {
      CoachMarkService.setTourActive(false);
    }
  }
}

class _CoachMarkOverlayView extends StatefulWidget {
  final List<CoachMarkStep> steps;

  const _CoachMarkOverlayView({required this.steps});

  @override
  State<_CoachMarkOverlayView> createState() => _CoachMarkOverlayViewState();
}

class _CoachMarkOverlayViewState extends State<_CoachMarkOverlayView>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _rectAnimController;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;
  int _currentIndex = 0;
  Rect? _fromRect;
  Rect? _targetRect;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _rectAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.15).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.15, end: 0.75).chain(CurveTween(curve: Curves.easeOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.75, end: 0.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 20,
      ),
    ]).animate(_pulseController);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _activateStep(0);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rectAnimController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted || _isBusy) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final measured = _measureStepRect(widget.steps[_currentIndex]);
      if (measured != null) {
        setState(() {
          _fromRect = measured;
          _targetRect = measured;
        });
      }
    });
  }

  Rect? _measureStepRect(CoachMarkStep step) {
    final targetCtx = step.targetKey.currentContext;
    if (targetCtx == null || !targetCtx.mounted) return null;
    final renderObject = targetCtx.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached || !renderObject.hasSize) {
      return null;
    }
    final size = renderObject.size;
    if (size.isEmpty) return null;

    final offset = renderObject.localToGlobal(Offset.zero);
    final rawRect = Rect.fromLTWH(
      offset.dx - step.highlightPadding.left,
      offset.dy - step.highlightPadding.top,
      size.width + step.highlightPadding.horizontal,
      size.height + step.highlightPadding.vertical,
    );

    final screenSize = MediaQuery.sizeOf(context);
    final clampedLeft =
        rawRect.left.clamp(2.0, math.max(2.0, screenSize.width - 10.0)).toDouble();
    final clampedTop =
        rawRect.top.clamp(2.0, math.max(2.0, screenSize.height - 10.0)).toDouble();
    final clampedRight = rawRect.right
        .clamp(clampedLeft + 8.0, math.max(clampedLeft + 8.0, screenSize.width - 2.0))
        .toDouble();
    final clampedBottom = rawRect.bottom
        .clamp(clampedTop + 8.0, math.max(clampedTop + 8.0, screenSize.height - 2.0))
        .toDouble();

    return Rect.fromLTRB(clampedLeft, clampedTop, clampedRight, clampedBottom);
  }

  Future<void> _activateStep(int index) async {
    if (!mounted) return;
    if (index >= widget.steps.length) {
      _closeOverlay();
      return;
    }

    _isBusy = true;
    final step = widget.steps[index];
    final targetCtx = step.targetKey.currentContext;

    if (targetCtx == null || !targetCtx.mounted) {
      _isBusy = false;
      await _activateStep(index + 1);
      return;
    }

    // Desplaza suavemente el scroll subyacente si el widget está fuera o al borde de la vista
    if (Scrollable.maybeOf(targetCtx) != null) {
      try {
        await Scrollable.ensureVisible(
          targetCtx,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: step.scrollAlignment,
        );
        await Future.delayed(const Duration(milliseconds: 60));
        await WidgetsBinding.instance.endOfFrame;
      } catch (e) {
        debugPrint('[COACH_MARK LOG] No se pudo hacer scroll hacia el paso $index: $e');
      }
    }

    if (!mounted) return;
    final measured = _measureStepRect(step);
    if (measured == null) {
      _isBusy = false;
      await _activateStep(index + 1);
      return;
    }

    final previous = _targetRect ?? measured;
    setState(() {
      _currentIndex = index;
      _fromRect = previous;
      _targetRect = measured;
    });

    _rectAnimController.forward(from: 0.0);
    _pulseController.forward(from: 0.0);
    _isBusy = false;
  }

  void _handleNextOrClose() {
    if (_isBusy) return;
    if (_currentIndex >= widget.steps.length - 1) {
      _closeOverlay();
    } else {
      _activateStep(_currentIndex + 1);
    }
  }

  void _closeOverlay() {
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final screenSize = media.size;
    final safeTop = media.padding.top;
    final safeBottom = media.padding.bottom;

    final step = widget.steps[_currentIndex];
    final isLastStep = _currentIndex >= widget.steps.length - 1;
    const spotlightAccent = Color(0xFFB388FF);

    return PopScope(
      canPop: true,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Fondo desenfocado (solo fuera del spotlight) + velo oscuro profundo + halo pulsante
            AnimatedBuilder(
              animation: Listenable.merge([_rectAnimController, _pulseController]),
              builder: (context, _) {
                final t = Curves.easeOutCubic.transform(_rectAnimController.value);
                final currentRect = (_fromRect != null && _targetRect != null)
                    ? Rect.lerp(_fromRect, _targetRect, t)
                    : _targetRect;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipPath(
                      clipper: _SpotlightInverseClipper(
                        targetRect: currentRect,
                        borderRadius: step.borderRadius,
                        isCircle: step.isCircle,
                      ),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    CustomPaint(
                      size: screenSize,
                      painter: _SpotlightPainter(
                        targetRect: currentRect,
                        borderRadius: step.borderRadius,
                        isCircle: step.isCircle,
                        scrimColor: const Color(0xDD0D0A18), // ~87% opacidad morado-negro profundo
                        accentColor: spotlightAccent,
                        pulseValue: _pulseAnim.value,
                      ),
                    ),
                  ],
                );
              },
            ),

            // Opción 2 mejorada: Texto flotante sin recuadro en negrita de alto contraste
            if (_targetRect != null)
              _buildTooltipPositioned(
                context: context,
                l10n: l10n,
                theme: theme,
                screenSize: screenSize,
                safeTop: safeTop,
                safeBottom: safeBottom,
                targetRect: _targetRect!,
                step: step,
                isLastStep: isLastStep,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTooltipPositioned({
    required BuildContext context,
    required AppLocalizations l10n,
    required ThemeData theme,
    required Size screenSize,
    required double safeTop,
    required double safeBottom,
    required Rect targetRect,
    required CoachMarkStep step,
    required bool isLastStep,
  }) {
    const double edgeMargin = 24.0;
    const double gap = 14.0;

    final double spaceAbove = targetRect.top - safeTop - gap - 8.0;
    final double spaceBelow =
        screenSize.height - safeBottom - targetRect.bottom - gap - 8.0;
    final bool placeBelow = spaceBelow >= 210.0 || spaceBelow >= spaceAbove;

    final double topBound =
        placeBelow ? (targetRect.bottom + gap) : (safeTop + 12.0);
    final double bottomBound = placeBelow
        ? (safeBottom + 12.0)
        : (screenSize.height - targetRect.top + gap);

    final double minTop = safeTop + 8.0;
    final double maxTop = math.max(minTop, screenSize.height - safeBottom - 140.0);
    final double minBottom = safeBottom + 8.0;
    final double maxBottom = math.max(minBottom, screenSize.height - safeTop - 140.0);

    final double clampedTop = topBound.clamp(minTop, maxTop).toDouble();
    final double clampedBottom = bottomBound.clamp(minBottom, maxBottom).toDouble();

    const Color accentText = Color(0xFFD9BEFF);
    const Color buttonBg = Color(0xFF7C4DFF);
    const List<Shadow> textShadows = [
      Shadow(
        color: Color(0xEE000000),
        blurRadius: 12,
        offset: Offset(0, 2),
      ),
      Shadow(
        color: Color(0x99000000),
        blurRadius: 4,
        offset: Offset(0, 1),
      ),
    ];

    final double contentWidth =
        math.min(screenSize.width - (edgeMargin * 2), 420.0);
    final double contentLeft = (screenSize.width - contentWidth) / 2.0;
    final double pointerX = (targetRect.center.dx - contentLeft)
        .clamp(16.0, math.max(16.0, contentWidth - 16.0))
        .toDouble();

    // Indicador direccional sin caja apuntando hacia el control destacado
    final Widget pointer = SizedBox(
      width: contentWidth,
      height: 26,
      child: Stack(
        children: [
          Positioned(
            left: (pointerX - 13).clamp(0.0, math.max(0.0, contentWidth - 26.0)),
            top: 0,
            child: Icon(
              placeBelow
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              color: accentText,
              size: 24,
              shadows: textShadows,
            ),
          ),
        ],
      ),
    );

    return Positioned(
      top: clampedTop,
      bottom: clampedBottom,
      left: edgeMargin,
      right: edgeMargin,
      child: Align(
        alignment: placeBelow ? Alignment.topCenter : Alignment.bottomCenter,
        child: SizedBox(
          width: contentWidth,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOutCubic,
            child: Column(
              key: ValueKey<int>(_currentIndex),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (placeBelow) ...[
                  pointer,
                  const SizedBox(height: 6),
                ],
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: accentText.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                l10n.coachStepCounter(
                                  _currentIndex + 1,
                                  widget.steps.length,
                                ),
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                  color: accentText,
                                ),
                              ),
                            ),
                            const Spacer(),
                            if (!isLastStep)
                              TextButton(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: _closeOverlay,
                                child: Text(
                                  l10n.coachBtnSkip,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white70,
                                    shadows: textShadows,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          step.title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.1,
                            shadows: textShadows,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          step.description,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            height: 1.48,
                            shadows: textShadows,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            if (widget.steps.length > 1)
                              Flexible(
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: List.generate(
                                    widget.steps.length,
                                    (idx) {
                                      final active = idx == _currentIndex;
                                      return AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 220),
                                        width: active ? 22 : 7,
                                        height: 7,
                                        decoration: BoxDecoration(
                                          color: active
                                              ? accentText
                                              : Colors.white
                                                  .withValues(alpha: 0.34),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            const Spacer(),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: buttonBg,
                                foregroundColor: Colors.white,
                                elevation: 3,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                              iconAlignment: IconAlignment.end,
                              icon: Icon(
                                isLastStep
                                    ? Icons.check_rounded
                                    : Icons.arrow_forward_rounded,
                                size: 18,
                              ),
                              label: Text(
                                isLastStep ? l10n.btnClose : l10n.btnNext,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              onPressed: _handleNextOrClose,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (!placeBelow) ...[
                  const SizedBox(height: 6),
                  pointer,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SpotlightInverseClipper extends CustomClipper<Path> {
  final Rect? targetRect;
  final double borderRadius;
  final bool isCircle;

  _SpotlightInverseClipper({
    required this.targetRect,
    required this.borderRadius,
    required this.isCircle,
  });

  @override
  Path getClip(Size size) {
    final fullPath = Path()..addRect(Offset.zero & size);
    if (targetRect == null) return fullPath;

    final holePath = Path();
    if (isCircle) {
      final radius = math.max(targetRect!.width, targetRect!.height) / 2;
      holePath.addOval(
        Rect.fromCircle(center: targetRect!.center, radius: radius),
      );
    } else {
      holePath.addRRect(
        RRect.fromRectAndRadius(
          targetRect!,
          Radius.circular(borderRadius),
        ),
      );
    }

    return Path.combine(PathOperation.difference, fullPath, holePath);
  }

  @override
  bool shouldReclip(covariant _SpotlightInverseClipper oldClipper) {
    return oldClipper.targetRect != targetRect ||
        oldClipper.borderRadius != borderRadius ||
        oldClipper.isCircle != isCircle;
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect? targetRect;
  final double borderRadius;
  final bool isCircle;
  final Color scrimColor;
  final Color accentColor;
  final double pulseValue;

  _SpotlightPainter({
    required this.targetRect,
    required this.borderRadius,
    required this.isCircle,
    required this.scrimColor,
    required this.accentColor,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fullPath = Path()..addRect(Offset.zero & size);
    final scrimPaint = Paint()..color = scrimColor;

    if (targetRect == null) {
      canvas.drawPath(fullPath, scrimPaint);
      return;
    }

    final Path holePath = Path();
    if (isCircle) {
      final radius = math.max(targetRect!.width, targetRect!.height) / 2;
      holePath.addOval(
        Rect.fromCircle(center: targetRect!.center, radius: radius),
      );
    } else {
      holePath.addRRect(
        RRect.fromRectAndRadius(
          targetRect!,
          Radius.circular(borderRadius),
        ),
      );
    }

    final cutoutPath = Path.combine(
      PathOperation.difference,
      fullPath,
      holePath,
    );
    canvas.drawPath(cutoutPath, scrimPaint);

    // Halo pulsante + borde blanco limpio alrededor del elemento destacado
    final glowPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.25 + (0.30 * pulseValue))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0 + (6.0 * pulseValue);
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.94)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    canvas.drawPath(holePath, glowPaint);
    canvas.drawPath(holePath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.isCircle != isCircle ||
        oldDelegate.scrimColor != scrimColor ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.pulseValue != pulseValue;
  }
}

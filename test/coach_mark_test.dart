import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lista_compras/l10n/app_localizations.dart';
import 'package:lista_compras/services/coach_mark_service.dart';
import 'package:lista_compras/widgets/coach_mark_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CoachMarkService.setTourActive(false);
  });

  group('CoachMarkService persistence tests', () {
    test('Tracks seen tours independently per user and supports reset', () async {
      expect(
        await CoachMarkService.hasSeenTour(CoachMarkTour.familySetup, 'user-1'),
        isFalse,
      );
      expect(
        await CoachMarkService.hasSeenTour(CoachMarkTour.home, 'user-1'),
        isFalse,
      );

      await CoachMarkService.markTourSeen(CoachMarkTour.familySetup, 'user-1');

      expect(
        await CoachMarkService.hasSeenTour(CoachMarkTour.familySetup, 'user-1'),
        isTrue,
      );
      // Otro usuario no debe verse afectado
      expect(
        await CoachMarkService.hasSeenTour(CoachMarkTour.familySetup, 'user-2'),
        isFalse,
      );

      await CoachMarkService.markTourSeen(CoachMarkTour.home, 'user-1');
      await CoachMarkService.markTourSeen(CoachMarkTour.listDetail, 'user-1');

      await CoachMarkService.resetTour(CoachMarkTour.home, 'user-1');
      expect(
        await CoachMarkService.hasSeenTour(CoachMarkTour.home, 'user-1'),
        isFalse,
      );
      expect(
        await CoachMarkService.hasSeenTour(CoachMarkTour.listDetail, 'user-1'),
        isTrue,
      );

      await CoachMarkService.resetAllTours('user-1');
      for (final tour in CoachMarkTour.values) {
        expect(
          await CoachMarkService.hasSeenTour(tour, 'user-1'),
          isFalse,
        );
      }
    });
  });

  group('CoachMarkController widget tests', () {
    testWidgets(
      'Steps through mounted GlobalKeys with Siguiente -> Cerrar and ignores unmounted keys',
      (WidgetTester tester) async {
        final key1 = GlobalKey();
        final keyUnmounted = GlobalKey();
        final key2 = GlobalKey();
        bool completed = false;

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return Column(
                    children: [
                      const SizedBox(height: 60),
                      ElevatedButton(
                        key: key1,
                        onPressed: () {
                          CoachMarkController.show(
                            context: context,
                            steps: [
                              CoachMarkStep(
                                targetKey: key1,
                                title: 'Paso 1',
                                description: 'Descripción del paso 1',
                              ),
                              CoachMarkStep(
                                targetKey: keyUnmounted,
                                title: 'Paso oculto',
                                description: 'No debe mostrarse',
                              ),
                              CoachMarkStep(
                                targetKey: key2,
                                title: 'Paso 2',
                                description: 'Descripción del paso 2',
                              ),
                            ],
                            onComplete: () => completed = true,
                          );
                        },
                        child: const Text('Lanzar'),
                      ),
                      const SizedBox(height: 120),
                      Container(
                        key: key2,
                        width: 180,
                        height: 48,
                        color: Colors.teal,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );

        await tester.tap(find.text('Lanzar'));
        await tester.pumpAndSettle();

        // Debe mostrar 2 pasos (omitiendo keyUnmounted)
        expect(find.text('1 de 2'), findsOneWidget);
        expect(find.text('Paso 1'), findsOneWidget);
        expect(find.text('Siguiente'), findsOneWidget);
        expect(find.text('Omitir'), findsOneWidget);

        // Avanzar al último paso
        await tester.tap(find.text('Siguiente'));
        await tester.pumpAndSettle();

        expect(find.text('2 de 2'), findsOneWidget);
        expect(find.text('Paso 2'), findsOneWidget);
        expect(find.text('Cerrar'), findsOneWidget);
        expect(find.text('Omitir'), findsNothing);

        // Cerrar el recorrido
        await tester.tap(find.text('Cerrar'));
        await tester.pumpAndSettle();

        expect(completed, isTrue);
        expect(CoachMarkService.isTourActive, isFalse);
      },
    );

    testWidgets(
      'Works on top of an AlertDialog and leaves the dialog open when closed',
      (WidgetTester tester) async {
        final fieldKey = GlobalKey();
        final qrBtnKey = GlobalKey();
        bool completed = false;

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return Center(
                    child: ElevatedButton(
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder: (dialogCtx) {
                            return AlertDialog(
                              title: const Text('Unirse a Familia'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  OutlinedButton(
                                    key: qrBtnKey,
                                    onPressed: () {},
                                    child: const Text('Escanear código QR'),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(key: fieldKey),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    CoachMarkController.show(
                                      context: dialogCtx,
                                      steps: [
                                        CoachMarkStep(
                                          targetKey: fieldKey,
                                          title: 'Código de familia',
                                          description: 'Ingresa tu código',
                                        ),
                                        CoachMarkStep(
                                          targetKey: qrBtnKey,
                                          title: 'Escanear código QR',
                                          description: 'Escanea con cámara',
                                        ),
                                      ],
                                      onComplete: () => completed = true,
                                    );
                                  },
                                  child: const Text('Iniciar guía'),
                                ),
                              ],
                            );
                          },
                        );
                      },
                      child: const Text('Abrir diálogo'),
                    ),
                  );
                },
              ),
            ),
          ),
        );

        await tester.tap(find.text('Abrir diálogo'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Iniciar guía'));
        await tester.pumpAndSettle();

        expect(find.text('Código de familia'), findsOneWidget);
        expect(find.text('1 de 2'), findsOneWidget);

        // Omitir cierra solo el coach mark y deja el AlertDialog abierto
        await tester.tap(find.text('Omitir'));
        await tester.pumpAndSettle();

        expect(completed, isTrue);
        expect(find.text('Unirse a Familia'), findsOneWidget);
        expect(CoachMarkService.isTourActive, isFalse);
      },
    );

    testWidgets(
      'Auto-scrolls to dynamically positioned off-screen purchased action icons',
      (WidgetTester tester) async {
        final restoreKey = GlobalKey();
        final clearKey = GlobalKey();
        final scrollController = ScrollController();
        bool completed = false;

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return SingleChildScrollView(
                    controller: scrollController,
                    child: Column(
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            CoachMarkController.show(
                              context: context,
                              steps: [
                                CoachMarkStep(
                                  targetKey: restoreKey,
                                  title: 'Restaurar artículos comprados',
                                  description: 'Regresa los comprados',
                                  isCircle: true,
                                  scrollAlignment: 0.72,
                                ),
                                CoachMarkStep(
                                  targetKey: clearKey,
                                  title: 'Limpiar artículos comprados',
                                  description: 'Elimina los comprados',
                                  isCircle: true,
                                  scrollAlignment: 0.72,
                                ),
                              ],
                              onComplete: () => completed = true,
                            );
                          },
                          child: const Text('Mostrar guía comprados'),
                        ),
                        // Simula lista variable de artículos por comprar + catálogo
                        const SizedBox(height: 1100),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              key: restoreKey,
                              icon: const Icon(Icons.restore_rounded),
                              onPressed: () {},
                            ),
                            IconButton(
                              key: clearKey,
                              icon: const Icon(Icons.delete_sweep_rounded),
                              onPressed: () {},
                            ),
                          ],
                        ),
                        const SizedBox(height: 120),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );

        expect(scrollController.offset, equals(0.0));

        await tester.tap(find.text('Mostrar guía comprados'));
        await tester.pumpAndSettle();

        // Debe haber hecho scroll automáticamente hacia abajo
        expect(scrollController.offset, greaterThan(200.0));
        expect(find.text('1 de 2'), findsOneWidget);
        expect(find.text('Restaurar artículos comprados'), findsOneWidget);
        expect(find.text('Siguiente'), findsOneWidget);

        await tester.tap(find.text('Siguiente'));
        await tester.pumpAndSettle();

        expect(find.text('2 de 2'), findsOneWidget);
        expect(find.text('Limpiar artículos comprados'), findsOneWidget);
        expect(find.text('Cerrar'), findsOneWidget);

        await tester.tap(find.text('Cerrar'));
        await tester.pumpAndSettle();

        expect(completed, isTrue);
        expect(CoachMarkService.isTourActive, isFalse);
        scrollController.dispose();
      },
    );
  });
}

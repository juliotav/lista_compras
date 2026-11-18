# MEMORY.md

Memoria viva del proyecto: principios y decisiones vigentes que todo agente debe respetar.
Reglas de mantenimiento: máximo 50 líneas; actualizar al integrar algo nuevo; eliminar lo que ya no aplique.

## Principios obligatorios

### 1. Offline-first primordial: guardado local inmediato y sincronización en segundo plano
El guardado en local (RAM + SQLite) y la sincronización delta en segundo plano con MongoDB son primordiales en toda la app:
- Toda mutación (agregar, marcar/desmarcar comprado, eliminar, reordenar, editar nota, crear/eliminar lista) se aplica PRIMERO en memoria + SQLite (`LocalDbService`) y notifica a la UI en 0ms.
- La escritura a MongoDB va siempre en segundo plano vía `sync_queue` + `SyncService` (`recordLocalMutation` + tombstones para evitar resurrecciones o "productos fantasma").
- En `pullDeltaSync`, distinguir respuesta vacía legítima (`[]`) de fallo de red (`null` vía `MongoService.findOrNull`) para depurar de SQLite elementos borrados remotamente sin riesgo de pérdida ante caídas de red.

### 2. Descarga completa al iniciar sesión y aislamiento por usuario
- Al iniciar sesión (`loginUser`), restaurar sesión (`initSession`) o reanudar (`onAppResume`), descargar toda la información actualizada de todos los grupos/familias a los que pertenece el usuario (`fetchUserFamilies` + `pullDeltaSync` + `warmUpOfflineCacheForAllFamilies` con `forceRefresh: true`), guardándola en SQLite y RAM para trabajar sin conexión incluso en listas nuevas o al cambiar de grupo.
- Al cerrar sesión (`logout`) o autenticar un nuevo usuario (`loginUser`, `registerUser`), limpiar al 100% RAM, `SyncService.resetState()`, todas las tablas de SQLite (`clearAllData`) y banderas `offline_cache_v1_*`. `fetchUserFamilies` depura con `purgeDataOutsideFamilies` cualquier dato ajeno.

### 3. Multi-idioma: español e inglés siempre
- Todo texto visible nuevo va en `lib/l10n/app_es.arb` (plantilla) Y `lib/l10n/app_en.arb`.
- Nada de strings hardcodeados en la UI; usar `AppLocalizations`.

### 4. Comportamiento de listas de compras
- El botón de completar en `ListDetailScreen` (`finishAndCompleteEntireList`) marca todos los artículos pendientes como comprados sin cerrar ni concluir la lista (`isCompleted` se mantiene `false`) y permanece en la pantalla.
- En `HomeScreen`, cada tarjeta de lista muestra en la esquina superior derecha el contador de artículos pendientes (`getPendingItemsCount`, leyenda `{count} por comprar` / `{count} to buy`), obtenido en tiempo real desde la colección `detalle_lista` sincronizada en SQLite y RAM.

### 5. Unión a familias por código o QR
- Las familias pueden compartirse mediante su código `cl_familia` (`FAM-XXXXX`) o su código QR (`LISTALISTA:FAM-XXXXX`) generado localmente con `qr_flutter` (`FamilyQrDialog` en `HomeScreen`, `FamilyMembersScreen` y `FamilySetupScreen`).
- En `FamilySetupScreen`, el diálogo de unirse permite tanto escribir el código manualmente como escanear el QR con la cámara (`QrScannerScreen` con `mobile_scanner`), reutilizando `DatabaseService.joinFamily`.

class ShoppingListModel {
  final String idListaCompra;
  final String idFamilia;
  final String nbLista;
  final bool isDefault; // Para la lista "Super" fija arriba
  final bool isActive;  // Para borrado lógico
  final bool isCompleted; // Indica si fue marcada como hecha
  final DateTime? feUltimaNotificacion; // Cooldown para adición de productos (10 min)
  final DateTime? feUltimaNotificacionCompra; // Cooldown para marcado de compra (10 min)

  ShoppingListModel({
    required this.idListaCompra,
    required this.idFamilia,
    required this.nbLista,
    this.isDefault = false,
    this.isActive = true,
    this.isCompleted = false,
    this.feUltimaNotificacion,
    this.feUltimaNotificacionCompra,
  });

  ShoppingListModel copyWith({
    String? idListaCompra,
    String? idFamilia,
    String? nbLista,
    bool? isDefault,
    bool? isActive,
    bool? isCompleted,
    DateTime? feUltimaNotificacion,
    bool clearFeUltimaNotificacion = false,
    DateTime? feUltimaNotificacionCompra,
    bool clearFeUltimaNotificacionCompra = false,
  }) {
    return ShoppingListModel(
      idListaCompra: idListaCompra ?? this.idListaCompra,
      idFamilia: idFamilia ?? this.idFamilia,
      nbLista: nbLista ?? this.nbLista,
      isDefault: isDefault ?? this.isDefault,
      isActive: isActive ?? this.isActive,
      isCompleted: isCompleted ?? this.isCompleted,
      feUltimaNotificacion: clearFeUltimaNotificacion
          ? null
          : (feUltimaNotificacion ?? this.feUltimaNotificacion),
      feUltimaNotificacionCompra: clearFeUltimaNotificacionCompra
          ? null
          : (feUltimaNotificacionCompra ?? this.feUltimaNotificacionCompra),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id_lista_compra': idListaCompra,
      'id_familia': idFamilia,
      'nb_lista': nbLista,
      'is_default': isDefault,
      'is_active': isActive,
      'is_completed': isCompleted,
      'fe_ultima_notificacion': feUltimaNotificacion?.toIso8601String(),
      'fe_ultima_notificacion_compra': feUltimaNotificacionCompra?.toIso8601String(),
    };
  }

  factory ShoppingListModel.fromMap(Map<String, dynamic> map) {
    return ShoppingListModel(
      idListaCompra: map['id_lista_compra'] ?? '',
      idFamilia: map['id_familia'] ?? '',
      nbLista: map['nb_lista'] ?? '',
      isDefault: map['is_default'] ?? false,
      isActive: map['is_active'] ?? true,
      isCompleted: map['is_completed'] ?? false,
      feUltimaNotificacion: map['fe_ultima_notificacion'] != null
          ? DateTime.tryParse(map['fe_ultima_notificacion'].toString())
          : null,
      feUltimaNotificacionCompra: map['fe_ultima_notificacion_compra'] != null
          ? DateTime.tryParse(map['fe_ultima_notificacion_compra'].toString())
          : null,
    );
  }
}

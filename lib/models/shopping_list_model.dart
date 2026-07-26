class ShoppingListModel {
  final String idListaCompra;
  final String idFamilia;
  final String nbLista;
  final bool isDefault; // Para la lista "Super" fija arriba
  final bool isActive;  // Para borrado lógico
  final bool isCompleted; // Indica si fue marcada como hecha

  ShoppingListModel({
    required this.idListaCompra,
    required this.idFamilia,
    required this.nbLista,
    this.isDefault = false,
    this.isActive = true,
    this.isCompleted = false,
  });

  ShoppingListModel copyWith({
    String? idListaCompra,
    String? idFamilia,
    String? nbLista,
    bool? isDefault,
    bool? isActive,
    bool? isCompleted,
  }) {
    return ShoppingListModel(
      idListaCompra: idListaCompra ?? this.idListaCompra,
      idFamilia: idFamilia ?? this.idFamilia,
      nbLista: nbLista ?? this.nbLista,
      isDefault: isDefault ?? this.isDefault,
      isActive: isActive ?? this.isActive,
      isCompleted: isCompleted ?? this.isCompleted,
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
    );
  }
}

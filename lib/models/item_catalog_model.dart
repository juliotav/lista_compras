class ItemCatalogModel {
  final String idArticulo;
  final String idFamilia;
  final String nbArticuloEs;
  final String nbArticuloEn;
  final int nuUso;

  ItemCatalogModel({
    required this.idArticulo,
    required this.idFamilia,
    required this.nbArticuloEs,
    required this.nbArticuloEn,
    this.nuUso = 0,
  });

  ItemCatalogModel copyWith({
    String? idArticulo,
    String? idFamilia,
    String? nbArticuloEs,
    String? nbArticuloEn,
    int? nuUso,
  }) {
    return ItemCatalogModel(
      idArticulo: idArticulo ?? this.idArticulo,
      idFamilia: idFamilia ?? this.idFamilia,
      nbArticuloEs: nbArticuloEs ?? this.nbArticuloEs,
      nbArticuloEn: nbArticuloEn ?? this.nbArticuloEn,
      nuUso: nuUso ?? this.nuUso,
    );
  }

  String getLocalizedName(String languageCode) {
    if (languageCode == 'en') {
      return nbArticuloEn.isNotEmpty ? nbArticuloEn : nbArticuloEs;
    }
    return nbArticuloEs;
  }

  Map<String, dynamic> toMap() {
    return {
      'id_articulo': idArticulo,
      'id_familia': idFamilia,
      'nb_articulo_es': nbArticuloEs,
      'nb_articulo_en': nbArticuloEn,
      'nu_uso': nuUso,
    };
  }

  factory ItemCatalogModel.fromMap(Map<String, dynamic> map) {
    final rawUso = map['nu_uso'] ?? map['nu_compras'] ?? 0;
    final int parsedUso = rawUso is int ? rawUso : int.tryParse(rawUso.toString()) ?? 0;

    return ItemCatalogModel(
      idArticulo: map['id_articulo'] ?? '',
      idFamilia: map['id_familia'] ?? '',
      nbArticuloEs: map['nb_articulo_es'] ?? map['nb_articulo'] ?? '',
      nbArticuloEn: map['nb_articulo_en'] ?? map['nb_articulo'] ?? '',
      nuUso: parsedUso,
    );
  }
}

class ItemCatalogModel {
  final String idArticulo;
  final String idFamilia;
  final String nbArticuloEs;
  final String nbArticuloEn;

  ItemCatalogModel({
    required this.idArticulo,
    required this.idFamilia,
    required this.nbArticuloEs,
    required this.nbArticuloEn,
  });

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
    };
  }

  factory ItemCatalogModel.fromMap(Map<String, dynamic> map) {
    return ItemCatalogModel(
      idArticulo: map['id_articulo'] ?? '',
      idFamilia: map['id_familia'] ?? '',
      nbArticuloEs: map['nb_articulo_es'] ?? map['nb_articulo'] ?? '',
      nbArticuloEn: map['nb_articulo_en'] ?? map['nb_articulo'] ?? '',
    );
  }
}

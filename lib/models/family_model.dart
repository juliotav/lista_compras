class FamilyModel {
  final String idFamilia;
  final String idCreador;
  final String nbFamilia;
  final String clFamilia;
  final String? dsFamilia;
  final DateTime fechaCreacion;

  FamilyModel({
    required this.idFamilia,
    required this.idCreador,
    required this.nbFamilia,
    required this.clFamilia,
    this.dsFamilia,
    required this.fechaCreacion,
  });

  Map<String, dynamic> toMap() {
    return {
      'id_familia': idFamilia,
      'id_creador': idCreador,
      'nb_familia': nbFamilia,
      'cl_familia': clFamilia,
      'ds_familia': dsFamilia,
      'fecha_creacion': fechaCreacion.toIso8601String(),
    };
  }

  factory FamilyModel.fromMap(Map<String, dynamic> map) {
    return FamilyModel(
      idFamilia: map['id_familia'] ?? '',
      idCreador: map['id_creador'] ?? '',
      nbFamilia: map['nb_familia'] ?? '',
      clFamilia: map['cl_familia'] ?? '',
      dsFamilia: map['ds_familia'],
      fechaCreacion: map['fecha_creacion'] != null
          ? DateTime.parse(map['fecha_creacion'])
          : DateTime.now(),
    );
  }
}

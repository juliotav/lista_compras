class UserFamilyModel {
  final String idUsuario;
  final String idFamilia;
  final DateTime fechaUnion;

  UserFamilyModel({
    required this.idUsuario,
    required this.idFamilia,
    required this.fechaUnion,
  });

  Map<String, dynamic> toMap() {
    return {
      'id_usuario': idUsuario,
      'id_familia': idFamilia,
      'fecha_union': fechaUnion.toIso8601String(),
    };
  }

  factory UserFamilyModel.fromMap(Map<String, dynamic> map) {
    return UserFamilyModel(
      idUsuario: map['id_usuario'] ?? '',
      idFamilia: map['id_familia'] ?? '',
      fechaUnion: map['fecha_union'] != null
          ? DateTime.parse(map['fecha_union'])
          : DateTime.now(),
    );
  }
}

class UserModel {
  final String idUsuario;
  final String nbCompleto;
  final String? nbUsuario;
  final String nbEmail;
  final String clPass;
  final String? idFamilia;
  final String? dsVersionApp;

  UserModel({
    required this.idUsuario,
    required this.nbCompleto,
    this.nbUsuario,
    required this.nbEmail,
    required this.clPass,
    this.idFamilia,
    this.dsVersionApp,
  });

  UserModel copyWith({
    String? idUsuario,
    String? nbCompleto,
    String? nbUsuario,
    String? nbEmail,
    String? clPass,
    String? idFamilia,
    bool clearFamilia = false,
    String? dsVersionApp,
  }) {
    return UserModel(
      idUsuario: idUsuario ?? this.idUsuario,
      nbCompleto: nbCompleto ?? this.nbCompleto,
      nbUsuario: nbUsuario ?? this.nbUsuario,
      nbEmail: nbEmail ?? this.nbEmail,
      clPass: clPass ?? this.clPass,
      idFamilia: clearFamilia ? null : (idFamilia ?? this.idFamilia),
      dsVersionApp: dsVersionApp ?? this.dsVersionApp,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id_usuario': idUsuario,
      'nb_completo': nbCompleto,
      'nb_usuario': nbUsuario,
      'nb_email': nbEmail,
      'cl_pass': clPass,
      'id_familia': idFamilia,
      'ds_version_app': dsVersionApp,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      idUsuario: map['id_usuario'] ?? '',
      nbCompleto: map['nb_completo'] ?? '',
      nbUsuario: map['nb_usuario'],
      nbEmail: map['nb_email'] ?? '',
      clPass: map['cl_pass'] ?? '',
      idFamilia: map['id_familia'],
      dsVersionApp: map['ds_version_app'],
    );
  }
}

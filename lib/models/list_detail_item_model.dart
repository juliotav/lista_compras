class ListDetailItemModel {
  final String idDetalle;
  final String idListaCompra;
  final String idArticulo;
  final String nbArticulo;
  final String? dsDetalle;
  final String status; // 'pending' | 'completed'
  final DateTime? fechaCompra;
  final String? idUsuarioFinalizo;
  final String? idUsuarioAgrego;

  ListDetailItemModel({
    required this.idDetalle,
    required this.idListaCompra,
    required this.idArticulo,
    required this.nbArticulo,
    this.dsDetalle,
    this.status = 'pending',
    this.fechaCompra,
    this.idUsuarioFinalizo,
    this.idUsuarioAgrego,
  });

  bool get isCompleted => status == 'completed';
  bool get isPending => status == 'pending';

  ListDetailItemModel copyWith({
    String? idDetalle,
    String? idListaCompra,
    String? idArticulo,
    String? nbArticulo,
    String? dsDetalle,
    bool clearDsDetalle = false,
    String? status,
    DateTime? fechaCompra,
    String? idUsuarioFinalizo,
    String? idUsuarioAgrego,
  }) {
    return ListDetailItemModel(
      idDetalle: idDetalle ?? this.idDetalle,
      idListaCompra: idListaCompra ?? this.idListaCompra,
      idArticulo: idArticulo ?? this.idArticulo,
      nbArticulo: nbArticulo ?? this.nbArticulo,
      dsDetalle: clearDsDetalle ? null : (dsDetalle ?? this.dsDetalle),
      status: status ?? this.status,
      fechaCompra: fechaCompra ?? this.fechaCompra,
      idUsuarioFinalizo: idUsuarioFinalizo ?? this.idUsuarioFinalizo,
      idUsuarioAgrego: idUsuarioAgrego ?? this.idUsuarioAgrego,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id_detalle': idDetalle,
      'id_lista_compra': idListaCompra,
      'id_articulo': idArticulo,
      'nb_articulo': nbArticulo,
      'ds_detalle': dsDetalle,
      'status': status,
      'fecha_compra': fechaCompra?.toIso8601String(),
      'id_usuario_finalizo': idUsuarioFinalizo,
      'id_usuario_agrego': idUsuarioAgrego,
    };
  }

  factory ListDetailItemModel.fromMap(Map<String, dynamic> map) {
    return ListDetailItemModel(
      idDetalle: map['id_detalle'] ?? '',
      idListaCompra: map['id_lista_compra'] ?? '',
      idArticulo: map['id_articulo'] ?? '',
      nbArticulo: map['nb_articulo'] ?? '',
      dsDetalle: map['ds_detalle'],
      status: map['status'] ?? 'pending',
      fechaCompra: map['fecha_compra'] != null ? DateTime.parse(map['fecha_compra']) : null,
      idUsuarioFinalizo: map['id_usuario_finalizo'],
      idUsuarioAgrego: map['id_usuario_agrego'],
    );
  }
}

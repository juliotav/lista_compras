class ListDetailItemModel {
  final String idDetalle;
  final String idListaCompra;
  final String idArticulo;
  final String nbArticulo;
  final String? dsDetalle;
  final String status; // 'pending' | 'completed'
  final DateTime? fechaCompra;
  final DateTime? fechaAgrego;
  final String? idUsuarioFinalizo;
  final String? idUsuarioAgrego;
  final int nuOrder;

  ListDetailItemModel({
    required this.idDetalle,
    required this.idListaCompra,
    required this.idArticulo,
    required this.nbArticulo,
    this.dsDetalle,
    this.status = 'pending',
    this.fechaCompra,
    this.fechaAgrego,
    this.idUsuarioFinalizo,
    this.idUsuarioAgrego,
    this.nuOrder = 0,
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
    bool clearFechaCompra = false,
    DateTime? fechaAgrego,
    bool clearFechaAgrego = false,
    String? idUsuarioFinalizo,
    bool clearIdUsuarioFinalizo = false,
    String? idUsuarioAgrego,
    int? nuOrder,
  }) {
    return ListDetailItemModel(
      idDetalle: idDetalle ?? this.idDetalle,
      idListaCompra: idListaCompra ?? this.idListaCompra,
      idArticulo: idArticulo ?? this.idArticulo,
      nbArticulo: nbArticulo ?? this.nbArticulo,
      dsDetalle: clearDsDetalle ? null : (dsDetalle ?? this.dsDetalle),
      status: status ?? this.status,
      fechaCompra: clearFechaCompra ? null : (fechaCompra ?? this.fechaCompra),
      fechaAgrego: clearFechaAgrego ? null : (fechaAgrego ?? this.fechaAgrego),
      idUsuarioFinalizo: clearIdUsuarioFinalizo ? null : (idUsuarioFinalizo ?? this.idUsuarioFinalizo),
      idUsuarioAgrego: idUsuarioAgrego ?? this.idUsuarioAgrego,
      nuOrder: nuOrder ?? this.nuOrder,
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
      'fecha_agrego': fechaAgrego?.toIso8601String(),
      'id_usuario_finalizo': idUsuarioFinalizo,
      'id_usuario_agrego': idUsuarioAgrego,
      'nu_order': nuOrder,
    };
  }

  factory ListDetailItemModel.fromMap(Map<String, dynamic> map) {
    DateTime? parsedFechaAgrego;
    final rawAgrego = map['fecha_agrego'] ?? map['fecha_creacion'] ?? map['fe_creacion'];
    if (rawAgrego != null) {
      parsedFechaAgrego = DateTime.tryParse(rawAgrego.toString());
    }

    if (parsedFechaAgrego == null && map['_id'] != null) {
      final idStr = map['_id'].toString();
      final hex = RegExp(r'[0-9a-fA-F]{24}').firstMatch(idStr)?.group(0);
      if (hex != null) {
        try {
          final seconds = int.parse(hex.substring(0, 8), radix: 16);
          parsedFechaAgrego = DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true).toLocal();
        } catch (_) {}
      }
    }

    return ListDetailItemModel(
      idDetalle: map['id_detalle'] ?? '',
      idListaCompra: map['id_lista_compra'] ?? '',
      idArticulo: map['id_articulo'] ?? '',
      nbArticulo: map['nb_articulo'] ?? '',
      dsDetalle: map['ds_detalle'],
      status: map['status'] ?? 'pending',
      fechaCompra: map['fecha_compra'] != null ? DateTime.tryParse(map['fecha_compra'].toString()) : null,
      fechaAgrego: parsedFechaAgrego,
      idUsuarioFinalizo: map['id_usuario_finalizo'],
      idUsuarioAgrego: map['id_usuario_agrego'],
      nuOrder: map['nu_order'] is int
          ? map['nu_order'] as int
          : (int.tryParse(map['nu_order']?.toString() ?? '0') ?? 0),
    );
  }
}

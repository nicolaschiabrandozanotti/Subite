import 'dart:ui';
import 'package:latlong2/latlong.dart';

class Ruta {
  final String id;
  final String sentido; // 'I' or 'V'
  final String nombre;
  final String longitud;

  Ruta({
    required this.id,
    required this.sentido,
    required this.nombre,
    required this.longitud,
  });

  factory Ruta.fromJson(Map<String, dynamic> json) {
    return Ruta(
      id: json['id']?.toString() ?? '',
      sentido: json['sentido']?.toString() ?? 'I',
      nombre: json['nombre']?.toString() ?? '',
      longitud: json['longitud']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sentido': sentido,
    'nombre': nombre,
    'longitud': longitud,
  };
}

class Linea {
  final String id;
  final String nombre;
  final String grupo;
  final String colorHex;
  final int clienteId;
  final String clienteNombre;
  final List<Ruta> rutas;

  Linea({
    required this.id,
    required this.nombre,
    required this.grupo,
    required this.colorHex,
    required this.clienteId,
    required this.clienteNombre,
    required this.rutas,
  });

  Color get color {
    try {
      final hex = colorHex.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return const Color(0xFF009EE2);
    }
  }

  factory Linea.fromJson(Map<String, dynamic> json) {
    final rawRutas = json['rutas'] as List? ?? [];
    return Linea(
      id: json['id']?.toString() ?? '',
      nombre: json['nombre']?.toString() ?? '',
      grupo: json['grupo']?.toString() ?? '',
      colorHex: json['color']?.toString() ?? '#009ee2',
      clienteId: json['clienteId'] is int ? json['clienteId'] : int.tryParse(json['clienteId']?.toString() ?? '0') ?? 0,
      clienteNombre: json['clienteNombre']?.toString() ?? 'Urbano',
      rutas: rawRutas.map((r) => Ruta.fromJson(r as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'nombre': nombre,
    'grupo': grupo,
    'color': colorHex,
    'clienteId': clienteId,
    'clienteNombre': clienteNombre,
    'rutas': rutas.map((r) => r.toJson()).toList(),
  };
}

class Coche {
  final int coche;
  final String linea;
  final String sentido;
  double lat;
  double lon;
  double curso;
  String demora;
  final bool rampa;
  final String? ultimaActualizacion;
  bool isPredictive;

  Coche({
    required this.coche,
    required this.linea,
    required this.sentido,
    required this.lat,
    required this.lon,
    required this.curso,
    required this.demora,
    required this.rampa,
    this.ultimaActualizacion,
    this.isPredictive = false,
  });

  LatLng get position => LatLng(lat, lon);

  factory Coche.fromJson(Map<String, dynamic> json) {
    return Coche(
      coche: json['coche'] is int ? json['coche'] : int.tryParse(json['coche']?.toString() ?? '0') ?? 0,
      linea: json['linea']?.toString() ?? '',
      sentido: json['sentido']?.toString() ?? 'I',
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lon: (json['lon'] as num?)?.toDouble() ?? 0.0,
      curso: (json['curso'] as num?)?.toDouble() ?? 0.0,
      demora: json['demora']?.toString() ?? 'A tiempo',
      rampa: json['rampa'] == true || json['rampa'] == 1 || json['rampa'] == '1',
      ultimaActualizacion: json['ultimaActualizacion']?.toString(),
      isPredictive: json['isPredictive'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'coche': coche,
    'linea': linea,
    'sentido': sentido,
    'lat': lat,
    'lon': lon,
    'curso': curso,
    'demora': demora,
    'rampa': rampa,
    'ultimaActualizacion': ultimaActualizacion,
    'isPredictive': isPredictive,
  };
}

class Parada {
  final String codigo;
  final String nombre;
  final double lat;
  final double lon;

  Parada({
    required this.codigo,
    required this.nombre,
    required this.lat,
    required this.lon,
  });

  LatLng get position => LatLng(lat, lon);

  factory Parada.fromJson(Map<String, dynamic> json) {
    return Parada(
      codigo: json['codigo']?.toString() ?? '',
      nombre: json['nombre']?.toString() ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lon: (json['lon'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'codigo': codigo,
    'nombre': nombre,
    'lat': lat,
    'lon': lon,
  };
}

class Traza {
  final String lineaId;
  final String rutaId;
  final String colorHex;
  final List<LatLng> puntos;
  final List<Parada> paradas;

  Traza({
    required this.lineaId,
    required this.rutaId,
    required this.colorHex,
    required this.puntos,
    required this.paradas,
  });

  factory Traza.fromJson(Map<String, dynamic> json) {
    final rawPuntos = json['puntos'] as List? ?? [];
    final puntosList = rawPuntos.map((p) {
      if (p is List && p.length >= 2) {
        return LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble());
      }
      return const LatLng(0, 0);
    }).where((p) => p.latitude != 0 && p.longitude != 0).toList();

    final rawParadas = json['paradas'] as List? ?? [];
    final paradasList = rawParadas.map((par) => Parada.fromJson(par as Map<String, dynamic>)).toList();

    return Traza(
      lineaId: json['lineaId']?.toString() ?? '',
      rutaId: json['rutaId']?.toString() ?? '',
      colorHex: json['color']?.toString() ?? '#009ee2',
      puntos: puntosList,
      paradas: paradasList,
    );
  }
}

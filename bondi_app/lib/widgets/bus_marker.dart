import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class BusMarker extends StatelessWidget {
  final String line;
  final Color color;
  final bool selected;
  const BusMarker({
    super.key,
    required this.line,
    required this.color,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final hex =
        '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';
    return Semantics(
      label: 'Colectivo línea $line',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color, width: selected ? 3 : 2),
            ),
            child: Text(
              line,
              maxLines: 1,
              style: const TextStyle(
                color: Color(0xFF182D46),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          SvgPicture.string(
            '''<svg xmlns="http://www.w3.org/2000/svg" width="38" height="40" viewBox="0 0 38 40">
          <rect x="6" y="3" width="26" height="32" rx="7" fill="$hex" stroke="#182D46" stroke-width="1.3"/>
          <rect x="11" y="6" width="16" height="3" rx="1.5" fill="#182D46"/>
          <rect x="10" y="12" width="18" height="12" rx="3" fill="#EDF7FF"/>
          <path d="M19 12v12" stroke="#182D46" stroke-width="1.3"/>
          <path d="M11 21l5-7" stroke="white" stroke-width="2"/>
          <rect x="2" y="14" width="4" height="7" rx="2" fill="$hex"/>
          <rect x="32" y="14" width="4" height="7" rx="2" fill="$hex"/>
          <circle cx="12" cy="29" r="2" fill="#FFF0B3"/>
          <circle cx="26" cy="29" r="2" fill="#FFF0B3"/>
          <rect x="16" y="29" width="6" height="2" rx="1" fill="#182D46"/>
          <rect x="9" y="34" width="5" height="4" rx="2" fill="#182D46"/>
          <rect x="24" y="34" width="5" height="4" rx="2" fill="#182D46"/>
        </svg>''',
            width: 38,
            height: 40,
          ),
        ],
      ),
    );
  }
}

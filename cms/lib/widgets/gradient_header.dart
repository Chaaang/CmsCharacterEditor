import 'package:flutter/material.dart';

class GradientHeader extends StatelessWidget {
  final String text;
  final double fontSize;
  const GradientHeader({super.key, required this.text, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    final gradient = const LinearGradient(
      colors: [Colors.purpleAccent, Colors.orangeAccent],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0,),
      child: ShaderMask(
        shaderCallback: (bounds) =>
            gradient.createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style:  TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
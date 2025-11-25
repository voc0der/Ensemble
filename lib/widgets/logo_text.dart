import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LogoText extends StatelessWidget {
  final double fontSize;
  final bool lightMode;

  const LogoText({
    super.key, 
    this.fontSize = 24, 
    this.lightMode = false
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = lightMode ? Colors.white : colorScheme.onBackground;
    
    return Text(
      'Assistant To The Music',
      style: GoogleFonts.permanentMarker(
        textStyle: TextStyle(
          color: textColor,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          shadows: [
            Shadow(
              color: colorScheme.primary.withOpacity(0.5),
              offset: const Offset(2, 2),
              blurRadius: 4,
            ),
          ],
        ),
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

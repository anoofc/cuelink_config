import 'package:flutter/material.dart';

/// Approved PNG artwork; keep launcher masters and SVG alternatives out of UI code.
abstract final class CueLinkBrand {
  static const charcoal = Color(0xFF1D2528);
  static const orange = Color(0xFFFF7A0A);
  static const white = Color(0xFFFFFFFF);
  static const logoOnLight = 'assets/branding/cuelink_logo_color.png';
  static const logoOnDark = 'assets/branding/cuelink_logo_white.png';
  static const markOnLight = 'assets/branding/cuelink_mark_color.png';
  static const markOnDark = 'assets/branding/cuelink_mark_white.png';
  static const logoAspectRatio = 2280 / 648;
}

/// Size follows available space; text scaling never distorts the approved artwork.
class CueLinkLogo extends StatelessWidget {
  const CueLinkLogo({super.key, this.compact = false, this.height = 40});
  final bool compact;
  final double height;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final asset = compact
        ? (dark ? CueLinkBrand.markOnDark : CueLinkBrand.markOnLight)
        : (dark ? CueLinkBrand.logoOnDark : CueLinkBrand.logoOnLight);
    return Image.asset(
      asset,
      width: height * (compact ? 1 : CueLinkBrand.logoAspectRatio),
      height: height,
      fit: BoxFit.contain,
      alignment: Alignment.centerLeft,
      semanticLabel: 'CueLink',
    );
  }
}

import 'package:flutter/material.dart';

/// Bol Khata brand assets and display name.
abstract final class BolKhataBrand {
  static const appName = 'Bol Khata';

  /// Green book mark — onboarding / empty states on light surfaces.
  static const logo = 'assets/branding/bol_khata_logo.png';

  /// Black book mark — light backgrounds / app bar.
  static const logoBlack = 'assets/branding/bol_khata_logo_black.png';

  /// White book mark — dark splash / dark surfaces.
  static const logoWhite = 'assets/branding/bol_khata_logo_white_on_dark.png';

  /// Wide mark assets (natural book aspect, less padding).
  static const markGreen = 'assets/branding/bol_khata_mark_green.png';
  static const markBlack = 'assets/branding/bol_khata_mark_black.png';
  static const markWhite = 'assets/branding/bol_khata_mark_white.png';

  /// Natural book mark aspect (width / height).
  static const markAspectRatio = 289 / 157;
}

/// Book mark logo with optional app name.
///
/// Sized with a locked aspect ratio so parent stretch cannot distort it.
class BolKhataLogo extends StatelessWidget {
  const BolKhataLogo({
    super.key,
    this.height = 40,
    this.showName = false,
    this.variant = BolKhataLogoVariant.green,
    this.nameStyle,
  });

  final double height;
  final bool showName;
  final BolKhataLogoVariant variant;
  final TextStyle? nameStyle;

  String get _asset {
    switch (variant) {
      case BolKhataLogoVariant.green:
        return BolKhataBrand.markGreen;
      case BolKhataLogoVariant.black:
        return BolKhataBrand.markBlack;
      case BolKhataLogoVariant.white:
        return BolKhataBrand.markWhite;
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = height * BolKhataBrand.markAspectRatio;
    final logo = SizedBox(
      height: height,
      width: width,
      child: Image.asset(
        _asset,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
      ),
    );

    if (!showName) {
      return Align(
        alignment: Alignment.center,
        widthFactor: 1,
        heightFactor: 1,
        child: logo,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        logo,
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            BolKhataBrand.appName,
            overflow: TextOverflow.ellipsis,
            style:
                nameStyle ??
                const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F7A4C),
                ),
          ),
        ),
      ],
    );
  }
}

enum BolKhataLogoVariant { green, black, white }

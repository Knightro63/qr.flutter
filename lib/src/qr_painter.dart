/*
 * QR.Flutter
 * Copyright (c) 2019 the QR.Flutter authors.
 * See LICENSE for distribution and usage details.
 */

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:qr/qr.dart';

import 'errors.dart';
import 'paint_cache.dart';
import 'qr_versions.dart';
import 'types.dart';
import 'validator.dart';

// ignore_for_file: deprecated_member_use_from_same_package

const _finderPatternLimit = 7;

// default color for the qr code pixels
const Color? _qrDefaultColor = null;

/// A [CustomPainter] object that you can use to paint a QR code.
class QrPainter extends CustomPainter {
  /// Create a new QRPainter with passed options (or defaults).
  QrPainter({
    required String data,
    required this.version,
    this.errorCorrectionLevel = QrErrorCorrectLevel.L,
    this.color = _qrDefaultColor,
    this.emptyColor,
    this.gapless = false,
    this.embeddedImage,
    this.embeddedImageStyle,
    this.eyeStyle = const QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: Color(0xFF000000),
    ),
    this.dataModuleStyle = const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: Color(0xFF000000),
    ),
  }) : assert(QrVersions.isSupportedVersion(version)) {
    _init(data);
  }

  /// Create a new QrPainter with a pre-validated/created [QrCode] object. This
  /// constructor is useful when you have a custom validation / error handling
  /// flow or for when you need to pre-validate the QR data.
  QrPainter.withQr({
    required QrCode qr,
    this.color = _qrDefaultColor,
    this.emptyColor,
    this.gapless = false,
    this.embeddedImage,
    this.embeddedImageStyle,
    this.eyeStyle = const QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: Color(0xFF000000),
    ),
    this.dataModuleStyle = const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: Color(0xFF000000),
    ),
  })  : _qr = QrImage(qr),
        version = qr.typeNumber,
        errorCorrectionLevel = qr.errorCorrectLevel {
    _calcVersion = version;
    _initPaints();
  }

  /// The QR code version.
  final int version; // the qr code version

  /// The error correction level of the QR code.
  final int errorCorrectionLevel; // the qr code error correction level

  /// The color of the squares.
  @Deprecated('use colors in eyeStyle and dataModuleStyle instead')
  final Color? color; // the color of the dark squares

  /// The color of the non-squares (background).
  @Deprecated(
      'You should use the background color value of your container widget')
  final Color? emptyColor; // the other color
  /// If set to false, the painter will leave a 1px gap between each of the
  /// squares.
  final bool gapless;

  /// The image data to embed (as an overlay) in the QR code. The image will
  /// be added to the center of the QR code.
  final ui.Image? embeddedImage;

  /// Styling options for the image overlay.
  final QrEmbeddedImageStyle? embeddedImageStyle;

  /// Styling option for QR Eye ball and frame.
  final QrEyeStyle eyeStyle;

  /// Styling option for QR data module.
  final QrDataModuleStyle dataModuleStyle;

  /// The base QR code data
  QrImage? _qr;

  /// This is the version (after calculating) that we will use if the user has
  /// requested the 'auto' version.
  late final int _calcVersion;

  /// The size of the 'gap' between the pixels
  final double _gapSize = 0.25;

  /// Cache for all of the [Paint] objects.
  final _paintCache = PaintCache();

  List<Map<String,dynamic>> _rects = [];

  void _init(String data) {
    if (!QrVersions.isSupportedVersion(version)) {
      throw QrUnsupportedVersionException(version);
    }
    // configure and make the QR code data
    final validationResult = QrValidator.validate(
      data: data,
      version: version,
      errorCorrectionLevel: errorCorrectionLevel,
    );
    if (!validationResult.isValid) {
      throw validationResult.error!;
    }
    final qrCode = QrCode(4, QrErrorCorrectLevel.L);
    qrCode.addData(data);
    _qr = QrImage(qrCode);
    _calcVersion = _qr!.typeNumber;
    _initPaints();
  }

  void _initPaints() {
    // Cache the pixel paint object. For now there is only one but we might
    // expand it to multiple later (e.g.: different colours).
    _paintCache.cache(
        Paint()..style = PaintingStyle.fill, QrCodeElement.codePixel);
    // Cache the empty pixel paint object. Empty color is deprecated and will go
    // away.
    _paintCache.cache(
        Paint()..style = PaintingStyle.fill, QrCodeElement.codePixelEmpty);
    // Cache the finder pattern painters. We'll keep one for each one in case
    // we want to provide customization options later.
    for (final position in FinderPatternPosition.values) {
      _paintCache.cache(Paint()..style = PaintingStyle.stroke,
          QrCodeElement.finderPatternOuter,
          position: position);
      _paintCache.cache(Paint()..style = PaintingStyle.stroke,
          QrCodeElement.finderPatternInner,
          position: position);
      _paintCache.cache(
          Paint()..style = PaintingStyle.fill, QrCodeElement.finderPatternDot,
          position: position);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // if the widget has a zero size side then we cannot continue painting.
    if (size.shortestSide == 0) {
      print("[QR] WARN: width or height is zero. You should set a 'size' value "
          "or nest this painter in a Widget that defines a non-zero size");
      return;
    }

    final paintMetrics = _PaintMetrics(
      containerSize: size.shortestSide,
      moduleCount: _qr!.moduleCount,
      gapSize: (gapless ? 0 : _gapSize),
    );

    // draw the finder pattern elements
    _drawFinderPatternItem(FinderPatternPosition.topLeft, canvas, paintMetrics);
    _drawFinderPatternItem(
        FinderPatternPosition.bottomLeft, canvas, paintMetrics);
    _drawFinderPatternItem(
        FinderPatternPosition.topRight, canvas, paintMetrics);

    // DEBUG: draw the inner content boundary
//    final paint = Paint()..style = ui.PaintingStyle.stroke;
//    paint.strokeWidth = 1;
//    paint.color = const Color(0x55222222);
//    canvas.drawRect(
//        Rect.fromLTWH(paintMetrics.inset, paintMetrics.inset,
//            paintMetrics.innerContentSize, paintMetrics.innerContentSize),
//        paint);

    double left;
    double top;
    final gap = !gapless ? _gapSize : 0;
    // get the painters for the pixel information
    final pixelPaint = _paintCache.firstPaint(QrCodeElement.codePixel);
    if (color != null) {
      pixelPaint!.color = color!;
    } else {
      pixelPaint!.color = dataModuleStyle.color!;
    }
    Paint? emptyPixelPaint;
    if (emptyColor != null) {
      emptyPixelPaint = _paintCache.firstPaint(QrCodeElement.codePixelEmpty);
      emptyPixelPaint!.color = emptyColor!;
    }
    for (var x = 0; x < _qr!.moduleCount; x++) {
      for (var y = 0; y < _qr!.moduleCount; y++) {
        // draw the finder patterns independently
        if (_isFinderPatternPosition(x, y)) continue;
        final paint = _qr!.isDark(y, x) ? pixelPaint : emptyPixelPaint;
        if (paint == null) continue;
        // paint a pixel
        left = paintMetrics.inset + (x * (paintMetrics.pixelSize + gap));
        top = paintMetrics.inset + (y * (paintMetrics.pixelSize + gap));
        var pixelHTweak = 0.0;
        var pixelVTweak = 0.0;
        if (gapless && _hasAdjacentHorizontalPixel(x, y, _qr!.moduleCount)) {
          pixelHTweak = 0.5;
        }
        if (gapless && _hasAdjacentVerticalPixel(x, y, _qr!.moduleCount)) {
          pixelVTweak = 0.5;
        }
        final squareRect = Rect.fromLTWH(
          left,
          top,
          paintMetrics.pixelSize + pixelHTweak,
          paintMetrics.pixelSize + pixelVTweak,
        );
        if (dataModuleStyle.dataModuleShape == QrDataModuleShape.square) {
          _rects.add(<String, dynamic>{
            'Rect': squareRect,
            'paint': paint,
            'finder': false
          });
          canvas.drawRect(squareRect, paint);
        } 
        else {
          final roundedRect = RRect.fromRectAndRadius(squareRect,
              Radius.circular(paintMetrics.pixelSize + pixelHTweak));
          _rects.add(<String, dynamic>{
            'RRect': roundedRect,
            'paint': paint,
            'finder': false
          });
          canvas.drawRRect(roundedRect, paint);
        }
      }
    }

    if (embeddedImage != null) {
      final originalSize = Size(
        embeddedImage!.width.toDouble(),
        embeddedImage!.height.toDouble(),
      );
      final requestedSize =
          embeddedImageStyle != null ? embeddedImageStyle!.size : null;
      final imageSize = _scaledAspectSize(size, originalSize, requestedSize);
      final position = Offset(
        (size.width - imageSize.width) / 2.0,
        (size.height - imageSize.height) / 2.0,
      );
      // draw the image overlay.
      _drawImageOverlay(canvas, position, imageSize, embeddedImageStyle);
    }
  }

  bool _hasAdjacentVerticalPixel(int x, int y, int moduleCount) {
    if (y + 1 >= moduleCount) return false;
    return _qr!.isDark(y + 1, x);
  }

  bool _hasAdjacentHorizontalPixel(int x, int y, int moduleCount) {
    if (x + 1 >= moduleCount) return false;
    return _qr!.isDark(y, x + 1);
  }

  bool _isFinderPatternPosition(int x, int y) {
    final isTopLeft = (y < _finderPatternLimit && x < _finderPatternLimit);
    final isBottomLeft = (y < _finderPatternLimit &&
        (x >= _qr!.moduleCount - _finderPatternLimit));
    final isTopRight = (y >= _qr!.moduleCount - _finderPatternLimit &&
        (x < _finderPatternLimit));
    return isTopLeft || isBottomLeft || isTopRight;
  }

  void _drawFinderPatternItem(
    FinderPatternPosition position,
    Canvas canvas,
    _PaintMetrics metrics,
  ) {
    final totalGap = (_finderPatternLimit - 1) * metrics.gapSize;
    final radius = ((_finderPatternLimit * metrics.pixelSize) + totalGap) -
        metrics.pixelSize;
    final strokeAdjust = (metrics.pixelSize / 2.0);
    final edgePos =
        (metrics.inset + metrics.innerContentSize) - (radius + strokeAdjust);

    Offset offset;
    if (position == FinderPatternPosition.topLeft) {
      offset =
          Offset(metrics.inset + strokeAdjust, metrics.inset + strokeAdjust);
    } else if (position == FinderPatternPosition.bottomLeft) {
      offset = Offset(metrics.inset + strokeAdjust, edgePos);
    } else {
      offset = Offset(edgePos, metrics.inset + strokeAdjust);
    }

    // configure the paints
    final outerPaint = _paintCache.firstPaint(QrCodeElement.finderPatternOuter,
        position: position)!;
    outerPaint.strokeWidth = metrics.pixelSize;
    if (color != null) {
      outerPaint.color = color!;
    } else {
      outerPaint.color = eyeStyle.color!;
    }

    final innerPaint = _paintCache.firstPaint(QrCodeElement.finderPatternInner,
        position: position)!;
    innerPaint.strokeWidth = metrics.pixelSize;
    innerPaint.color = emptyColor ?? Color(0x00ffffff);

    final dotPaint = _paintCache.firstPaint(QrCodeElement.finderPatternDot,
        position: position);
    if (color != null) {
      dotPaint!.color = color!;
    } else {
      dotPaint!.color = eyeStyle.color!;
    }

    final outerRect = Rect.fromLTWH(offset.dx, offset.dy, radius, radius);

    final innerRadius = radius - (2 * metrics.pixelSize);
    final innerRect = Rect.fromLTWH(offset.dx + metrics.pixelSize,
        offset.dy + metrics.pixelSize, innerRadius, innerRadius);

    final gap = metrics.pixelSize * 2;
    final dotSize = radius - gap - (2 * strokeAdjust);
    final dotRect = Rect.fromLTWH(offset.dx + metrics.pixelSize + strokeAdjust,
        offset.dy + metrics.pixelSize + strokeAdjust, dotSize, dotSize);

    final rad = eyeStyle.eyeShape == QrEyeShape.circle?null:eyeStyle.radius;

    if (eyeStyle.eyeShape == QrEyeShape.square && rad == null) {
      _rects.add(<String, dynamic>{
        'Rect': outerRect,
        'paint': outerPaint,
        'finder': true
      });
      _rects.add(<String, dynamic>{
        'Rect': innerRect,
        'paint': innerPaint,
        'finder': true
      });
      _rects.add(<String, dynamic>{
        'Rect': dotRect,
        'paint': dotPaint,
        'finder': true
      });
      canvas.drawRect(outerRect, outerPaint);
      canvas.drawRect(innerRect, innerPaint);
      canvas.drawRect(dotRect, dotPaint);
    } 
    else {
      final roundedOuterStrokeRect =
          RRect.fromRectAndRadius(
            outerRect, 
            Radius.circular(rad ?? radius)
          );
      canvas.drawRRect(roundedOuterStrokeRect, outerPaint);
      
      
      final roundedInnerStrokeRect =
          RRect.fromRectAndRadius(
            outerRect, 
            Radius.circular(innerRadius)
          );
      canvas.drawRRect(roundedInnerStrokeRect, innerPaint);

      final ds = (rad == null?dotSize:rad/2);
      final roundedDotStrokeRect =
          RRect.fromRectAndRadius(
            dotRect, 
            Radius.circular(ds)
          );
      canvas.drawRRect(roundedDotStrokeRect, dotPaint);

      _rects.add(<String, dynamic>{
        'RRect': roundedOuterStrokeRect,
        'paint': outerPaint,
        'finder': true
      });
      _rects.add(<String, dynamic>{
        'RRect': roundedInnerStrokeRect,
        'paint': innerPaint,
        'finder': true
      });
      _rects.add(<String, dynamic>{
        'RRect': roundedDotStrokeRect,
        'paint': dotPaint,
        'finder': true
      });
    }
  }

  bool _hasOneNonZeroSide(Size size) => size.longestSide > 0;

  Size _scaledAspectSize(
      Size widgetSize, Size originalSize, Size? requestedSize) {
    if (requestedSize != null && !requestedSize.isEmpty) {
      return requestedSize;
    } else if (requestedSize != null && _hasOneNonZeroSide(requestedSize)) {
      final maxSide = requestedSize.longestSide;
      final ratio = maxSide / originalSize.longestSide;
      return Size(ratio * originalSize.width, ratio * originalSize.height);
    } else {
      final maxSide = 0.25 * widgetSize.shortestSide;
      final ratio = maxSide / originalSize.longestSide;
      return Size(ratio * originalSize.width, ratio * originalSize.height);
    }
  }

  void _drawImageOverlay(
      Canvas canvas, Offset position, Size size, QrEmbeddedImageStyle? style) {
    final paint = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.high;
    if (style != null) {
      if (style.color != null) {
        paint.colorFilter = ColorFilter.mode(style.color!, BlendMode.srcATop);
      }
    }
    final srcSize =
        Size(embeddedImage!.width.toDouble(), embeddedImage!.height.toDouble());
    final src = Alignment.center.inscribe(srcSize, Offset.zero & srcSize);
    final dst = Alignment.center.inscribe(size, position & size);

    canvas.drawImageRect(embeddedImage!, src, dst, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldPainter) {
    if (oldPainter is QrPainter) {
      return errorCorrectionLevel != oldPainter.errorCorrectionLevel ||
          _calcVersion != oldPainter._calcVersion ||
          _qr != oldPainter._qr ||
          gapless != oldPainter.gapless ||
          embeddedImage != oldPainter.embeddedImage ||
          embeddedImageStyle != oldPainter.embeddedImageStyle ||
          eyeStyle != oldPainter.eyeStyle ||
          dataModuleStyle != oldPainter.dataModuleStyle;
    }
    return true;
  }

  /// Returns a [ui.Picture] object containing the QR code data.
  ui.Picture toPicture(Size size) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    paint(canvas, size);
    return recorder.endRecording();
  }

  /// Returns an image in SVG format
  String toSVG(
    Size size,
    [
      String? centerSVG
    ]
  ){
    String convertedSVG(){
      if(centerSVG == null) return '';
      List<String> cs = centerSVG.split('>');
      String info = '';
      bool start = false;
      final ws = centerSVG.split('width="')[1].split('" ')[0];
      final hs = centerSVG.split('height="')[1].split('" ')[0];
      late double width;
      late double height;
      if(ws.contains('%')){
        width = 320*(double.parse(ws.replaceAll('%', ''))/100);
      }
      else{
        width = double.parse(ws);
      }

      if(ws.contains('%')){
        height = 320*(double.parse(hs.replaceAll('%', ''))/100);
      }
      else{
        height = double.parse(hs);
      }

      final msa = math.max(width,height);
      final s =  math.max(size.width, size.height)/msa*0.25;

      for(int i = 0; i < cs.length;i++){
        if(cs[i].contains('<svg') || cs[i].contains('</svg')){
          start = !start;
        }
        else if(start){
          info += '${cs[i]}>';
        }
      }
      return '<g transform="translate(${size.width/2-(width*s)/2},${size.height/2-(height*s)/2}) scale($s)">\n$info\n</g>';
    }
    Rect rotatePoint(Rect c){
      final rad = 90*math.pi/180;
      final si = math.sin(rad);
      final co = math.cos(rad);
      final cx = size.width/2;
      final cy = size.height/2;

      // translate point back to origin:
      final px = c.center.dx-cx;
      final py = c.center.dy-cy;

      // rotate point
      final xnew = px * co - py * si;
      final ynew = px * si + py * co;

      // translate point back:
      return Rect.fromCenter(
        center: Offset(size.width-(xnew + cx), (ynew+cy)),
        width:c.width,
        height: c.height
      );
    }
    String svg = '<svg id="Layer_1" data-name="Layer 1" xmlns="http://www.w3.org/2000/svg" width="100%" height="100%" viewBox="0 0 ${size.width} ${size.height}" class="qrCode">\n';

    for(int i = 0; i < _rects.length;i++){
      if(_rects[i].keys.contains('Rect')){
        final r = rotatePoint(_rects[i]['Rect']);
        Paint p = _rects[i]['paint'];
        final sw = p.strokeWidth;
        bool finder = _rects[i]['finder'];
        final hexColor = p.color.value.toRadixString(16).substring(2);
        if(hexColor != 'ffffff' && sw == 0){
          svg += '\t<rect x="${r.top}" y="${r.left}" width="${r.size.width}" height="${r.size.height}" style="fill: #$hexColor;"></rect>\n';
        }
        else if(hexColor != 'ffffff' && finder && sw != 0){
          svg += '\t<rect x="${r.top}" y="${r.left}" width="${r.size.width}" height="${r.size.height}" style="stroke-width:10; stroke:#$hexColor; fill: #ffffff;"></rect>\n';
        }
      }
      else if(_rects[i].keys.contains('RRect')){
        RRect rr = _rects[i]['RRect'];
        final r = rotatePoint(
          Rect.fromLTWH(rr.left, rr.top, rr.width, rr.height)
        );
        Paint p = _rects[i]['paint'];
        bool finder = _rects[i]['finder'];
        final hexColor = p.color.value.toRadixString(16).substring(2);
        final sw = p.strokeWidth;
        if(hexColor != 'ffffff' && !finder){
          final radius = r.width/2;
          //svg += '\t<rect x="${r.top}" y="${r.left}" width="${r.width}" height="${r.height}" rx="${rr.blRadiusX}" ry="${rr.blRadiusX}" style="fill: #$hexColor;"></rect>\n';
          svg += '\t<circle cx="${r.top+radius}" cy="${r.left+radius}" r="$radius" style="fill: #$hexColor;"></circle>\n';
        }
        else if(hexColor != 'ffffff' && sw == 0 && finder){
          svg += '\t<rect x="${r.top}" y="${r.left}" rx="${rr.blRadiusX}" ry="${rr.blRadiusX}" width="${r.width}" height="${r.height}"  style="fill: #$hexColor;"></rect>\n';
        }
        else if(hexColor != 'ffffff' && finder && sw != 0){
          svg += '\t<rect x="${r.top}" y="${r.left}" rx="${rr.blRadiusX}" ry="${rr.blRadiusY}" width="${r.size.width}" height="${r.size.height}"  style="stroke-width:10; stroke:#$hexColor; fill: #ffffff;"></rect>\n';
        }
      }
    }

    svg += '${convertedSVG()}\n</svg>';
    return svg;
  }

  /// Returns the raw QR code [ui.Image] object.
  Future<ui.Image> toImage(Size size,
      {ui.ImageByteFormat format = ui.ImageByteFormat.png}) async {
    return await toPicture(size).toImage(size.width.toInt(), size.height.toInt());
  }

  /// Returns the raw QR code image byte data.
  Future<ByteData?> toImageData(Size size,
      {ui.ImageByteFormat format = ui.ImageByteFormat.png}) async {
    final image = await toImage(size, format: format);
    return image.toByteData(format: format);
  }
}

class _PaintMetrics {
  _PaintMetrics(
      {required this.containerSize,
      required this.gapSize,
      required this.moduleCount}) {
    _calculateMetrics();
  }

  final int moduleCount;
  final double containerSize;
  final double gapSize;

  late final double _pixelSize;
  double get pixelSize => _pixelSize;

  late final double _innerContentSize;
  double get innerContentSize => _innerContentSize;

  late final double _inset;
  double get inset => _inset;

  void _calculateMetrics() {
    final gapTotal = (moduleCount - 1) * gapSize;
    var pixelSize = (containerSize - gapTotal) / moduleCount;
    _pixelSize = (pixelSize * 2).roundToDouble() / 2;
    _innerContentSize = (_pixelSize * moduleCount) + gapTotal;
    _inset = (containerSize - _innerContentSize) / 2;
  }
}

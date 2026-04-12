import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Helper class to fix common overflow issues
class OverflowFixHelper {
  /// Wrap text in Expanded to prevent overflow in Rows
  static Widget wrapTextInRow(Widget textWidget) {
    return Expanded(child: textWidget);
  }

  /// Wrap text in Flexible to prevent overflow in Columns
  static Widget wrapTextInColumn(Widget textWidget) {
    return Flexible(child: textWidget);
  }

  /// Create a scrollable container
  static Widget makeScrollable(Widget child, {bool shrinkWrap = false}) {
    return SingleChildScrollView(
      child: child,
    );
  }

  /// Create responsive text with overflow handling
  static Widget responsiveText(
    String text, {
    double? fontSize,
    Color? color,
    FontWeight? fontWeight,
    int maxLines = 1,
    TextOverflow overflow = TextOverflow.ellipsis,
    TextAlign? textAlign,
  }) {
    return Text(
      text,
      style: TextStyle(
        fontSize: fontSize?.sp ?? 14.sp,
        color: color,
        fontWeight: fontWeight,
      ),
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }

  /// Wrap Row children with Expanded where needed
  static List<Widget> wrapRowChildren(List<Widget> children, {List<bool>? shouldExpand}) {
    if (shouldExpand == null) {
      // Auto-detect: wrap Text widgets in Expanded
      return children.map((child) {
        if (child is Text) {
          return Expanded(child: child);
        }
        return child;
      }).toList();
    }
    
    return List.generate(children.length, (index) {
      if (index < shouldExpand.length && shouldExpand[index]) {
        return Expanded(child: children[index]);
      }
      return children[index];
    });
  }
}

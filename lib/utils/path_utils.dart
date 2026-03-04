// File: utils/path_utils.dart
import 'dart:core';

String safeDecodeComponent(String s) {
  try {
    return Uri.decodeComponent(s);
  } catch (e) {
    return s;
  }
}

String safeEncodeComponent(String s) {
  try {
    return Uri.encodeComponent(s);
  } catch (e) {
    return s;
  }
}

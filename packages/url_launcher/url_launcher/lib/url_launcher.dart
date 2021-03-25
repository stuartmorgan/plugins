// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// The desired mode to launch a URL.
///
/// Support for these modes varies by platform. Platforms that do not support
/// the requested mode may substitute another mode. See [launchUrl] for more
/// details.
enum LaunchMode {
  /// Leaves the decision of how to launch the URL to the platform
  /// implementation.
  platformDefault,

  /// Loads the URL in an-in web view (e.g., Safari View Controller).
  inAppWebView,

  /// Passes the URL to the OS to be handled by another application.
  externalApplication,

  /// Passes the URL to the OS to be handled by another non-browser application.
  externalNonBrowserApplication,
}

/// Additional configuration options for web URLs. Except where noted, these
/// options are only supported when the URL is launched in an in-app web view.
class WebConfiguration {
  /// Creates a new WebConfiguration with the given settings.
  const WebConfiguration({
    this.enableJavaScript = false,
    this.enableDomStorage = false,
    this.headers = const <String, String>{},
    this.webOnlyWindowName,
  });

  /// Whether or not JavaScript is enabled for the web content.
  final bool enableJavaScript;

  /// Whether or not DOM storage is enabled for the web content.
  final bool enableDomStorage;

  /// Additional headers to pass in the load request.
  ///
  /// On Android, this may work even when not loading in an in-app web view.
  /// When loading in an external browsers, this sets
  /// [Browser.EXTRA_HEADERS](https://developer.android.com/reference/android/provider/Browser#EXTRA_HEADERS)
  /// Not all browsers support this, so it is not guaranteed to be honored.
  final Map<String, String> headers;

  /// For web, a target for the launch. This supports the standard special link
  /// target names. E.g.:
  ///  - "_blank" opens the new URL in a new tab.
  ///  - "_self" opens the new URL in the current tab.
  /// Default behaviour when unset is to open the url in a new tab.
  final String? webOnlyWindowName;
}

/// Passes [url] to the underlying platform for handling.
///
/// The returned future completes with a [PlatformException] for URLs which
/// cannot be handled, such as:
///   - when [canLaunchUri] would return false.
///   - when [LaunchMode.externalNonBrowserApplication] is set on a supported
///     platform, and there is no non-browser app available to handle it.
///
/// [mode] support varies significantly by platform:
///   - [LaunchMode.platformDefault] is supported on all platforms:
///     - On iOS 9+ and Android, this treats web URLs as
///       [LaunchMode.inAppWebView], and all other URLs as
///       [LaunchMode.externalApplication].
///     - On Windows, macOS, Linux, and iOS 8 this behaves like
///       [LaunchMode.externalApplication].
///     - On web, this uses the [WebConfiguration]'s `webOnlyWindowName`
///       setting for web URLs, and behaves like
///       [LaunchMode.externalApplication] for any other content.
///   - [LaunchMode.inAppWebView] is currently only supported on iOS and
///     Android. If a non-web URL is passed with this mode, an [ArgumentError]
///     will be thrown.
///   - [LaunchMode.externalApplication] is supported on all platforms.
///     On iOS, this should be used in cases where sharing the cookies of the
///     user's browser is important, such as SSO flows, since Safari View
///     Controller does not share the browser's context.
///   - [LaunchMode.externalNonBrowserApplication] is supported on iOS 10+.
///     This setting is used to require universal links to open in a non-browser
///     application.
///
/// Returns true if the URL launched successful; false is only returned when the
/// launch mode is [LaunchMode.externalNonBrowserApplication]
/// and no non-browser application was available to handle the URL.
Future<bool> launchUrl(
  Uri url, {
  LaunchMode mode = LaunchMode.platformDefault,
  WebConfiguration webConfiguration = const WebConfiguration(),
  Map<String, String> headers = const <String, String>{},
  String? webOnlyWindowName,
}) async {
  final bool isWebURL = url.scheme == 'http' || url.scheme == 'https';
  if (mode == LaunchMode.inAppWebView && !isWebURL) {
    throw PlatformException(
        code: 'NOT_A_WEB_SCHEME',
        message: 'To use an in-app web view, you must provide a web URL. '
            '"$url" is not a web URL.');
  }
  final bool useWebView = mode == LaunchMode.inAppWebView ||
      (isWebURL && mode == LaunchMode.platformDefault);

  return await UrlLauncherPlatform.instance.launch(
    url.toString(),
    useSafariVC: useWebView,
    useWebView: useWebView,
    enableJavaScript: webConfiguration.enableJavaScript,
    enableDomStorage: webConfiguration.enableDomStorage,
    universalLinksOnly: mode == LaunchMode.externalNonBrowserApplication,
    headers: headers,
    webOnlyWindowName: webOnlyWindowName,
  );
}

/// Deprecated String form of canLaunchUrl.
@Deprecated('Use launchUrl')
Future<bool> launch(
  String urlString, {
  bool? forceSafariVC,
  bool forceWebView = false,
  bool enableJavaScript = false,
  bool enableDomStorage = false,
  bool universalLinksOnly = false,
  Map<String, String> headers = const <String, String>{},
  Brightness? statusBarBrightness,
  String? webOnlyWindowName,
}) async {
  final Uri? url = Uri.tryParse(urlString.trimLeft());
  if (url == null) {
    throw ArgumentError('Invalid URL: "$urlString"');
  }

  final WebConfiguration webConfig = WebConfiguration(
    enableDomStorage: enableDomStorage,
    enableJavaScript: enableJavaScript,
  );
  // Map the legacy arguments back to the resulting launch mode.
  final bool isWebURL = url.scheme == 'http' || url.scheme == 'https';
  LaunchMode mode = LaunchMode.platformDefault;
  if (Platform.isIOS) {
    if (forceSafariVC == false && universalLinksOnly) {
      mode = LaunchMode.externalNonBrowserApplication;
    } else {
      mode = (forceSafariVC ?? isWebURL)
          ? LaunchMode.inAppWebView
          : LaunchMode.externalApplication;
    }
  } else if (Platform.isAndroid) {
    mode =
        forceWebView ? LaunchMode.inAppWebView : LaunchMode.externalApplication;
  }

  /// [true] so that ui is automatically computed if [statusBarBrightness] is set.
  bool previousAutomaticSystemUiAdjustment = true;
  if (statusBarBrightness != null &&
      defaultTargetPlatform == TargetPlatform.iOS &&
      WidgetsBinding.instance != null) {
    previousAutomaticSystemUiAdjustment =
        WidgetsBinding.instance!.renderView.automaticSystemUiAdjustment;
    WidgetsBinding.instance!.renderView.automaticSystemUiAdjustment = false;
    SystemChrome.setSystemUIOverlayStyle(statusBarBrightness == Brightness.light
        ? SystemUiOverlayStyle.dark
        : SystemUiOverlayStyle.light);
  }

  bool result = await launchUrl(
    url,
    mode: mode,
    webConfiguration: webConfig,
    headers: headers,
    webOnlyWindowName: webOnlyWindowName,
  );

  if (statusBarBrightness != null && WidgetsBinding.instance != null) {
    WidgetsBinding.instance!.renderView.automaticSystemUiAdjustment =
        previousAutomaticSystemUiAdjustment;
  }

  return result;
}

/// Checks whether the specified URL can be handled by some app installed on the
/// device.
///
/// On Android (from API 30), [canLaunchUrl] will return `false` when the
/// required visibility configuration is not provided in the AndroidManifest.xml
/// file. For more information see the
/// [Managing packagevisibility](https://developer.android.com/training/basics/intents/package-visibility)
/// article in the Android docs.
Future<bool> canLaunchUrl(Uri uri) async {
  return await UrlLauncherPlatform.instance.canLaunch(uri.toString());
}

/// Deprecated String form of canLaunchUrl.
@Deprecated('Use canLaunchUrl')
Future<bool> canLaunch(String urlString) async {
  return await UrlLauncherPlatform.instance.canLaunch(urlString);
}

/// Closes the current WebView, if one was previously opened via a call to [launchUrl].
///
/// If [launchUrl] was never called, or if [launchUrl] was called such that the
/// URL was launched externally rather than in an inline view, then this call
/// will not have any effect.
///
/// On Android systems, if [launchUrl] was called without `forceWebView` being set to `true`
/// Or on IOS systems, if [launch] was called without `forceSafariVC` being set to `true`,
/// this call will not do anything either, simply because there is no
/// WebView/SafariViewController available to be closed.
///
/// SafariViewController is only available on IOS version >= 9.0, this method does not do anything
/// on IOS version below 9.0
Future<void> closeWebView() async {
  return await UrlLauncherPlatform.instance.closeWebView();
}

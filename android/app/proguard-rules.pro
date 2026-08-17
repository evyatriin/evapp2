# Keep Flutter embedding and plugin registration stable in release builds.
-keep class com.evranger.ev_router_app2.MainActivity { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# Preserve classes accessed reflectively by Google Mobile Ads and Maps SDK.
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.android.gms.maps.** { *; }

# Preserve bluetooth plugin entry points used through generated registrants.
-keep class com.lib.flutter_blue_plus.** { *; }
-keep class io.github.edufolly.flutterbluetoothserial.** { *; }
-keep class prof.ronny.bluetooth_serial_android.** { *; }

import 'dart:math' as math;
import 'dart:ui';

class IsometricUtils {
  // Isometric projection angles (30 degrees)
  static const double isoAngle = math.pi / 6; // 30 degrees in radians
  static const double cosAngle = 0.866; // cos(30°)
  static const double sinAngle = 0.5;   // sin(30°)
  
  /// Convert 3D coordinates to 2D isometric screen coordinates
  static Offset projectToScreen(double x, double y, double z, {double scale = 100}) {
    final screenX = (x - z) * cosAngle * scale;
    final screenY = (x + z) * sinAngle * scale - y * scale;
    return Offset(screenX, screenY);
  }
  
  /// Convert 2D screen coordinates back to 3D world coordinates (Y = 0)
  static Offset screenToWorld(Offset screenPos, {double scale = 100}) {
    final screenX = screenPos.dx / scale;
    final screenY = screenPos.dy / scale;
    
    // Inverse isometric projection (assuming Y = 0)
    final x = (screenX / cosAngle + screenY / sinAngle) / 2;
    final z = (screenY / sinAngle - screenX / cosAngle) / 2;
    
    return Offset(x, z);
  }
  
  /// Get the four corners of a 3D box in screen coordinates
  static List<Offset> getBoxCorners(
    double x, double y, double z,
    double width, double height, double depth,
    {double scale = 100}
  ) {
    return [
      projectToScreen(x, y, z, scale: scale),                    // bottom front left
      projectToScreen(x + width, y, z, scale: scale),           // bottom front right
      projectToScreen(x + width, y, z + depth, scale: scale),   // bottom back right
      projectToScreen(x, y, z + depth, scale: scale),           // bottom back left
      projectToScreen(x, y + height, z, scale: scale),          // top front left
      projectToScreen(x + width, y + height, z, scale: scale),  // top front right
      projectToScreen(x + width, y + height, z + depth, scale: scale), // top back right
      projectToScreen(x, y + height, z + depth, scale: scale),  // top back left
    ];
  }
  
  /// Snap a value to grid
  static double snapToGrid(double value, double gridSize) {
    return (value / gridSize).round() * gridSize;
  }
  
  /// Check if a point is inside a rectangle in 3D space (projected to XZ plane)
  static bool isPointInBounds(double x, double z, double width, double depth) {
    return x >= 0 && x <= width && z >= 0 && z <= depth;
  }
}
import '../models/box.dart';
import '../models/trunk_space.dart';

class CollisionUtils {
  /// Check if two boxes overlap in 3D space
  static bool boxesOverlap(Box box1, Box box2) {
    // Get actual dimensions considering rotation
    final box1Dims = _getRotatedDimensions(box1);
    final box2Dims = _getRotatedDimensions(box2);
    
    // Check overlap in X axis
    if (box1.x + box1Dims.width <= box2.x || 
        box2.x + box2Dims.width <= box1.x) {
      return false;
    }
    
    // Check overlap in Z axis
    if (box1.z + box1Dims.depth <= box2.z || 
        box2.z + box2Dims.depth <= box1.z) {
      return false;
    }
    
    // Check overlap in Y axis
    if (box1.y + box1.height <= box2.y || 
        box2.y + box2.height <= box1.y) {
      return false;
    }
    
    return true;
  }
  
  /// Check if box is within trunk boundaries
  static bool isBoxInBounds(Box box, TrunkSpace trunkSpace) {
    final dims = _getRotatedDimensions(box);
    
    return box.x >= 0 && 
           box.z >= 0 && 
           box.x + dims.width <= trunkSpace.width &&
           box.z + dims.depth <= trunkSpace.depth &&
           box.y + box.height <= trunkSpace.height;
  }
  
  /// Check if box overlaps with any wheelhouse
  static bool boxOverlapsWheelhouse(Box box, TrunkSpace trunkSpace) {
    final dims = _getRotatedDimensions(box);
    
    for (final wheelhouse in trunkSpace.wheelhouses) {
      // Check if box overlaps with wheelhouse
      if (!(box.x + dims.width <= wheelhouse.x || 
            wheelhouse.x + wheelhouse.width <= box.x ||
            box.z + dims.depth <= wheelhouse.z || 
            wheelhouse.z + wheelhouse.depth <= box.z ||
            box.y + box.height <= 0 || // Box above wheelhouse
            wheelhouse.height <= box.y)) { // Wheelhouse below box
        return true;
      }
    }
    
    return false;
  }
  
  /// Get list of boxes that collide with the given box
  static List<Box> getCollidingBoxes(Box targetBox, List<Box> allBoxes) {
    return allBoxes
        .where((box) => box.id != targetBox.id && boxesOverlap(targetBox, box))
        .toList();
  }
  
  /// Check if box has any collision (with other boxes, wheelhouses, or boundaries)
  static bool hasAnyCollision(Box box, List<Box> otherBoxes, TrunkSpace trunkSpace) {
    // Check boundary collision
    if (!isBoxInBounds(box, trunkSpace)) {
      return true;
    }
    
    // Check wheelhouse collision
    if (boxOverlapsWheelhouse(box, trunkSpace)) {
      return true;
    }
    
    // Check box-to-box collisions
    return getCollidingBoxes(box, otherBoxes).isNotEmpty;
  }
  
  /// Get rotated dimensions of a box
  static ({double width, double depth}) _getRotatedDimensions(Box box) {
    if (box.rotationY == 90 || box.rotationY == 270) {
      return (width: box.depth, depth: box.width);
    }
    return (width: box.width, depth: box.depth);
  }
  
  /// Find nearest valid position for a box (for snapping after invalid placement)
  static ({double x, double z}) findNearestValidPosition(
    Box box, 
    List<Box> otherBoxes, 
    TrunkSpace trunkSpace,
    double gridSize,
  ) {
    final dims = _getRotatedDimensions(box);
    
    // Start from current position and expand search
    double bestX = box.x;
    double bestZ = box.z;
    double minDistance = double.infinity;
    
    // Search in a grid pattern around the current position
    final maxSearchRadius = 2.0; // 2 meters search radius
    final step = gridSize;
    
    for (double searchX = -maxSearchRadius; 
         searchX <= maxSearchRadius; 
         searchX += step) {
      for (double searchZ = -maxSearchRadius; 
           searchZ <= maxSearchRadius; 
           searchZ += step) {
        
        final testX = (box.x + searchX / step).round() * step;
        final testZ = (box.z + searchZ / step).round() * step;
        
        // Skip if out of bounds
        if (testX < 0 || testZ < 0 || 
            testX + dims.width > trunkSpace.width ||
            testZ + dims.depth > trunkSpace.depth) {
          continue;
        }
        
        // Create test box
        final testBox = Box(
          id: box.id,
          width: box.width,
          depth: box.depth,
          height: box.height,
          x: testX,
          y: box.y,
          z: testZ,
          rotationY: box.rotationY,
        );
        
        // Check if position is valid
        if (!hasAnyCollision(testBox, otherBoxes, trunkSpace)) {
          final distance = (searchX * searchX + searchZ * searchZ);
          if (distance < minDistance) {
            minDistance = distance;
            bestX = testX;
            bestZ = testZ;
          }
        }
      }
    }
    
    return (x: bestX, z: bestZ);
  }
}
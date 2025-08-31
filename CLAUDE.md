# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TrimBox Simulator is a Flutter application for simulating trunk/cargo space packing with boxes in an isometric 3D view. Users can add boxes with custom dimensions, drag and position them in a virtual SUV trunk space, and visualize packing efficiency.

## Project Requirements

Based on the backlog files in `/backlog/`:

### Core Features (from PRD)
- **Isometric trunk visualization**: 3D-like view of trunk space with floor grid (10cm units)
- **Box management**: Create, rotate (90°), move, and delete boxes with custom W×D×H dimensions
- **Collision detection**: Visual feedback (red borders) when boxes overlap or exceed boundaries
- **Wheelhouse modeling**: Two protruding rectangular areas that boxes must avoid
- **Save/Load**: JSON-based scene persistence
- **Snap-to-grid**: Automatic 10cm grid alignment for precise placement

### Target Trunk Sizes
- Small: 2×2m
- Medium: 3×3m  
- Large: 4×4m

### Architecture Focus
- Use Flutter's rendering engine (Impeller preferred) for 2D/isometric graphics
- Custom painting with `CustomPainter` for trunk floor, grid, and wheelhouse visualization
- Physics-based drag & drop with constraint validation
- JSON serialization for save/load functionality

## Development Commands

This is a Flutter project. Common commands include:

```bash
# Get dependencies
flutter pub get

# Run in debug mode
flutter run

# Run tests
flutter test

# Build for release
flutter build apk    # Android
flutter build ipa    # iOS
flutter build web    # Web

# Analyze code
flutter analyze

# Format code
dart format .
```

## Key Technical Considerations

### Flutter Rendering
- Use `CustomPainter` for isometric trunk visualization
- Implement drag gesture detection with `GestureDetector`
- Use `Transform` widgets for box positioning and rotation
- Consider `RepaintBoundary` for performance optimization

### 3D/Isometric Rendering
- Implement isometric projection using matrix transformations
- Use Flutter's built-in graphics capabilities rather than external 3D engines
- Custom fragment shaders may be useful for advanced visual effects

### State Management
- Manage box positions, rotations, and collision states
- Track trunk dimensions and wheelhouse constraints
- Handle save/load state persistence

### Testing Strategy
- Aim for 95% unit test coverage
- Test collision detection algorithms
- Test JSON serialization/deserialization
- Test drag & drop gesture handling
- Test grid snapping logic

## Project Structure

The project follows Flutter's standard structure with additional focus on:
- Custom painters for isometric rendering
- Geometry utilities for collision detection
- JSON models for data persistence
- Widget hierarchy for interactive 3D-like UI

## Commit Strategy

Work in incremental steps with focused commits:
1. Set up basic Flutter project structure
2. Implement isometric trunk visualization
3. Add box creation and basic positioning
4. Implement drag & drop with grid snapping
5. Add collision detection and visual feedback
6. Implement rotation functionality
7. Add save/load JSON persistence
8. Create comprehensive tests
9. Polish UI and add wheelhouse constraints

Focus on getting each feature working completely before moving to the next step.
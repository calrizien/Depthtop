# CS_HoverEffect to Depthtop Migration Plan

## Key Components from CS_HoverEffect to Migrate

### Core Architecture Components
1. **CompositorServicesHoverEffectApp.swift** - Main app structure with RemoteImmersiveSpace
2. **CompositorServicesHoverEffectApp+CompositorLayer.swift** - CompositorLayer configuration
3. **CompositorServicesHoverEffectApp+Render.swift** - Main render loop entry
4. **RenderData.swift** - Core rendering state manager (Actor-based)
5. **RenderData+Render.swift** - Render loop implementation
6. **RenderData+AssetLoad.swift** - Asset loading pipeline
7. **Data Structures.swift** - Shared types and structures

### Shader Pipeline
1. **Shaders.metal** - Metal shaders (will adapt to use our window textures)
2. **ShaderTypes.h** - Shared header between Swift and Metal
3. **TileResolvePipeline.swift** - MSAA and hover effect pipeline

### Extensions & Utilities
1. **CompositorLayer+FunctionInit.swift** - Helper functions
2. **LayerRenderer-Clock-Instant-Duration+timeInterval.swift** - Timing utilities
3. **SIMD+Utilities.swift** - Math helpers

### Components to Keep from Depthtop
1. **ContentView.swift** - Window capture UI
2. **AppModel.swift** - Window capture state (merge with CS_HoverEffect's AppModel)
3. **Window capture shaders** - Our working texture rendering code
4. **WindowRenderData.swift** - Window texture management
5. **Logger.swift** - Logging utilities

## Migration Strategy

### Phase 1: Foundation Setup
- Copy CS_HoverEffect app structure
- Preserve Depthtop's window capture UI
- Merge AppModel classes

### Phase 2: Rendering Pipeline
- Integrate CS_HoverEffect's RenderData actor
- Adapt shaders to render window textures instead of 3D models
- Configure CompositorLayer for window rendering

### Phase 3: Integration
- Connect window capture to new rendering pipeline
- Pass window textures to Metal shaders
- Test RemoteImmersiveSpace functionality

### Phase 4: Cleanup
- Remove unused CS_HoverEffect features (hover effects, 3D model loading)
- Optimize for window rendering use case
- Update documentation
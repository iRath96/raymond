#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <Cocoa/Cocoa.h>

#include <string>
#include <vector>
#include <map>

#include "main.h"

#import "Raymond-Swift.h"

#include "imgui.h"
#include "implot.h"
#include "imgui_impl_metal.h"
#include "imgui_impl_osx.h"

#include "console.hpp"
#include "utils/inspector.hpp"


@interface AppViewController () <MTKViewDelegate>
@property (nonatomic, readonly) MTKView *mtkView;
@property (nonatomic, strong) id <MTLDevice> device;
@property (nonatomic, strong) id <MTLCommandQueue> commandQueue;

@property (nonatomic, strong) Lens *lens;
@property (nonatomic, strong) LensLoader *lensLoader;
@property (nonatomic, strong) NSMutableArray *availableLenses;

@property (nonatomic, retain) Renderer *renderer;
@property (nonatomic) UIState state;
@property (nonatomic) bool viewportHovered;
@property (nonatomic) float gestureSpeed;
@end

const char *makeCString(NSString *str) {
    /// @todo is there a more elegant way to do this?
    const char *original = [str cStringUsingEncoding:NSASCIIStringEncoding];
    const size_t length = strlen(original);
    char *copy = (char *)malloc(length + 1);
    strcpy(copy, original);
    return copy;
}

//-----------------------------------------------------------------------------------
// AppViewController
//-----------------------------------------------------------------------------------

@implementation AppViewController

- (NSURL *)applicationDataDirectory {
    NSFileManager* sharedFM = [NSFileManager defaultManager];
    NSArray* possibleURLs = [sharedFM URLsForDirectory:NSApplicationSupportDirectory
                                 inDomains:NSUserDomainMask];
    NSURL* appSupportDir = nil;
    NSURL* appDirectory = nil;

    if ([possibleURLs count] >= 1) {
        // Use the first directory (if multiple are returned)
        appSupportDir = [possibleURLs objectAtIndex:0];
    }

    // If a valid app support directory exists, add the
    // app's bundle ID to it to specify the final directory.
    if (appSupportDir) {
        NSString* appBundleID = [[NSBundle mainBundle] bundleIdentifier];
        appDirectory = [appSupportDir URLByAppendingPathComponent:appBundleID];
    }

    [sharedFM createDirectoryAtURL:appDirectory withIntermediateDirectories:YES attributes:NULL error:NULL];
    return appDirectory;
}

-(instancetype)initWithRenderer:(Renderer *)renderer {
    self = [super initWithNibName:nil bundle:nil];
    
    _device = MTLCreateSystemDefaultDevice();
    _commandQueue = [_device newCommandQueue];
    _renderer = renderer;
    _gestureSpeed = 0.01f;
    _lensLoader = [LensLoader new];
    
    _availableLenses = [NSMutableArray new];
    NSArray *lensURLs = [[NSBundle mainBundle] URLsForResourcesWithExtension:@"len" subdirectory:@"data/lenses"];
    for (NSURL *lensURL in lensURLs) {
        NSString *filename = [[lensURL lastPathComponent] stringByDeletingPathExtension];
        [_availableLenses addObject:filename];
    }
    [_availableLenses sortUsingSelector:@selector(caseInsensitiveCompare:)];

    if (!self.device)
    {
        NSLog(@"Metal is not supported");
        abort();
    }

    // Setup Dear ImGui context
    // FIXME: This example doesn't have proper cleanup...
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    
    ImGuiIO& io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
    io.ConfigFlags |= ImGuiConfigFlags_DockingEnable;

    // Setup Dear ImGui style
    ImGui::StyleColorsDark();
    //ImGui::StyleColorsLight();
    
    // FIXME: hack so that colors look good
    auto &colors = ImGui::GetStyle().Colors;
    for (int i = 0; i < ImGuiCol_COUNT; i++) {
        colors[i].x = pow(colors[i].x, 2.4f);
        colors[i].y = pow(colors[i].y, 2.4f);
        colors[i].z = pow(colors[i].z, 2.4f);
    }

    // Setup Renderer backend
    ImGui_ImplMetal_Init(_device);

    io.Fonts->AddFontFromFileTTF("/System/Library/Fonts/SFNS.ttf", 30);
    io.Fonts->AddFontFromFileTTF("/System/Library/Fonts/Monaco.ttf", 26);
    io.FontGlobalScale = 0.5;
    
    NSURL *appDir = [self applicationDataDirectory];
    NSString *iniPath = [[appDir URLByAppendingPathComponent:@"imgui.ini"] relativePath];
    io.IniFilename = makeCString(iniPath);
    
    [SwiftLogger.shared debug:[NSString stringWithFormat:@"storing imgui config to %s", io.IniFilename]];
    
    return self;
}

-(MTKView *)mtkView
{
    return (MTKView *)self.view;
}

-(void)loadView
{
    self.view = [[MTKView alloc] initWithFrame:CGRectMake(0, 0, 1200, 720)];
}

-(void)viewDidLoad
{
    [super viewDidLoad];

    self.mtkView.device = self.device;
    self.mtkView.delegate = self;
    
    self.mtkView.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    self.mtkView.colorPixelFormat = MTLPixelFormatRGBA16Float;
    self.mtkView.sampleCount = 1;
    self.mtkView.preferredFramesPerSecond = 120;
    self.mtkView.colorspace = CGColorSpaceCreateWithName(kCGColorSpaceLinearDisplayP3);

#if TARGET_OS_OSX
    ImGui_ImplOSX_Init(self.view);
    [NSApp activateIgnoringOtherApps:YES];
#endif
    
    ImPlot::CreateContext();
}

static void HelpMarker(const char *desc) {
    ImGui::TextDisabled("(?)");
    if (ImGui::IsItemHovered(ImGuiHoveredFlags_DelayShort)) {
        ImGui::BeginTooltip();
        ImGui::PushTextWrapPos(ImGui::GetFontSize() * 35.0f);
        ImGui::TextUnformatted(desc);
        ImGui::PopTextWrapPos();
        ImGui::EndTooltip();
    }
}

static void drawAperture(float relstop, int numBlades, float scale = 100) {
    static std::vector<ImVec2> points;
    const int n = numBlades * (128 / numBlades);
    points.resize(n);
    
    const float piOverBlades = M_PI / numBlades;
    const float norm = std::sqrt(std::tan(piOverBlades) / piOverBlades);
    const float relstop2 = pow(relstop, 2);
    
    const ImVec2 region = ImGui::GetContentRegionAvail();
    const ImVec2 pos = ImGui::GetCursorScreenPos();
    for (int i = 0; i < n; i++) {
        const float phi = i / float(n);
        const float phiL = fmod(phi * numBlades, float(1)) - 0.5f;
        const float r = relstop / (relstop2 + (1 - relstop2) * norm * std::cos(2 * piOverBlades * phiL));
        const float phiRadians = 2 * M_PI * (phi + (1 - relstop) / 4);
        
        points[i] = ImVec2(
            pos.x + scale * (r * std::cos(phiRadians) + 1) / 2 + (region.x - scale) / 2,
            pos.y + scale * (r * std::sin(phiRadians) + 1) / 2
        );
    }
    
    const ImU32 color = ImGui::GetColorU32(IM_COL32(255, 255, 255, 255));
    const ImU32 color2 = ImGui::GetColorU32(IM_COL32(255, 255, 255, 64));
    ImDrawList *drawList = ImGui::GetWindowDrawList();
    drawList->AddCircle(ImVec2(pos.x + region.x / 2, pos.y + scale / 2), scale / 2, color2);
    drawList->AddPolyline(points.data(), int(points.size()), color, ImDrawFlags_Closed, 1.0f);
    ImGui::Dummy(ImVec2(region.x, scale));
}

-(void)drawInMTKView:(MTKView *)view
{
    ImGuiIO& io = ImGui::GetIO();
    io.DisplaySize.x = view.bounds.size.width;
    io.DisplaySize.y = view.bounds.size.height;

#if TARGET_OS_OSX
    CGFloat framebufferScale = view.window.screen.backingScaleFactor ?: NSScreen.mainScreen.backingScaleFactor;
#else
    CGFloat framebufferScale = view.window.screen.scale ?: UIScreen.mainScreen.scale;
#endif
    io.DisplayFramebufferScale = ImVec2(framebufferScale, framebufferScale);

    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];

    MTLRenderPassDescriptor* renderPassDescriptor = view.currentRenderPassDescriptor;
    if (renderPassDescriptor == nil)
    {
        [commandBuffer commit];
		return;
    }

    // Start the Dear ImGui frame
    ImGui_ImplMetal_NewFrame(renderPassDescriptor);
#if TARGET_OS_OSX
    ImGui_ImplOSX_NewFrame(view);
#endif
    ImGui::NewFrame();
    
    // use dockspaces
    ImGui::DockSpaceOverViewport(ImGui::GetMainViewport());
    
    if (ImGui::BeginMainMenuBar()) {
        if (ImGui::BeginMenu("Demos")) {
            ImGui::MenuItem("ImGui demo", nullptr, &_state.showImguiDemo);
            ImGui::MenuItem("ImPlot demo", nullptr, &_state.showImplotDemo);
            ImGui::EndMenu();
        }
        
        if (ImGui::BeginMenu("Window")) {
            ImGui::MenuItem("Show Console", nullptr, isConsoleOpen());
            ImGui::EndMenu();
        }
        
        HelpMarker(
            "When docking is enabled, you can ALWAYS dock MOST window into another! Try it now!" "\n"
            "- Drag from window title bar or their tab to dock/undock." "\n"
            "- Drag from window menu button (upper-left button) to undock an entire node (all windows)." "\n"
            "- Hold SHIFT to disable docking (if io.ConfigDockingWithShift == false, default)" "\n"
            "- Hold SHIFT to enable docking (if io.ConfigDockingWithShift == true)" "\n"
            "This demo app has nothing to do with enabling docking!" "\n\n"
            "This demo app only demonstrate the use of ImGui::DockSpace() which allows you to manually create a docking node _within_ another window." "\n\n"
            "Read comments in ShowExampleAppDockSpace() for more details.");

        ImGui::EndMainMenuBar();
    }
    
    drawConsole();

    // Our state (make them static = more or less global) as a convenience to keep the example terse.
    static ImVec4 clear_color = ImVec4(0.45f, 0.55f, 0.60f, 1.00f);

    // 1. Show the big demo window (Most of the sample code is in ImGui::ShowDemoWindow()! You can browse its code to learn more about Dear ImGui!).
    if (_state.showImguiDemo) ImGui::ShowDemoWindow(&_state.showImguiDemo);
    if (_state.showImplotDemo) ImPlot::ShowDemoWindow();
    
    _viewportHovered = false;
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(0, 0));
    if (ImGui::Begin("Viewport")) {
        const ImVec2 viewportSize = ImGui::GetContentRegionAvail();
        const ImVec2 scale = ImGui::GetIO().DisplayFramebufferScale;
        
        [_renderer setSizeWithWidth:int(scale.x * viewportSize.x) height:int(scale.y * viewportSize.y)];
        [_renderer executeIn:commandBuffer];
        
        const ImVec2 mouse = ImVec2(
            scale.x * (ImGui::GetMousePos().x - ImGui::GetCursorScreenPos().x),
            scale.y * (ImGui::GetMousePos().y - ImGui::GetCursorScreenPos().y)
        );
        ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(0, 0));
        ImGui::ImageButton((__bridge void *)_renderer.normalizedImage, viewportSize);
        ImGui::PopStyleVar();
        
        if (ImGui::IsItemHovered()) {
            if (ImGui::IsKeyDown(ImGuiKey_Space)) {
                ui_inspect_image(mouse.x, mouse.y, _renderer.normalizedImage);
            }
            _viewportHovered = true;
        }
    }
    ImGui::End();
    ImGui::PopStyleVar();
    
    {
        ImGui::Begin("Statistics");
        
        static float exposure = 0;
        bool uniformsChanged = false;
        
        ImGui::Text("%d frames", _renderer.uniforms->frameIndex);
        ImGui::Text("Average %.3f ms/frame (%.1f FPS)", 1000.0f / ImGui::GetIO().Framerate, ImGui::GetIO().Framerate);
        ImGui::Text("Resolution: %d x %d", int(_renderer.outputImageSize.width), int(_renderer.outputImageSize.height));
        ImGui::DragFloat("Speed", &_gestureSpeed, _gestureSpeed / 1000, 0, 100);
        ImGui::DragFloat("EV", &exposure, 0.01f, -20, 20);

        uniformsChanged |= ImGui::Checkbox("Accumulate", &_renderer.uniforms->accumulate);
        
        static const char *channels[] = { "Image", "Albedo", "Roughness" };
        uniformsChanged |= ImGui::Combo("Channel", (int *)&_renderer.uniforms->outputChannel, channels, sizeof(channels) / sizeof(*channels));
        
        static const char *samplingNames[] = { "BSDF", "NEE", "MIS" };
        uniformsChanged |= ImGui::Combo("Sampling", (int *)&_renderer.uniforms->samplingMode,
            samplingNames, sizeof(samplingNames) / sizeof(*samplingNames));
            
        static const char *rrNames[] = { "Disabled", "Throughput" };
        uniformsChanged |= ImGui::Combo("RR", (int *)&_renderer.uniforms->rr,
            rrNames, sizeof(rrNames) / sizeof(*rrNames));
        uniformsChanged |= ImGui::DragInt("RR depth", &_renderer.uniforms->rrDepth, 0.1f, 0, 16);
        
        static bool shouldSave = false;
        
        ImGui::BeginDisabled(shouldSave);
        shouldSave |= ImGui::Button("Save Frame");
        shouldSave |= ImGui::IsKeyDown(ImGuiKey_ModSuper) && ImGui::IsKeyPressed(ImGuiKey_S);
        ImGui::EndDisabled();
        
        if (shouldSave && (_renderer.uniforms->frameIndex % 50 == 0)) {
            [_renderer saveFrame];
            shouldSave = false;
        }
        
        float cameraScale = 1000 * _renderer.uniforms->cameraScale;
        uniformsChanged |= ImGui::DragFloat("Camera scale", &cameraScale, cameraScale / 1000, 0, 100);
        uniformsChanged |= ImGui::DragFloat("Sensor scale", &_renderer.uniforms->sensorScale, _renderer.uniforms->sensorScale / 1000, 0, 100);
        uniformsChanged |= ImGui::DragFloat("Focus", &_renderer.uniforms->focus, 0.001f, -100, 100);
        _renderer.uniforms->cameraScale = cameraScale / 1000;
        
        static int currentLensIndex = 0;
        static std::string currentLens = "(none)";
        
        if (ImGui::BeginCombo("Lens", currentLens.c_str())) {
            int index = 0;
            if (ImGui::Selectable("(none)", currentLensIndex == index)) {
                currentLensIndex = index;
                currentLens = "(none)";
                
                _lens = nil;
                [_renderer setLens:_lens];
                uniformsChanged = true;
            }
            if (currentLensIndex == index) {
                ImGui::SetItemDefaultFocus();
            }
            
            for (NSString *filename in _availableLenses) {
                index++;
                
                const bool isSelected = currentLensIndex == index;
                const char *filenameCStr = [filename cStringUsingEncoding:NSASCIIStringEncoding];
                if (ImGui::Selectable(filenameCStr, isSelected)) {
                    currentLensIndex = index;
                    currentLens = filenameCStr;
                    
                    NSURL *url = [[NSBundle mainBundle] URLForResource:filename withExtension:@"len" subdirectory:@"data/lenses"];
                    _lens = [_lensLoader load:url device:_device];
                    _renderer.uniforms->stopIndex = _lens.stopIndex;
                    [_renderer setLens:_lens];
                    uniformsChanged = true;
                }

                if (isSelected) {
                    ImGui::SetItemDefaultFocus();
                }
            }
            ImGui::EndCombo();
        }
        
        float lensEVCorrection = 1;
        static float aperture = 1.8f;
        if (_lens != nil) {
            ImGui::Text("%s", [_lens.name cStringUsingEncoding:NSASCIIStringEncoding]);
            ImGui::Text("EFL: %.1fmm", _lens.efl);
            ImGui::Text("F/#: %.1f", _lens.fstop);
            uniformsChanged |= ImGui::SliderInt("Stop #", &_renderer.uniforms->stopIndex, 1, _lens.numSurfaces - 1);
            
            aperture = std::max(aperture, _lens.fstop);
            _renderer.uniforms->relativeStop = _lens.fstop / aperture;
            
            uniformsChanged |= ImGui::DragFloat("Aperture", &aperture, aperture / 1000, _lens.fstop, 40.f);
            uniformsChanged |= ImGui::DragInt("Aperture blades", &_renderer.uniforms->numApertureBlades, 1, 3, 32);
            uniformsChanged |= ImGui::Checkbox("Spectral sampling", &_renderer.uniforms->lensSpectral);
            
            drawAperture(_renderer.uniforms->relativeStop, _renderer.uniforms->numApertureBlades);
            
            lensEVCorrection = M_PI/2 * std::pow(aperture, 2);
            
            ImGui::Text("Lens exposure: %+.2f EV", log2(lensEVCorrection));
        }
        
        static const char *tonemappingNames[] = { "Linear", "Hable", "ACES" };
        ImGui::Combo("Tonemapping", (int *)&_renderer.uniforms->tonemapping,
            tonemappingNames, sizeof(tonemappingNames) / sizeof(*tonemappingNames));

        _renderer.uniforms->exposure = pow(2, exposure) * lensEVCorrection;
        
        if (uniformsChanged) {
            [_renderer reset];
        }
        
        ImGui::End();
    }

    if (_viewportHovered && !ImGui::IsKeyDown(ImGuiKey_ModSuper)) {
        int moveW = ImGui::IsKeyDown(ImGuiKey_W) ? 1 : 0;
        int moveS = ImGui::IsKeyDown(ImGuiKey_S) ? 1 : 0;
        int moveA = ImGui::IsKeyDown(ImGuiKey_A) ? 1 : 0;
        int moveD = ImGui::IsKeyDown(ImGuiKey_D) ? 1 : 0;
        int moveQ = ImGui::IsKeyDown(ImGuiKey_Q) ? 1 : 0;
        int moveE = ImGui::IsKeyDown(ImGuiKey_E) ? 1 : 0;
        
        if (moveW || moveS || moveA || moveD || moveQ || moveE) {
            const simd_float4x4 zoom {{
                { 1, 0, 0, 30 * _gestureSpeed * (moveD - moveA) },
                { 0, 1, 0, 30 * _gestureSpeed * (moveQ - moveE) },
                { 0, 0, 1, 30 * _gestureSpeed * (moveS - moveW) },
                { 0, 0, 0, 1 }
            }};
            [_renderer updateProjectionBy:zoom];
        }
    }

    // Rendering
    ImGui::Render();
    ImDrawData* draw_data = ImGui::GetDrawData();

    renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(clear_color.x * clear_color.w, clear_color.y * clear_color.w, clear_color.z * clear_color.w, clear_color.w);
    id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    [renderEncoder pushDebugGroup:@"Dear ImGui rendering"];
    ImGui_ImplMetal_RenderDrawData(draw_data, commandBuffer, renderEncoder);
    [renderEncoder popDebugGroup];
    [renderEncoder endEncoding];

	// Present
    view.currentDrawable.layer.wantsExtendedDynamicRangeContent = true;
    [commandBuffer presentDrawable:view.currentDrawable];
    [commandBuffer commit];
}

-(void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size {
}

-(void)rotateWithEvent:(NSEvent *)event {
    if (!_viewportHovered) return;
    
    const float radians = event.rotation * M_PI / 180;
    const float c = std::cos(radians);
    const float s = std::sin(radians);
    
    const simd_float4x4 rotation {{
        { c, s, 0, 0 },
        {-s, c, 0, 0 },
        { 0, 0, 1, 0 },
        { 0, 0, 0, 1 }
    }};
    
    [_renderer updateProjectionBy:rotation];
}

- (void)magnifyWithEvent:(NSEvent *)event {
    if (!_viewportHovered) return;
    
    const simd_float4x4 zoom {{
        { 1, 0, 0, 0 },
        { 0, 1, 0, 0 },
        { 0, 0, 1, -float(event.magnification) * 100 * _gestureSpeed },
        { 0, 0, 0, 1 }
    }};
    
    [_renderer updateProjectionBy:zoom];
}

- (void)scrollWheel:(NSEvent *)event {
    if (!_viewportHovered) return;
    
    if (event.scrollingDeltaX == 0 && event.scrollingDeltaY == 0) {
        return;
    }
    
    const simd_float4x4 shift {{
        { 1, 0, 0,-float(event.scrollingDeltaX) * 0.2f * _gestureSpeed },
        { 0, 1, 0, float(event.scrollingDeltaY) * 0.2f * _gestureSpeed },
        { 0, 0, 1, 0 },
        { 0, 0, 0, 1 }
    }};
    
    [_renderer updateProjectionBy:shift];
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_viewportHovered) return;
    
    const float radiansX = float(event.deltaX) * M_PI / 180;
    const float cX = std::cos(radiansX);
    const float sX = std::sin(radiansX);
    const simd_float4x4 rotationX {{
        { cX, 0,-sX, 0 },
        {  0, 1,  0, 0 },
        { sX, 0, cX, 0 },
        {  0, 0,  0, 1 }
    }};
    
    const float radiansY = float(event.deltaY) * M_PI / 180;
    const float cY = std::cos(radiansY);
    const float sY = std::sin(radiansY);
    const simd_float4x4 rotationY {{
        { 1,  0,  0, 0 },
        { 0, cY, sY, 0 },
        { 0,-sY, cY, 0 },
        { 0,  0,  0, 1 }
    }};
    
    [_renderer updateProjectionBy:simd_mul(rotationX, rotationY)];
}

//-----------------------------------------------------------------------------------
// Input processing
//-----------------------------------------------------------------------------------

- (void)viewWillAppear
{
    [super viewWillAppear];
    self.view.window.delegate = self;
}

- (void)windowWillClose:(NSNotification *)notification
{
    ImGui_ImplMetal_Shutdown();
    ImGui_ImplOSX_Shutdown();
    ImGui::DestroyContext();
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) NSWindow *window;
@end

@implementation AppDelegate

-(BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return YES;
}

@end

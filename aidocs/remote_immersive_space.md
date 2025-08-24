This year, you can use the power of your Mac to render and stream immersive content directly to Vision Pro. This can be used to add immersive experiences to existing Mac apps.

For example, a 3D modeling app can directly preview your scenes on Vision Pro. Or you can build an immersive macOS app from scratch. This way you can make complex immersive experiences with high compute needs, without being constrained by the power usage of Vision Pro.

Starting a remote immersive session from a Mac app is really easy. When you open an Immersive Space in macOS, you'll be prompted to accept the connection on Vision Pro.

Do that, and you'll start seeing your Mac-rendered immersive content.

A typical Mac app is built with SwiftUI or AppKit. You use either of these frameworks to create and display Windows. The system renders your window content with Core Animation. You can adopt a variety of macOS frameworks to implement your app's functionality. And the system displays your content on your Mac display. To build a Mac-supported immersive experience, you'll use the same familiar frameworks that allow you to create immersive visionOS apps. First, you use SwiftUI with the new Remote Immersive Space scene type. You then adopt the Compositor Services framework. You use ARKit and Metal to place and render your content. And the system directly displays your immersive scene on Vision Pro.

The macOS Remote Immersive Space hosts the Compositor Layer and ARKit Session, like a native visionOS app does. They seamlessly connect to your Vision Pro display and sensors. In order to connect your ARKit Session to visionOS, there's a new Remote Device Identifier SwiftUI environment object that you pass to the session initializer.

This is how a Mac immersive app is structured.

I define a new remote immersive space, which contains my compositor content. I'll show how it uses the compositor layer in a bit. On Mac, only the progressive and full immersion styles are supported. In the interface of my Mac app, I use the new supports remote scenes environment variable to check if my Mac has this capability. I can customize my UI to show a message if remote scenes are not supported. If they are supported, and I have not opened the immersive space yet, I can launch it.

The last part of my app is my compositor content. It has my compositor layer and my ARKit session. I create and use a compositor layer the same way I did on visionOS. I access the new remote device identifier SwiftUI environment object, and pass it to the ARKit session initializer. This will connect my Mac's ARKit session to Vision Pro. Last, I start my render loop like I would on a typical Metal immersive app.

ARKit and the world tracking provider are now available on macOS.

This allows you to query the Vision Pro location in space. Just as you would in a native immersive app, you will use the device pose to update your scene and drawables before rendering.

A macOS spatial app supports any input device connected to your Mac. You can use keyboard and mouse controls. Or you can connect a gamepad, and handle its input using the Game Controller framework.

Additionally, you can use pinch events on the interactive elements of your immersive scene by using the 'onSpatialEvent' modifier on your Layer Renderer.

New this year, you can also create SwiftUI scenes from an existing AppKit or UIKit app. This is a great way of adding new immersive experiences to existing Mac apps. You can learn more about how to do this in "What's new in SwiftUI".

It's common for rendering engines to be implemented in C or C++. All the APIs I have explained have native equivalents in C. The C types for the Compositor Services framework start with the 'cp' prefix. They use similar patterns and conventions as familiar C libraries such as Core Foundation. For ARKit, the cDevice property gives you a C-compatible remote device identifier. You can pass it into your C framework, and initialize your ARKit Session with the create with device function.

Now you have all the pieces to use your Mac to power immersive content on Vision Pro.

// App structure

@main
struct MyImmersiveMacApp: App {
@State var immersionStyle: ImmersionStyle = .full

    var body: some Scene {
        WindowGroup {
            MyAppContent()
        }

        RemoteImmersiveSpace(id: "MyRemoteImmersiveSpace") {
            MyCompositorContent()
        }
        .immersionStyle(selection: $immersionStyle, in: .full, .progressive)

}
}

// App UI

struct MyAppContent: View {
@Environment(\.supportsRemoteScenes) private var supportsRemoteScenes
@Environment(\.openImmersiveSpace) private var openImmersiveSpace
@State private var spaceState: OpenImmersiveSpaceAction.Result?

    var body: some View {
        if !supportsRemoteScenes {
            Text("Remote SwiftUI scenes are not supported on this Mac.")
        } else if spaceState != nil {
            MySpaceStateView($spaceState)
        } else {
            Button("Open remote immersive space") {
                Task {
                    spaceState = await openImmersiveSpace(id: "MyRemoteImmersiveSpace")
                }
            }
        }
    }

}

// Compositor content and ARKit session

struct MyCompositorContent: CompositorContent {
@Environment(\.remoteDeviceIdentifier) private var remoteDeviceIdentifier

    var body: some CompositorContent {
        CompositorLayer(configuration: MyConfiguration()) { @MainActor layerRenderer in
            guard let remoteDeviceIdentifier else { return }
            let arSession = ARKitSession(device: remoteDeviceIdentifier)
            Renderer.startRenderLoop(layerRenderer, arSession)
        }
    }

}

[Skip Navigation](https://developer.apple.com/documentation/swiftui/remoteimmersivespace#app-main)

- [SwiftUI](https://developer.apple.com/documentation/swiftui)
- RemoteImmersiveSpace Beta

Structure

# RemoteImmersiveSpace

A scene that presents its content in an unbounded space on a remote device.

macOS 26.0+Beta

```
struct RemoteImmersiveSpace<Content, Data> where Content : ImmersiveSpaceContent, Data : Decodable, Data : Encodable, Data : Hashable
```

## [Overview](https://developer.apple.com/documentation/swiftui/remoteimmersivespace#overview)

Use a remote immersive space as a container for compositor content that your macOS app presents on a user’s chosen visionOS device. The compositor content that you declare as the remote immersive space’s content serves as a template for it:

```
@main
struct SolarSystemApp: App {
    var body: some Scene {
        RemoteImmersiveSpace {
            CompositorLayer { layerRenderer in
                // Set up and run the Metal render loop.
                let renderThread = Thread {
                    let engine = solar_engine_create(layerRenderer)
                    solar_engine_render_loop(engine)
                }
                renderThread.name = "Render Thread"
                renderThread.start()
            }
        }
    }
}

```

### [Using the environment, state, and modifiers](https://developer.apple.com/documentation/swiftui/remoteimmersivespace#Using-the-environment-state-and-modifiers)

Declare types that conform to the [`CompositorContent`](https://developer.apple.com/documentation/swiftui/compositorcontent) protocol to access the environment, declare `@State` variables, and use modifiers inside your remote immersive space.

```
struct SolarSystem: CompositorContent {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: AppModel

    var body: some CompositorContent {
        CompositorLayer { layerRenderer in
            // Set up and run the Metal render loop.
            let renderThread = Thread {
                let engine = solar_engine_create(layerRenderer)
                solar_engine_render_loop(engine)
            }
            renderThread.name = "Render Thread"
            renderThread.start()
        }
        .onChange(of: scenePhase) {
            model.remoteSpaceActive = scenePhase == .active
        }
    }
}

```

### [Identifying the remote device](https://developer.apple.com/documentation/swiftui/remoteimmersivespace#Identifying-the-remote-device)

Use the [`remoteDeviceIdentifier`](https://developer.apple.com/documentation/swiftui/environmentvalues/remotedeviceidentifier) environment value to identify the device the scene is running on. This identifier can also be used to initialize an `ARKitSession` associated with the remote device.

```
struct SolarSystem: CompositorContent {
    @Environment(\.remoteDeviceIdentifier) private var deviceID

    var body: some CompositorContent {
        CompositorLayer { layerRenderer in
            // Create an ARSession for the device
            let arSession = ARKitSession(deviceID)

            // Set up and run the Metal render loop.
            let renderThread = Thread {
                let engine = solar_engine_create(
                    layerRenderer, arSession)
                solar_engine_render_loop(engine)
            }
            renderThread.name = "Render Thread"
            renderThread.start()
        }
    }
}

```

### [Style the immersive space](https://developer.apple.com/documentation/swiftui/remoteimmersivespace#Style-the-immersive-space)

By default, immersive spaces use the [`mixed`](https://developer.apple.com/documentation/swiftui/immersionstyle/mixed) style which places virtual content in a person’s surroundings. You can select a different style for the immersive space by adding the [`immersionStyle(selection:in:)`](<https://developer.apple.com/documentation/swiftui/scene/immersionstyle(selection:in:)>) scene modifier to the scene. For example, you can completely control the visual experience using the [`full`](https://developer.apple.com/documentation/swiftui/immersionstyle/full) immersion style:

```
@main
struct SolarSystemApp: App {
    @State private var style: ImmersionStyle = .full

    var body: some Scene {
        RemoteImmersiveSpace {
            SolarSystem()
        }
        .immersionStyle(selection: $style, in: .full)
    }
}

```

You can change the immersion style after presenting the immersive space by changing the modifier’s `selection` input, although you can only use one of the values that you specify in the modifier’s second parameter.

### [Open a remote immersive space](https://developer.apple.com/documentation/swiftui/remoteimmersivespace#Open-a-remote-immersive-space)

You can programmatically open a remote immersive space by giving it an identifier. For example, you can label the solar system view from the previous example:

```
RemoteImmersiveSpace(id: "solarSystem") {
    SolarSystem()
}

```

Elsewhere in your code, you use the [`openImmersiveSpace`](https://developer.apple.com/documentation/swiftui/environmentvalues/openimmersivespace) environment value to get the instance of the [`OpenImmersiveSpaceAction`](https://developer.apple.com/documentation/swiftui/openimmersivespaceaction) structure for a given [`Environment`](https://developer.apple.com/documentation/swiftui/environment). You call the instance directly — for example, from a button’s closure, like in the following code — using the identifier:

```
struct NewSolarSystemImmersiveSpaceButton: View {
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.supportsRemoteScenes) private var supportsRemoteScenes

    var body: some View {
        Button("Present Solar System") {
            Task {
                await openImmersiveSpace(id: "solarSystem")
            }
        }
        .disabled(!supportsRemoteScenes)
        .help(!supportsRemoteScenes
            ? "Presenting remote scenes is not supported on this device."
            : "")
    }
}

```

Mark the call to the action with `await` because it executes asynchronously. When your app opens a remote immersive space, the system may ask the user for a preferred device with which to display the content. Upon selection, the system on the remote device hides all other visible apps. The system allows only one immersive space to be open at a time. Be sure to close the open immersive space before opening another one.

### [Dismiss a remote immersive space](https://developer.apple.com/documentation/swiftui/remoteimmersivespace#Dismiss-a-remote-immersive-space)

You can dismiss an immersive space by calling the [`dismissImmersiveSpace`](https://developer.apple.com/documentation/swiftui/environmentvalues/dismissimmersivespace) action from the environment. For example, you can define a button that dismisses an immersive space:

```
struct DismissImmersiveSpaceButton: View {
    @Environment(\.dismissImmersiveSpace)
    private var dismissImmersiveSpace

    var body: some View {
        Button("Close Solar System") {
            Task {
                await dismissImmersiveSpace()
            }
        }
    }
}

```

The dismiss action runs asynchronously, like the open action. You don’t need to specify an identifier when dismissing an immersive space because there can only be one immersive space open at a time.

### [Present an immersive space at launch](https://developer.apple.com/documentation/swiftui/remoteimmersivespace#Present-an-immersive-space-at-launch)

When an app launches, it opens an instance of the first scene that’s listed in the app’s body. When opening an immersive space at launch, the system may still ask the user for a preferred device with which to display the content.

## [Topics](https://developer.apple.com/documentation/swiftui/remoteimmersivespace#topics)

### [Initializers](https://developer.apple.com/documentation/swiftui/remoteimmersivespace#Initializers)

[`init<C>(content: () -> C)`](<https://developer.apple.com/documentation/swiftui/remoteimmersivespace/init(content:)>)

Creates a remote immersive space.

[`init<C>(for: Data.Type, content: (Binding<Data?>) -> C)`](<https://developer.apple.com/documentation/swiftui/remoteimmersivespace/init(for:content:)>)

Creates the remote immersive space for a specified type of presented data.

[`init<C>(for: Data.Type, content: (Binding<Data>) -> C, defaultValue: () -> Data)`](<https://developer.apple.com/documentation/swiftui/remoteimmersivespace/init(for:content:defaultvalue:)>)

Creates the remote immersive space for a specified type of presented data, and a default value, if the data is not set.

[`init<C>(id: String, content: () -> C)`](<https://developer.apple.com/documentation/swiftui/remoteimmersivespace/init(id:content:)>)

Creates the remote immersive space associated with the specified identifier.

[`init<C>(id: String, for: Data.Type, content: (Binding<Data?>) -> C)`](<https://developer.apple.com/documentation/swiftui/remoteimmersivespace/init(id:for:content:)>)

Creates the remote immersive space associated with an identifier for a specified type of presented data.

[`init<C>(id: String, for: Data.Type, content: (Binding<Data>) -> C, defaultValue: () -> Data)`](<https://developer.apple.com/documentation/swiftui/remoteimmersivespace/init(id:for:content:defaultvalue:)>)

Creates the remote immersive space associated with an identifier for a specified type of presented data, and a default value, if the data is not set.

## [Relationships](https://developer.apple.com/documentation/swiftui/remoteimmersivespace#relationships)

### [Conforms To](https://developer.apple.com/documentation/swiftui/remoteimmersivespace#conforms-to)

- [`Scene`](https://developer.apple.com/documentation/swiftui/scene)

## [See Also](https://developer.apple.com/documentation/swiftui/remoteimmersivespace#see-also)

### [Handling remote immersive spaces](https://developer.apple.com/documentation/swiftui/remoteimmersivespace#Handling-remote-immersive-spaces)

[`struct RemoteDeviceIdentifier`](https://developer.apple.com/documentation/swiftui/remotedeviceidentifier)

An opaque type that identifies a remote device displaying scene content in a [`RemoteImmersiveSpace`](https://developer.apple.com/documentation/swiftui/remoteimmersivespace).

Beta

Beta Software

This documentation contains preliminary information about an API or technology in development. This information is subject to change, and software implemented according to this documentation should be tested with final operating system software.

[Learn more about using Apple's beta software](https://developer.apple.com/support/beta-software/)

Current page is RemoteImmersiveSpace

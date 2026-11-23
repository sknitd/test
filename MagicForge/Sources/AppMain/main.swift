import MFApp

// Top-level code runs on the main thread; `App.main()` is main-actor isolated.
MainActor.assumeIsolated {
    MagicForgeApp.main()
}

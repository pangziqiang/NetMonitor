import Testing
import Foundation
@testable import NetMonitorCore

// MARK: - Visibility Helper Tests

@Test func visibilityHelperHasMenuBarItem() {
    // All menu items off
    let v1 = VisibilityHelper(
        showDockIcon: false, menuShowSpeed: false, menuShowDailyTraffic: false,
        menuShowCPU: false, menuShowGPU: false, menuShowMemory: false,
        showFloatingWindow: false, floatShowSpeed: false, floatShowTraffic: false,
        floatShowCPU: false, floatShowGPU: false, floatShowMemory: false
    )
    #expect(v1.hasMenuBarItem == false)

    // Speed on
    let v2 = VisibilityHelper(
        showDockIcon: false, menuShowSpeed: true, menuShowDailyTraffic: false,
        menuShowCPU: false, menuShowGPU: false, menuShowMemory: false,
        showFloatingWindow: false, floatShowSpeed: false, floatShowTraffic: false,
        floatShowCPU: false, floatShowGPU: false, floatShowMemory: false
    )
    #expect(v2.hasMenuBarItem == true)
}

@Test func visibilityHelperHasFloatingWindowContent() {
    // All floating content off
    let v1 = VisibilityHelper(
        showDockIcon: false, menuShowSpeed: false, menuShowDailyTraffic: false,
        menuShowCPU: false, menuShowGPU: false, menuShowMemory: false,
        showFloatingWindow: true, floatShowSpeed: false, floatShowTraffic: false,
        floatShowCPU: false, floatShowGPU: false, floatShowMemory: false
    )
    #expect(v1.hasFloatingWindowContent == false)

    // Speed on
    let v2 = VisibilityHelper(
        showDockIcon: false, menuShowSpeed: false, menuShowDailyTraffic: false,
        menuShowCPU: false, menuShowGPU: false, menuShowMemory: false,
        showFloatingWindow: true, floatShowSpeed: true, floatShowTraffic: false,
        floatShowCPU: false, floatShowGPU: false, floatShowMemory: false
    )
    #expect(v2.hasFloatingWindowContent == true)
}

@Test func visibilityHelperIsFloatingWindowVisible() {
    // Main switch on, no content
    let v1 = VisibilityHelper(
        showDockIcon: false, menuShowSpeed: false, menuShowDailyTraffic: false,
        menuShowCPU: false, menuShowGPU: false, menuShowMemory: false,
        showFloatingWindow: true, floatShowSpeed: false, floatShowTraffic: false,
        floatShowCPU: false, floatShowGPU: false, floatShowMemory: false
    )
    #expect(v1.isFloatingWindowVisible == false)

    // Main switch on, has content
    let v2 = VisibilityHelper(
        showDockIcon: false, menuShowSpeed: false, menuShowDailyTraffic: false,
        menuShowCPU: false, menuShowGPU: false, menuShowMemory: false,
        showFloatingWindow: true, floatShowSpeed: true, floatShowTraffic: false,
        floatShowCPU: false, floatShowGPU: false, floatShowMemory: false
    )
    #expect(v2.isFloatingWindowVisible == true)

    // Main switch off, has content
    let v3 = VisibilityHelper(
        showDockIcon: false, menuShowSpeed: false, menuShowDailyTraffic: false,
        menuShowCPU: false, menuShowGPU: false, menuShowMemory: false,
        showFloatingWindow: false, floatShowSpeed: true, floatShowTraffic: false,
        floatShowCPU: false, floatShowGPU: false, floatShowMemory: false
    )
    #expect(v3.isFloatingWindowVisible == false)
}

@Test func visibilityHelperHasAnyVisibleElement() {
    // Nothing visible
    let v1 = VisibilityHelper(
        showDockIcon: false, menuShowSpeed: false, menuShowDailyTraffic: false,
        menuShowCPU: false, menuShowGPU: false, menuShowMemory: false,
        showFloatingWindow: false, floatShowSpeed: false, floatShowTraffic: false,
        floatShowCPU: false, floatShowGPU: false, floatShowMemory: false
    )
    #expect(v1.hasAnyVisibleElement == false)

    // Only dock icon
    let v2 = VisibilityHelper(
        showDockIcon: true, menuShowSpeed: false, menuShowDailyTraffic: false,
        menuShowCPU: false, menuShowGPU: false, menuShowMemory: false,
        showFloatingWindow: false, floatShowSpeed: false, floatShowTraffic: false,
        floatShowCPU: false, floatShowGPU: false, floatShowMemory: false
    )
    #expect(v2.hasAnyVisibleElement == true)

    // Only menu bar
    let v3 = VisibilityHelper(
        showDockIcon: false, menuShowSpeed: true, menuShowDailyTraffic: false,
        menuShowCPU: false, menuShowGPU: false, menuShowMemory: false,
        showFloatingWindow: false, floatShowSpeed: false, floatShowTraffic: false,
        floatShowCPU: false, floatShowGPU: false, floatShowMemory: false
    )
    #expect(v3.hasAnyVisibleElement == true)

    // Floating window main on but no content
    let v4 = VisibilityHelper(
        showDockIcon: false, menuShowSpeed: false, menuShowDailyTraffic: false,
        menuShowCPU: false, menuShowGPU: false, menuShowMemory: false,
        showFloatingWindow: true, floatShowSpeed: false, floatShowTraffic: false,
        floatShowCPU: false, floatShowGPU: false, floatShowMemory: false
    )
    #expect(v4.hasAnyVisibleElement == false)

    // Floating window with content
    let v5 = VisibilityHelper(
        showDockIcon: false, menuShowSpeed: false, menuShowDailyTraffic: false,
        menuShowCPU: false, menuShowGPU: false, menuShowMemory: false,
        showFloatingWindow: true, floatShowSpeed: true, floatShowTraffic: false,
        floatShowCPU: false, floatShowGPU: false, floatShowMemory: false
    )
    #expect(v5.hasAnyVisibleElement == true)
}

@Test func visibilityHelperCanDisableDock() {
    // Only dock visible - cannot disable
    let v1 = VisibilityHelper(
        showDockIcon: true, menuShowSpeed: false, menuShowDailyTraffic: false,
        menuShowCPU: false, menuShowGPU: false, menuShowMemory: false,
        showFloatingWindow: false, floatShowSpeed: false, floatShowTraffic: false,
        floatShowCPU: false, floatShowGPU: false, floatShowMemory: false
    )
    #expect(v1.canDisable("dock") == false)

    // Dock + menu bar - can disable dock
    let v2 = VisibilityHelper(
        showDockIcon: true, menuShowSpeed: true, menuShowDailyTraffic: false,
        menuShowCPU: false, menuShowGPU: false, menuShowMemory: false,
        showFloatingWindow: false, floatShowSpeed: false, floatShowTraffic: false,
        floatShowCPU: false, floatShowGPU: false, floatShowMemory: false
    )
    #expect(v2.canDisable("dock") == true)

    // Dock + floating with content - can disable dock
    let v3 = VisibilityHelper(
        showDockIcon: true, menuShowSpeed: false, menuShowDailyTraffic: false,
        menuShowCPU: false, menuShowGPU: false, menuShowMemory: false,
        showFloatingWindow: true, floatShowSpeed: true, floatShowTraffic: false,
        floatShowCPU: false, floatShowGPU: false, floatShowMemory: false
    )
    #expect(v3.canDisable("dock") == true)

    // Dock + floating without content - cannot disable dock
    let v4 = VisibilityHelper(
        showDockIcon: true, menuShowSpeed: false, menuShowDailyTraffic: false,
        menuShowCPU: false, menuShowGPU: false, menuShowMemory: false,
        showFloatingWindow: true, floatShowSpeed: false, floatShowTraffic: false,
        floatShowCPU: false, floatShowGPU: false, floatShowMemory: false
    )
    #expect(v4.canDisable("dock") == false)
}

@Test func visibilityHelperCanDisableMenuBar() {
    // Only one menu item - cannot disable
    let v1 = VisibilityHelper(
        showDockIcon: false, menuShowSpeed: true, menuShowDailyTraffic: false,
        menuShowCPU: false, menuShowGPU: false, menuShowMemory: false,
        showFloatingWindow: false, floatShowSpeed: false, floatShowTraffic: false,
        floatShowCPU: false, floatShowGPU: false, floatShowMemory: false
    )
    #expect(v1.canDisable("menuBar") == false)

    // Two menu items - can disable one
    let v2 = VisibilityHelper(
        showDockIcon: false, menuShowSpeed: true, menuShowDailyTraffic: true,
        menuShowCPU: false, menuShowGPU: false, menuShowMemory: false,
        showFloatingWindow: false, floatShowSpeed: false, floatShowTraffic: false,
        floatShowCPU: false, floatShowGPU: false, floatShowMemory: false
    )
    #expect(v2.canDisable("menuBar") == true)

    // One menu item + dock - can disable menu
    let v3 = VisibilityHelper(
        showDockIcon: true, menuShowSpeed: true, menuShowDailyTraffic: false,
        menuShowCPU: false, menuShowGPU: false, menuShowMemory: false,
        showFloatingWindow: false, floatShowSpeed: false, floatShowTraffic: false,
        floatShowCPU: false, floatShowGPU: false, floatShowMemory: false
    )
    #expect(v3.canDisable("menuBar") == true)
}

@Test func visibilityHelperCanDisableFloating() {
    // Only floating with content - cannot disable
    let v1 = VisibilityHelper(
        showDockIcon: false, menuShowSpeed: false, menuShowDailyTraffic: false,
        menuShowCPU: false, menuShowGPU: false, menuShowMemory: false,
        showFloatingWindow: true, floatShowSpeed: true, floatShowTraffic: false,
        floatShowCPU: false, floatShowGPU: false, floatShowMemory: false
    )
    #expect(v1.canDisable("floating") == false)

    // Floating + dock - can disable floating
    let v2 = VisibilityHelper(
        showDockIcon: true, menuShowSpeed: false, menuShowDailyTraffic: false,
        menuShowCPU: false, menuShowGPU: false, menuShowMemory: false,
        showFloatingWindow: true, floatShowSpeed: true, floatShowTraffic: false,
        floatShowCPU: false, floatShowGPU: false, floatShowMemory: false
    )
    #expect(v2.canDisable("floating") == true)
}

@Test func visibilityHelperCanDisableFloatingContent() {
    // Only one floating content - cannot disable
    let v1 = VisibilityHelper(
        showDockIcon: false, menuShowSpeed: false, menuShowDailyTraffic: false,
        menuShowCPU: false, menuShowGPU: false, menuShowMemory: false,
        showFloatingWindow: true, floatShowSpeed: true, floatShowTraffic: false,
        floatShowCPU: false, floatShowGPU: false, floatShowMemory: false
    )
    #expect(v1.canDisable("floatingContent") == false)

    // Two floating content - can disable one
    let v2 = VisibilityHelper(
        showDockIcon: false, menuShowSpeed: false, menuShowDailyTraffic: false,
        menuShowCPU: false, menuShowGPU: false, menuShowMemory: false,
        showFloatingWindow: true, floatShowSpeed: true, floatShowTraffic: true,
        floatShowCPU: false, floatShowGPU: false, floatShowMemory: false
    )
    #expect(v2.canDisable("floatingContent") == true)

    // One floating content + dock - can disable floating content
    let v3 = VisibilityHelper(
        showDockIcon: true, menuShowSpeed: false, menuShowDailyTraffic: false,
        menuShowCPU: false, menuShowGPU: false, menuShowMemory: false,
        showFloatingWindow: true, floatShowSpeed: true, floatShowTraffic: false,
        floatShowCPU: false, floatShowGPU: false, floatShowMemory: false
    )
    #expect(v3.canDisable("floatingContent") == true)
}

@Test func visibilityHelperMenuBarVisibleCount() {
    let v = VisibilityHelper(
        showDockIcon: false, menuShowSpeed: true, menuShowDailyTraffic: true,
        menuShowCPU: true, menuShowGPU: false, menuShowMemory: false,
        showFloatingWindow: false, floatShowSpeed: false, floatShowTraffic: false,
        floatShowCPU: false, floatShowGPU: false, floatShowMemory: false
    )
    #expect(v.menuBarVisibleCount == 3)
}

@Test func visibilityHelperFloatingContentCount() {
    let v = VisibilityHelper(
        showDockIcon: false, menuShowSpeed: false, menuShowDailyTraffic: false,
        menuShowCPU: false, menuShowGPU: false, menuShowMemory: false,
        showFloatingWindow: true, floatShowSpeed: true, floatShowTraffic: true,
        floatShowCPU: true, floatShowGPU: false, floatShowMemory: false
    )
    #expect(v.floatingContentCount == 3)
}

@Test func visibilityHelperEnsureVisibility() {
    // Has visible element - no action needed
    let v1 = VisibilityHelper(
        showDockIcon: true, menuShowSpeed: false, menuShowDailyTraffic: false,
        menuShowCPU: false, menuShowGPU: false, menuShowMemory: false,
        showFloatingWindow: false, floatShowSpeed: false, floatShowTraffic: false,
        floatShowCPU: false, floatShowGPU: false, floatShowMemory: false
    )
    #expect(v1.needsVisibilityRestore() == false)

    // No visible element - action needed
    let v2 = VisibilityHelper(
        showDockIcon: false, menuShowSpeed: false, menuShowDailyTraffic: false,
        menuShowCPU: false, menuShowGPU: false, menuShowMemory: false,
        showFloatingWindow: false, floatShowSpeed: false, floatShowTraffic: false,
        floatShowCPU: false, floatShowGPU: false, floatShowMemory: false
    )
    #expect(v2.needsVisibilityRestore() == true)
}

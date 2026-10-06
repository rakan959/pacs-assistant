#Requires AutoHotkey v2.0
#Include ../WindowPlacement.ahk
#Include TestRunner.ahk

class WindowPlacementTest {
    static tests := [
        "TestPlacementRoundTripsThroughTheDataFolder",
        "TestMissingOrDamagedPlacementLoadsAsNone",
        "TestPlacementOnAMonitorIsReachable",
        "TestPlacementOffEveryMonitorIsNotReachable",
        "TestTinyPlacementIsNotReachable"
    ]

    Setup() {
        try FileDelete(WindowPlacement.Path())
    }

    Teardown() {
        try FileDelete(WindowPlacement.Path())
    }

    TestPlacementRoundTripsThroughTheDataFolder() {
        WindowPlacement.SaveRect(-1500, 40, 900, 700)
        WindowPlacement.SaveMaximized(true)
        saved := WindowPlacement.Load()
        Assert.Equal(-1500, saved.x)
        Assert.Equal(40, saved.y)
        Assert.Equal(900, saved.w)
        Assert.Equal(700, saved.h)
        Assert.True(saved.maximized)
        WindowPlacement.SaveMaximized(false)
        Assert.False(WindowPlacement.Load().maximized)
    }

    TestMissingOrDamagedPlacementLoadsAsNone() {
        Assert.Equal(0, WindowPlacement.Load())
        ; Maximizing alone, before any move, records no position.
        WindowPlacement.SaveMaximized(true)
        Assert.Equal(0, WindowPlacement.Load())
        WindowPlacement.SaveRect(10, 10, 800, 600)
        IniWrite("wide", WindowPlacement.Path(), "MainWindow", "Width")
        Assert.Equal(0, WindowPlacement.Load())
    }

    TestPlacementOnAMonitorIsReachable() {
        areas := [{left: 0, top: 0, right: 1600, bottom: 1160}, {left: 1600, top: 0, right: 3240, bottom: 2008}]
        Assert.True(WindowPlacement.IsReachable({x: 100, y: 100, w: 850, h: 680}, areas))
        Assert.True(WindowPlacement.IsReachable({x: 2000, y: 600, w: 850, h: 680}, areas))
        ; Partly off the side of a monitor is fine while the title bar can be grabbed.
        Assert.True(WindowPlacement.IsReachable({x: 1400, y: 10, w: 850, h: 680}, areas))
    }

    ; A monitor that was removed or rearranged leaves the saved place off screen;
    ; the window then opens centred rather than where nobody can see it.
    TestPlacementOffEveryMonitorIsNotReachable() {
        areas := [{left: 0, top: 0, right: 1600, bottom: 1160}]
        Assert.False(WindowPlacement.IsReachable({x: 2000, y: 100, w: 850, h: 680}, areas))
        Assert.False(WindowPlacement.IsReachable({x: 100, y: -500, w: 850, h: 680}, areas))
        Assert.False(WindowPlacement.IsReachable({x: 100, y: 1150, w: 850, h: 680}, areas))
    }

    TestTinyPlacementIsNotReachable() {
        areas := [{left: 0, top: 0, right: 1600, bottom: 1160}]
        Assert.False(WindowPlacement.IsReachable({x: 100, y: 100, w: 120, h: 680}, areas))
        Assert.False(WindowPlacement.IsReachable(0, areas))
    }
}

#Requires AutoHotkey v2.0

; Stands in for AppControl's window driver with a fixed list of top-level windows,
; each {hwnd, title, exe, pid, active?}. An unknown HWND throws TargetError, as the
; native Win* functions do for a window that has gone.
class FakeWindowList {
    __New(windows, failTitles := false) {
        this.windows := windows.Clone()
        this.failTitles := failTitles
    }

    ListWindowsByExecutable(executable) {
        handles := []
        for window in this.windows {
            if (window.exe = executable)
                handles.Push(window.hwnd)
        }
        return handles
    }

    Window(hwnd) {
        for window in this.windows {
            if (window.hwnd = hwnd)
                return window
        }
        throw TargetError("unknown fake window")
    }

    GetTitle(hwnd) {
        if this.failTitles
            throw Error("simulated title failure")
        return this.Window(hwnd).title
    }

    GetProcessName(hwnd) {
        return this.Window(hwnd).exe
    }

    GetProcessId(hwnd) {
        return this.Window(hwnd).pid
    }

    IsActive(target) {
        window := this.Window(Integer(SubStr(target, StrLen("ahk_id ") + 1)))
        return HasProp(window, "active") && window.active
    }
}

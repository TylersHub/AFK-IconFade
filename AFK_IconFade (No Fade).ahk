#Requires AutoHotkey v2
#SingleInstance Force
#Warn

; ===================== Settings =====================
idleThreshold := 10000       ; ms of no input before hiding icons (10s)

; ===================== State =====================
hDesk := 0
hDefView := 0    ; SHELLDLL_DefView (kept visible)
hList := 0       ; SysListView32 (the actual icons control we will hide/show)
iconsHidden := false

AcquireHandles()
SetTimer(() => EnsureHandles(), 1000)   ; re-acquire if Explorer restarts
SetTimer(MainLoopHide, 200)             ; light polling is enough

; Tray
A_TrayMenu.Delete()
A_TrayMenu.Add("Exit", (*) => ExitApp())
OnExit(Cleanup)

; ===================== Main (HIDE mode) =====================
MainLoopHide() {
    global idleThreshold, hList, hDefView, iconsHidden

    if !hDefView  ; no desktop yet (Explorer restarting)
        return

    ; Prefer controlling the ListView; if missing, fall back to DefView
    targetCtrl := hList ? hList : hDefView

    if (A_TimeIdlePhysical >= idleThreshold) {
        if !iconsHidden {
            try WinHide("ahk_id " targetCtrl)
            iconsHidden := true
        }
    } else {
        if iconsHidden {
            try WinShow("ahk_id " targetCtrl)
            ; No forced desktop redraw here, to avoid interrupting WE animation.
            iconsHidden := false
        }
    }
}

; ===================== Handles =====================
EnsureHandles() {
    global hDesk, hDefView, hList
    if !hDefView || !hList {    ; we can run fine without hList, but attempt to reacquire it
        AcquireHandles()
    }
}

AcquireHandles() {
    global hDesk, hDefView, hList
    hDesk := 0, hDefView := 0, hList := 0

    ; 1) Try Progman -> SHELLDLL_DefView (keep DefView visible)
    if hwndProg := WinExist("ahk_class Progman") {
        if hwndDef := FindChild(hwndProg, "SHELLDLL_DefView") {
            hDesk := hwndProg, hDefView := hwndDef
            hList := FindChild(hwndDef, "SysListView32")  ; icons control
            if !hList {
                ; some builds expose the listview directly with the 1 suffix
                try hList := ControlGetHwnd("SysListView321", "ahk_id " hwndProg)
            }
            return
        }
    }

    ; 2) Otherwise: search all WorkerW hosts for DefView, then its ListView
    for hwndWorker in WinGetList("ahk_class WorkerW") {
        if hwndDef := FindChild(hwndWorker, "SHELLDLL_DefView") {
            hDesk := hwndWorker, hDefView := hwndDef
            hList := FindChild(hwndDef, "SysListView32")
            if !hList {
                try hList := ControlGetHwnd("SysListView321", "ahk_id " hwndWorker)
            }
            return
        }
    }
    ; Not found yet; EnsureHandles() will retry
}

FindChild(parentHwnd, className, title := "") {
    return DllCall("user32\FindWindowEx", "ptr", parentHwnd, "ptr", 0, "str", className, "str", title, "ptr")
}

; ===================== Cleanup =====================
Cleanup(*) {
    global hList, hDefView, iconsHidden
    try {
        if iconsHidden {
            ; Make sure whatever we hid is shown again
            if hList
                WinShow("ahk_id " hList)
            else if hDefView
                WinShow("ahk_id " hDefView)
        }
    }
}

#Requires AutoHotkey v2
#SingleInstance Force
#Warn

; ===================== Settings =====================
idleThreshold := 10000      ; ms of no input before fading (10s)
fadeStep := 17         ; 1..255 (higher = faster)
frameDelay := 20         ; ms between frames
minAlpha := 1          ; alpha when hidden
maxAlpha := 255        ; alpha when shown

; ===================== State =====================
hDesk := 0
hDefView := 0          ; keep visible
hList := 0             ; SysListView32 (fade target)
currentAlpha := maxAlpha
targetAlpha := maxAlpha
wasHidden := false

AcquireHandles()
SetTimer(() => EnsureHandles(), 1000)
SetTimer(MainLoopFade, frameDelay)

A_TrayMenu.Delete()
A_TrayMenu.Add("Exit", (*) => ExitApp())
OnExit(Cleanup)

MainLoopFade() {
    global idleThreshold, targetAlpha, currentAlpha, minAlpha, maxAlpha
        , fadeStep, hList, wasHidden

    if !hList
        return

    targetAlpha := (A_TimeIdlePhysical >= idleThreshold) ? minAlpha : maxAlpha

    if (targetAlpha = minAlpha) {
        ; fade OUT toward min
        if (currentAlpha > minAlpha) {
            currentAlpha := Max(currentAlpha - fadeStep, minAlpha)
            try WinSetTransparent(currentAlpha, hList)
        }
        if (currentAlpha = minAlpha)
            wasHidden := true
        return
    }

    ; target is fully visible → fade IN, but handle the last step specially
    if (currentAlpha < maxAlpha) {
        ; approach 254 first to avoid composite glitch at 255
        next := Min(currentAlpha + fadeStep, maxAlpha)
        if (next >= 254 && currentAlpha < 254) {
            next := 254
        }
        currentAlpha := next
        try WinSetTransparent(currentAlpha, hList)

        ; if we reached 254 or more, clear layered flag & finalize
        if (currentAlpha >= 254) {
            RemoveLayered(hList)                 ; <- key fix
            currentAlpha := maxAlpha             ; logical state
            if (wasHidden) {
                wasHidden := false
                LightNudgeCompositor()           ; gentle one-shot nudge
            }
        }
    }
}

EnsureHandles() {
    global hDesk, hDefView, hList
    if !hDefView || !hList
        AcquireHandles()
}

AcquireHandles() {
    global hDesk, hDefView, hList
    hDesk := 0, hDefView := 0, hList := 0

    ; Prefer Progman -> SHELLDLL_DefView -> SysListView32
    if hwndProg := WinExist("ahk_class Progman") {
        if hwndDef := FindChild(hwndProg, "SHELLDLL_DefView") {
            hDesk := hwndProg, hDefView := hwndDef
            hList := FindChild(hwndDef, "SysListView32")
            if !hList {
                ; some builds expose the list directly
                try hList := ControlGetHwnd("SysListView321", "ahk_id " hwndProg)
            }
            return
        }
    }

    ; Else search WorkerW hosts
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
}

FindChild(parentHwnd, className, title := "") {
    return DllCall("user32\FindWindowEx", "ptr", parentHwnd, "ptr", 0, "str", className, "str", title, "ptr")
}

; ===================== Layered window fix =====================
RemoveLayered(hwnd) {
    static GWL_EXSTYLE := -20, WS_EX_LAYERED := 0x00080000
    ex := DllCall("user32\GetWindowLongPtr", "ptr", hwnd, "int", GWL_EXSTYLE, "ptr")
    if (ex & WS_EX_LAYERED) {
        ex2 := ex & ~WS_EX_LAYERED
        DllCall("user32\SetWindowLongPtr", "ptr", hwnd, "int", GWL_EXSTYLE, "ptr", ex2, "ptr")
        ; make sure composition updates, but don't disturb Z-order/pos
        SWP_NOSIZE := 0x0001, SWP_NOMOVE := 0x0002, SWP_NOZORDER := 0x0004, SWP_NOACTIVATE := 0x0010, SWP_FRAMECHANGED :=
            0x0020
        flags := SWP_NOSIZE | SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED
        DllCall("user32\SetWindowPos", "ptr", hwnd, "ptr", 0, "int", 0, "int", 0, "int", 0, "int", 0, "uint", flags)
    }
}

LightNudgeCompositor() {
    ; tiny, low-risk sync — avoids pausing WE
    try DllCall("dwmapi\DwmFlush")
}

Cleanup(*) {
    global hList
    try {
        if hList {
            ; restore fully and clear layered flag on exit
            WinSetTransparent(255, hList)
            RemoveLayered(hList)
        }
    }
}

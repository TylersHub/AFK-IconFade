#Requires AutoHotkey v2
#SingleInstance Force
#Warn
; --- Settings ---
idleThreshold := 10000       ; ms of no input before fading out (10s)
fadeStep := 17          ; transparency step per frame (1..255, higher = faster)
frameDelay := 20          ; ms between frames (lower = smoother, higher = lighter CPU)
minAlpha := 1           ; lowest transparency when hidden (1..255)
maxAlpha := 255         ; fully visible

; --- State ---
currentAlpha := maxAlpha
targetAlpha := maxAlpha
hdesk := 0, hicon := 0

; Try to get the desktop icons control at start, and periodically if it ever fails
AcquireHandles()
SetTimer(() => EnsureHandles(), 1000)

; Main loop: check idle -> set target -> animate toward target
SetTimer(MainLoop, frameDelay)

; Tray menu
A_TrayMenu.Delete()  ; start clean
A_TrayMenu.Add("Settings", (*) => MsgBox("Idle: " idleThreshold " ms`nStep: " fadeStep "`nFrame: " frameDelay " ms"))
A_TrayMenu.Add("Exit", (*) => ExitApp())

OnExit((*) => (hicon ? WinSetTransparent(maxAlpha, hicon) : 0))

MainLoop() {
    global idleThreshold, targetAlpha, currentAlpha, minAlpha, maxAlpha, fadeStep, frameDelay, hicon

    ; Decide target based on physical idle (mouse+keyboard)
    targetAlpha := (A_TimeIdlePhysical >= idleThreshold) ? minAlpha : maxAlpha

    ; If we don't have the icons handle, wait for reacquire tick
    if !hicon
        return

    ; Move one step toward the target
    if (currentAlpha < targetAlpha) {
        currentAlpha := Min(currentAlpha + fadeStep, targetAlpha)
        try WinSetTransparent(currentAlpha, hicon)
    } else if (currentAlpha > targetAlpha) {
        currentAlpha := Max(currentAlpha - fadeStep, targetAlpha)
        try WinSetTransparent(currentAlpha, hicon)
    }
}

EnsureHandles() {
    global hdesk, hicon
    if !hicon {
        AcquireHandles()
    }
}

AcquireHandles() {
    global hdesk, hicon
    hdesk := 0, hicon := 0

    ; 1) Try Progman direct
    if hwndProg := WinExist("ahk_class Progman") {
        try {
            if hwndIcons := ControlGetHwnd("SysListView321", "ahk_id " hwndProg) {
                hdesk := hwndProg, hicon := hwndIcons
                return
            }
        }
        ; 2) Progman -> SHELLDLL_DefView -> SysListView32
        if hwndDef := FindChild(hwndProg, "SHELLDLL_DefView") {
            if hwndIcons := FindChild(hwndDef, "SysListView32") {
                hdesk := hwndProg, hicon := hwndIcons
                return
            }
        }
    }

    ; 3) Iterate WorkerW hosts
    workerList := WinGetList("ahk_class WorkerW")
    if IsObject(workerList) && workerList.Length {
        for hwndWorker in workerList {
            if hwndDef := FindChild(hwndWorker, "SHELLDLL_DefView") {
                if hwndIcons := FindChild(hwndDef, "SysListView32") {
                    hdesk := hwndWorker, hicon := hwndIcons
                    return
                }
            }
            try {
                if hwndIcons := ControlGetHwnd("SysListView321", "ahk_id " hwndWorker) {
                    hdesk := hwndWorker, hicon := hwndIcons
                    return
                }
            }
        }
    }

    ; If still not found, leave hicon=0. MainLoop will wait; EnsureHandles retries every second.
}

FindChild(parentHwnd, className, title := "") {
    return DllCall("user32\FindWindowEx", "ptr", parentHwnd, "ptr", 0, "str", className, "str", title, "ptr")
}

#Requires AutoHotkey v2.0
#SingleInstance Force
; Inspired by SpaceGT/Anti-AFK. No elevation, BlockInput, clicks, or Space presses.
; Roblox briefly receives focus for F15, then its previous window state is restored.

if A_Args.Length && A_Args[1] = "--check" {
    FileAppend("Syntax OK`n", "*")
    ExitApp(0)
}

InstallKeybdHook()
InstallMouseHook()

StateFile := A_Args.Length ? A_Args[1] : "C:\matcha\workspace\muscle-legends-anti-afk.ini"
StatusFile := RegExReplace(StateFile, "\.ini$", "-helper.ini")
LogFile := RegExReplace(StateFile, "\.ini$", "-helper.jsonl")
NextPulse := A_TickCount
Busy := false
Held := false
Successes := 0
Ack := 0
LastStatus := "Starting"
OnExit(Cleanup)
A_TrayMenu.Add("Stop background anti-AFK", (*) => ExitApp())
Persistent()
SetTimer(Check, 1000)
Check()

Report(status) {
    global StatusFile, Ack, Successes, LastStatus
    LastStatus := status
    try {
        file := FileOpen(StatusFile, "w", "UTF-8-RAW")
        file.Write("[helper]`nack=" Ack "`ncount=" Successes "`nstatus=" status "`n")
        file.Close()
    }
    A_IconTip := "Muscle Legends anti-AFK: " status
}

AnyHeldInput() {
    Loop 254 {
        if GetKeyState(Format("vk{:02X}", A_Index), "P")
            return true
    }
    return false
}

Check() {
    global StateFile, Ack, NextPulse, Busy, Successes
    if Busy
        return
    try {
        enabled := IniRead(StateFile, "session", "enabled", "0")
        Ack := IniRead(StateFile, "session", "serial", "0")
        if enabled != "1" || DateDiff(A_Now, FileGetTime(StateFile, "M"), "Seconds") > 15 {
            Report("Paused: hub disabled or heartbeat stale")
            return
        }
        windows := WinGetList("Roblox ahk_exe RobloxPlayerBeta.exe")
        if windows.Length != 1 {
            Report("Paused: expected exactly one Roblox window")
            return
        }
        target := windows[1]
        if A_TickCount < NextPulse {
            Report("Helper armed; pulse count=" Successes)
            return
        }
        if A_TimeIdlePhysical < 1500 || AnyHeldInput() {
            Report("Waiting for a pause in physical input")
            return
        }
        Busy := true
        try Pulse(target)
        finally Busy := false
    } catch Error as err {
        Report("Paused: " StrReplace(StrReplace(err.Message, "`n", " "), "`r", " "))
        NextPulse := A_TickCount + 10000
    }
}

Pulse(target) {
    global Held, Successes, NextPulse, LogFile, Ack
    selector := "ahk_id " target
    previous := WinExist("A")
    if !previous || !WinExist(selector)
        return
    alreadyFocused := WinActive(selector)
    idleBefore := A_TimeIdlePhysical
    priorMinMax := WinGetMinMax(selector)
    priorAlpha := WinGetTransparent(selector)
    success := false
    try {
        if !alreadyFocused {
            WinSetTransparent(0, selector)
            if priorMinMax = -1
                WinRestore(selector)
            WinActivate(selector)
            if !WinWaitActive(selector, , 0.5)
                throw Error("Roblox focus was not confirmed")
        }
        if AnyHeldInput()
            throw Error("Physical input resumed")
        Held := true
        try {
            SendEvent("{vk7E down}")
            Sleep(50)
        } finally {
            SendEvent("{vk7E up}")
            Held := false
        }
        success := true
    } finally {
        if Held {
            try SendEvent("{vk7E up}")
            Held := false
        }
        if !alreadyFocused && WinExist(selector) {
            try WinSetTransparent(priorAlpha = "" ? "Off" : priorAlpha, selector)
            if priorMinMax = -1 {
                try WinMinimize(selector)
            }
        }
        ; Respect a new window selected by the user during the pulse.
        current := WinExist("A")
        if (current = target || current = previous || A_TimeIdlePhysical >= idleBefore) && WinExist("ahk_id " previous) {
            try {
                WinActivate("ahk_id " previous)
                WinWaitActive("ahk_id " previous, , 0.5)
            }
        }
    }
    if success {
        Successes += 1
        NextPulse := A_TickCount + 120000
        restored := WinActive("ahk_id " previous) ? "true" : "false"
        minimized := WinExist(selector) && WinGetMinMax(selector) = priorMinMax ? "true" : "false"
        background := alreadyFocused ? "false" : "true"
        FileAppend('{"utc":"' A_NowUTC '","background":' background ',"target":' target ',"previous":' previous
            ',"focusRestored":' restored ',"windowStateRestored":' minimized
            ',"keyReleased":true,"count":' Successes ',"ack":' Ack '}`n', LogFile, "UTF-8-RAW")
        Report((alreadyFocused ? "Foreground" : "Background") " F15 pulse sent; focus restored=" restored)
    }
}

Cleanup(*) {
    global Held
    if Held {
        try SendEvent("{vk7E up}")
        Held := false
    }
    Report("Stopped")
}

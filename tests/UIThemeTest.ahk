#Requires AutoHotkey v2.0
#Include ../UITheme.ahk
#Include TestRunner.ahk
#Include UIThemeFixture.ahk

class UIThemeTest {
    static tests := [
        "TestContrastThemeAlwaysWins",
        "TestThemeSettingChoosesLightOrDark",
        "TestUpdateModeReadsTheSettingAndWindows",
        "TestEveryPaletteNamesTheSameColors",
        "TestColorRefSwapsRedAndBlue",
        "TestTextColorsAreReadable"
    ]

    Setup() {
        this.saved := UIThemeFixture.Save()
    }

    Teardown() {
        UIThemeFixture.Restore(this.saved)
    }

    ; A Windows contrast theme is an accessibility need: no setting overrides it.
    TestContrastThemeAlwaysWins() {
        for setting in ["Match Windows", "Light", "Dark"] {
            for windowsDark in [false, true]
                Assert.Equal("contrast", UITheme.ModeFor(setting, windowsDark, true), setting)
        }
    }

    TestThemeSettingChoosesLightOrDark() {
        Assert.Equal("light", UITheme.ModeFor("Match Windows", false, false))
        Assert.Equal("dark", UITheme.ModeFor("Match Windows", true, false))
        Assert.Equal("light", UITheme.ModeFor("Light", true, false))
        Assert.Equal("dark", UITheme.ModeFor("Dark", false, false))
        ; An unknown value is treated as Light, the look before the setting existed.
        Assert.Equal("light", UITheme.ModeFor("", true, false))
    }

    TestUpdateModeReadsTheSettingAndWindows() {
        UIThemeFixture.Use("Match Windows", true, false)
        Assert.Equal("dark", UITheme.UpdateMode())
        Assert.Equal("dark", UITheme.mode)
        Assert.Equal("E6E6E6", UITheme.textColor)
        UIThemeFixture.Use("Match Windows", true, true)
        Assert.Equal("contrast", UITheme.UpdateMode())
        Assert.Equal("Default", UITheme.windowColor)
        UIThemeFixture.Use("Light", true, false)
        Assert.Equal("light", UITheme.UpdateMode())
        Assert.Equal("FFFFFF", UITheme.windowColor)
    }

    TestEveryPaletteNamesTheSameColors() {
        names := []
        for name in UITheme.palettes["light"].OwnProps()
            names.Push(name)
        for mode, palette in UITheme.palettes {
            count := 0
            for name in palette.OwnProps()
                count++
            Assert.Equal(names.Length, count, mode)
            for name in names
                Assert.True(palette.HasOwnProp(name), mode " has " name)
        }
    }

    TestColorRefSwapsRedAndBlue() {
        UITheme.mode := "light"
        Assert.Equal(0x1C2BC4, UITheme.ColorRef("error"))  ; #C42B1C
        Assert.Equal(0x767676, UITheme.ColorRef("muted"))
        UITheme.mode := "contrast"
        Assert.Equal(-1, UITheme.ColorRef("error"))
    }

    ; WCAG AA: 4.5:1 for body text, against each background it is drawn on. Muted
    ; text appears only in the keybind list, on the window color.
    TestTextColorsAreReadable() {
        onPanels := ["text", "secondary", "warning", "ok", "error"]
        drawnOn := Map(
            "window", ["text", "secondary", "warning", "ok", "error", "muted"],
            "panel", onPanels,
            "field", onPanels
        )
        for mode in ["light", "dark"] {
            palette := UITheme.palettes[mode]
            for background, foregrounds in drawnOn {
                for foreground in foregrounds {
                    ratio := UIThemeTest.ContrastRatio(palette.%foreground%, palette.%background%)
                    Assert.True(ratio >= 4.5, mode " " foreground " on " background ": " Round(ratio, 2))
                }
            }
        }
    }

    static ContrastRatio(first, second) {
        a := this.Luminance(first), b := this.Luminance(second)
        return (Max(a, b) + 0.05) / (Min(a, b) + 0.05)
    }

    ; WCAG relative luminance of an RGB hex color.
    static Luminance(hex) {
        total := 0
        for index, weight in [0.2126, 0.7152, 0.0722] {
            channel := Integer("0x" SubStr(hex, 2 * index - 1, 2)) / 255
            linear := channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4
            total += weight * linear
        }
        return total
    }
}

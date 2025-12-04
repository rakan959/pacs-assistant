#Requires AutoHotkey v2.0
#Include ../PACSCommands.ahk
#Include TestRunner.ahk

class PACSCommandsTest {
    static Tests := [
        "TestBuiltInCommandsExist",
        "TestCreateCustomKeybindStoresConfig"
    ]
    
    TestBuiltInCommandsExist() {
        required := [
            "Toggle Dictation",
            "Select Next Field",
            "Select Previous Field",
            "Delete Previous Word",
            "Delete Next Word",
            "Draft Report",
            "Sign Report",
            "Open/Force Restart PACS",
            "Paste Wet Read",
            "Toggle PowerScribe Window",
            "Toggle EPIC Window"
        ]
        
        for name in required {
            Assert.True(PACSCommands.commands.Has(name), "Missing command: " name)
            Assert.True(IsObject(PACSCommands.commands[name]), "Command not callable: " name)
        }
    }
    
    TestCreateCustomKeybindStoresConfig() {
        func := PACSCommands.CreateCustomKeybind("^c")
        Assert.Equal("^c", func.keys)
        Assert.Equal("", func.window)
        
        func2 := PACSCommands.CreateCustomKeybind("^v", "TargetWindow")
        Assert.Equal("^v", func2.keys)
        Assert.Equal("TargetWindow", func2.window)
    }
}

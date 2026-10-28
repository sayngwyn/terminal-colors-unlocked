Scriptname TerminalColorsUnlocked:Holotape extends Terminal
{The configuration holotape's menus, for players without MCM. Attached to
all three of its terminal pages. Item IDs: 1-5 main page, 11-15 presets,
21-26 colour steps (red up, red down, green up, ...).}

TerminalColorsUnlocked:Main Property TCU_MainQuest Auto Const Mandatory

Int Property StepSize = 15 AutoReadOnly ; 0-255 in 17 steps

Event OnMenuItemRun(int auiMenuItemID, ObjectReference akTerminalRef)
	Int id = auiMenuItemID
	If id == 1
		TCU_MainQuest.SetEnabled(True)
	ElseIf id == 2
		TCU_MainQuest.SetEnabled(False)
	ElseIf id == 5
		TCU_MainQuest.ShowColor()
	ElseIf id >= 11 && id <= 15
		TCU_MainQuest.ChoosePreset(id - 10)
	ElseIf id >= 21 && id <= 26
		Int step = StepSize
		If (id - 21) % 2 == 1
			step = -StepSize
		EndIf
		TCU_MainQuest.Nudge((id - 21) / 2, step)
	EndIf
EndEvent

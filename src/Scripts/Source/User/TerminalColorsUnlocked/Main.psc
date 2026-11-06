Scriptname TerminalColorsUnlocked:Main extends Quest
{Tints terminal screens with the player's chosen colour. Needs only F4SE.
The colour lives in four globals, shared by the MCM page and the holotape.}

GlobalVariable Property TCU_Enabled Auto Const Mandatory
GlobalVariable Property TCU_Red Auto Const Mandatory
GlobalVariable Property TCU_Green Auto Const Mandatory
GlobalVariable Property TCU_Blue Auto Const Mandatory
GlobalVariable Property TCU_Preset Auto Const Mandatory
; What a holotape played on the Pip-Boy is drawn in: 0 = the Pip-Boy colour
; (default), 1 = the terminal colour.
GlobalVariable Property TCU_HolotapeMode Auto Const Mandatory
Holotape Property TCU_ConfigHolotape Auto Const Mandatory

; The configuration holotape is given once, also on saves made before it existed.
Bool HolotapeGiven

String Property ModName = "TerminalColorsUnlocked" AutoReadOnly

; Preset colours, by TCU_Preset value (0 = Custom, keeps the sliders).
; Order matches the MCM dropdown and the holotape. On the MCM page the
; colour bar (TCUSwatch.as, same table) applies them; the holotape uses
; ApplyPreset.
Int[] PresetRed
Int[] PresetGreen
Int[] PresetBlue

; Menus that draw terminal text: terminals, holotapes played in a terminal,
; and the terminal's button bar. A holotape played on the Pip-Boy opens
; TerminalMenu and its buttons, not the holotape menu; see PipboyTapeOpen.
String[] Menus

; True from the opening of a terminal menu started by a holotape played on the
; Pip-Boy (not a terminal used in the world) until TerminalMenu closes.
Bool PipboyTapeOpen

; True once the settings holotape (open on the Pip-Boy) ran a colour action: it then
; shows the terminal colour as a live preview, not the Pip-Boy colour, until
; TerminalMenu closes. See PreviewTape.
Bool TapePreview

String Property TintAsset = "TerminalColorsUnlocked/Tint.swf" AutoReadOnly

; Where each menu's tint clip was loaded, by index into Menus ("" = not yet).
String[] TintPaths

; With Pip-Boy FX on the game draws terminals in the Pip-Boy colour and our
; tint can't show, so while a terminal is open the Pip-Boy colour is set to
; the terminal colour, then put back. Reading the player's colour needs
; TerminalColorsUnlocked.dll; without it only FX off is supported.
String Property FXOffSetting = "bPipboyDisableFX:Pipboy" AutoReadOnly
String[] PipboyColorSettings
Int DllVersion
; First DLL version with SetWorldTint / ClearWorldTint.
Int Property WorldTintDllVersion = 2 AutoReadOnly
; First DLL version with Log (lines in the DLL's own log, F4SE\TerminalColorsUnlocked.log).
Int Property LogDllVersion = 3 AutoReadOnly
Bool Swapped
Float[] SavedPipboyColor

Event OnInit()
	RegisterForRemoteEvent(Game.GetPlayer(), "OnPlayerLoadGame")
	Setup()
EndEvent

Event Actor.OnPlayerLoadGame(Actor akSender)
	Setup()
EndEvent

; Called on first start and on every game load: menu registrations and
; loaded clips don't survive a reload.
Function Setup()
	Menus = new String[3]
	Menus[0] = "TerminalMenu"
	Menus[1] = "TerminalHolotapeMenu"
	Menus[2] = "TerminalMenuButtons"
	TintPaths = new String[3]
	PipboyColorSettings = new String[3]
	PipboyColorSettings[0] = "fPipboyEffectColorR:Pipboy"
	PipboyColorSettings[1] = "fPipboyEffectColorG:Pipboy"
	PipboyColorSettings[2] = "fPipboyEffectColorB:Pipboy"
	; A terminal can't be open across a load, and the game's settings are
	; the player's own again, so there's nothing to put back.
	Swapped = False
	PipboyTapeOpen = False
	TapePreview = False
	; Setup can run twice at once (OnInit and a load event). The flag is set
	; before the item is added, so only one run gives it.
	If !HolotapeGiven
		HolotapeGiven = True
		If Game.GetPlayer().GetItemCount(TCU_ConfigHolotape) == 0
			Game.GetPlayer().AddItem(TCU_ConfigHolotape, 1, True)
			Debug.Trace("TerminalColorsUnlocked: gave the settings holotape")
		EndIf
	EndIf
	If F4SE.GetVersionRelease() == 0 ; F4SE missing
		DllVersion = 0
		Return
	EndIf
	DllVersion = TerminalColorsUnlockedNative.GetVersion()
	Debug.Trace("TerminalColorsUnlocked: DLL version " + DllVersion)
	UnregisterForAllMenuOpenCloseEvents()
	Int i = 0
	While i < Menus.Length
		RegisterForMenuOpenCloseEvent(Menus[i])
		i += 1
	EndWhile
	SetupPresets()
	; MCM sends this through F4SE, so nothing here needs MCM installed.
	RegisterForExternalEvent("OnMCMSettingChange|" + ModName, "OnMCMSettingChange")
	; The DLL forgets the colour when the game closes: give it again.
	ApplyWorldTint()
	Note("setup dll=" + DllVersion + " enabled=" + TCU_Enabled.GetValueInt() + " FXOn=" + PipboyFXOn() + " holotapeMode=" + TCU_HolotapeMode.GetValueInt() + " preset=" + TCU_Preset.GetValueInt() + " colour=" + TCU_Red.GetValueInt() + "," + TCU_Green.GetValueInt() + "," + TCU_Blue.GetValueInt())
EndFunction

; Writes a diagnostic line to the Papyrus log and, with DLL 3+, to the DLL's own
; log (always on), so a bug report carries what the mod decided. Read-only: it
; never changes what the mod does. Not for anything that fires every frame.
Function Note(String text)
	Debug.Trace("TerminalColorsUnlocked: " + text)
	If DllVersion >= LogDllVersion
		TerminalColorsUnlockedNative.Log(text)
	EndIf
EndFunction

; The facts behind one opened terminal menu, for its log line. Read-only calls.
String Function OpenInfo(String menuName, Bool movementControls, Int sitState, Bool pipboyMenuOpen, Bool tapeChecked)
	Return "opened " + menuName + " enabled=" + TCU_Enabled.GetValueInt() + " FXOn=" + PipboyFXOn() + " holotapeMode=" + TCU_HolotapeMode.GetValueInt() + " movementControls=" + movementControls + " sitState=" + sitState + " pipboyMenuOpen=" + pipboyMenuOpen + " tapeChecked=" + tapeChecked + " pipboyTape=" + PipboyTapeOpen
EndFunction

; The MCM page applies presets itself (instantly, see TCUSwatch.as); this
; also applies them to the saved colour, in case the page's write is lost.
; It never redraws the page, so it can't fight the page's own display.
Function OnMCMSettingChange(String modName, String id)
	If id == "Preset"
		ApplyPreset()
	EndIf
	ApplyWorldTint()
EndFunction

; Live tint (DLL 2+): the green prompt and cursor drawn on terminal models
; take the terminal colour, or vanilla green again while the mod is off.
Function ApplyWorldTint()
	If DllVersion < WorldTintDllVersion
		Return
	EndIf
	If TCU_Enabled.GetValueInt() == 0
		TerminalColorsUnlockedNative.ClearWorldTint()
		Return
	EndIf
	TerminalColorsUnlockedNative.SetWorldTint(Clamp(TCU_Red.GetValueInt()), Clamp(TCU_Green.GetValueInt()), Clamp(TCU_Blue.GetValueInt()))
EndFunction

Function SetupPresets()
	;                     Custom  Green  Amber  White  Blue   Red
	PresetRed   = new Int[6]
	PresetGreen = new Int[6]
	PresetBlue  = new Int[6]
	SetPreset(1,  20, 255,  23) ; vanilla Pip-Boy green
	SetPreset(2, 255, 182,  66) ; amber
	SetPreset(3, 230, 240, 230) ; soft white
	SetPreset(4,  46, 207, 255) ; blue
	SetPreset(5, 255,  64,  48) ; red
EndFunction

Function SetPreset(Int index, Int r, Int g, Int b)
	PresetRed[index] = r
	PresetGreen[index] = g
	PresetBlue[index] = b
EndFunction

; Applies the chosen preset to the colour globals; 0 (Custom) changes nothing.
Function ApplyPreset()
	Int p = TCU_Preset.GetValueInt()
	If p <= 0 || p >= PresetRed.Length
		Return
	EndIf
	TCU_Red.SetValueInt(PresetRed[p])
	TCU_Green.SetValueInt(PresetGreen[p])
	TCU_Blue.SetValueInt(PresetBlue[p])
EndFunction


Var[] Function ColorArgs()
	Var[] args = new Var[3]
	args[0] = Clamp(TCU_Red.GetValueInt())
	args[1] = Clamp(TCU_Green.GetValueInt())
	args[2] = Clamp(TCU_Blue.GetValueInt())
	Return args
EndFunction

Event OnMenuOpenCloseEvent(String asMenuName, Bool abOpening)
	Int i = Menus.Find(asMenuName)
	If i < 0
		Return
	EndIf
	If !abOpening
		TintPaths[i] = ""
		Bool restored = False
		If i == 0
			PipboyTapeOpen = False
			TapePreview = False
			restored = Swapped
			RestorePipboyColor()
		ElseIf i == 1 && !UI.IsMenuOpen(Menus[0])
			PipboyTapeOpen = False
			TapePreview = False
		EndIf
		Note("closed " + asMenuName + " pipboyColourRestored=" + restored)
		Return
	EndIf
	; A terminal opened by a holotape played on the Pip-Boy is told from one
	; used in the world by the player's state (measured on 1.10.163 and
	; 1.11.240): a world terminal sits the player at the furniture (sit state 3)
	; and locks movement; a Pip-Boy holotape does neither. The flag stays until
	; the terminal closes.
	; The raw inputs of that test, read for the log line (read-only).
	Bool movementControls = Game.IsMovementControlsEnabled()
	Int sitState = Game.GetPlayer().GetSitState()
	Bool pipboyMenuOpen = UI.IsMenuOpen("PipboyMenu")
	Bool tapeChecked = !PipboyTapeOpen
	If !PipboyTapeOpen && IsPipboyTapeNow()
		PipboyTapeOpen = True
	EndIf
	; One log line per opened terminal menu: the facts, then what the mod did.
	String info = OpenInfo(asMenuName, movementControls, sitState, pipboyMenuOpen, tapeChecked)
	If TCU_Enabled.GetValueInt() == 0
		Note(info + " -> nothing, the mod is disabled")
		Return
	EndIf
	; A Pip-Boy holotape set to the Pip-Boy colour: with FX on the game draws it
	; in that colour itself, so nothing is swapped or tinted.
	If PipboyFXOn()
		If i == 0 && !TapeKeepsPipboyColor()
			SwapPipboyColor()
			Note(info + " -> swapped the Pip-Boy colour to the terminal colour, swapped=" + Swapped)
		ElseIf i == 0
			Note(info + " -> left the game's Pip-Boy colour for a Pip-Boy tape")
		Else
			Note(info + " -> nothing for this menu (FX on: the TerminalMenu opening sets the colour)")
		EndIf
		Return
	EndIf
	; FX off: tint it with the player's own Pip-Boy colour, which needs the DLL
	; to read. Without it (or without the setting), leave the game's colour.
	If TapeKeepsPipboyColor() && !CanReadPipboyColor()
		Note(info + " -> left the game's colour for a Pip-Boy tape (the Pip-Boy colour can't be read)")
		Return
	EndIf
	If TapeKeepsPipboyColor()
		Note(info + " -> tinting with the Pip-Boy colour")
	Else
		Note(info + " -> tinting with the terminal colour")
	EndIf
	UI.Load(asMenuName, "root1", TintAsset, Self, "OnTintLoaded")
EndEvent

; True when the terminal opening now comes from a holotape played on the Pip-Boy.
Bool Function IsPipboyTapeNow()
	; Movement controls are on for a Pip-Boy tape (also while seated) and off at a world terminal.
	Return Game.IsMovementControlsEnabled()
EndFunction

; True while a terminal opened by a Pip-Boy holotape is up and holotapes are
; set to use the Pip-Boy colour (not while the settings tape previews a colour).
Bool Function TapeKeepsPipboyColor()
	Return PipboyTapeOpen && !TapePreview && TCU_HolotapeMode.GetValueInt() == 0
EndFunction

; The settings holotape ran a colour action (Holotape.psc calls this first): its
; open screen now shows the terminal colour, so the change can be seen, until
; TerminalMenu closes. Other Pip-Boy holotapes keep the Pip-Boy colour.
Function PreviewTape()
	If !PipboyTapeOpen || TapePreview || TCU_Enabled.GetValueInt() == 0
		Return
	EndIf
	TapePreview = True
	Debug.Trace("TerminalColorsUnlocked: preview tape FXOn=" + PipboyFXOn())
	If PipboyFXOn()
		; The game draws the screen in the Pip-Boy colour: borrow it, as for any terminal.
		If UI.IsMenuOpen(Menus[0])
			SwapPipboyColor()
			If !UI.IsMenuOpen(Menus[0])
				RestorePipboyColor()
			EndIf
		EndIf
		Return
	EndIf
	; FX off: tint with the terminal colour. A menu that got no tint at its opening
	; (the Pip-Boy colour could not be read) gets one now.
	Int i = 0
	While i < Menus.Length
		If UI.IsMenuOpen(Menus[i])
			If TintPaths[i] == ""
				UI.Load(Menus[i], "root1", TintAsset, Self, "OnTintLoaded")
			Else
				ApplyColor(i)
			EndIf
		EndIf
		i += 1
	EndWhile
EndFunction

; True when the DLL is loaded and the game knows the Pip-Boy colour settings.
Bool Function CanReadPipboyColor()
	Return DllVersion > 0 && TerminalColorsUnlockedNative.HasINISetting(PipboyColorSettings[0])
EndFunction

; The colour one menu is tinted with: the player's Pip-Boy colour for a
; Pip-Boy holotape set to follow it, otherwise the terminal colour. White (no
; tint) when the Pip-Boy colour can't be read.
Var[] Function MenuColorArgs(Int i)
	If TapeKeepsPipboyColor()
		If CanReadPipboyColor()
			Return PipboyColorArgs()
		EndIf
		Var[] white = new Var[3]
		white[0] = 255
		white[1] = 255
		white[2] = 255
		Return white
	EndIf
	Return ColorArgs()
EndFunction

; The player's own Pip-Boy colour as 0-255 (the game keeps it as 0-1 floats).
; Needs the DLL; callers check CanReadPipboyColor first.
Var[] Function PipboyColorArgs()
	Var[] args = new Var[3]
	Int c = 0
	While c < 3
		Float f = TerminalColorsUnlockedNative.GetINIFloat(PipboyColorSettings[c])
		args[c] = Clamp((f * 255.0 + 0.5) as Int)
		c += 1
	EndWhile
	Return args
EndFunction

; True when the DLL is loaded and the player has Pip-Boy FX on.
Bool Function PipboyFXOn()
	Return DllVersion > 0 && !TerminalColorsUnlockedNative.GetINIBool(FXOffSetting)
EndFunction

; Remembers the player's Pip-Boy colour and sets it to the terminal colour.
Function SwapPipboyColor()
	If Swapped
		Return
	EndIf
	SavedPipboyColor = new Float[3]
	Var[] color = ColorArgs()
	Int c = 0
	While c < 3
		SavedPipboyColor[c] = TerminalColorsUnlockedNative.GetINIFloat(PipboyColorSettings[c])
		Utility.SetINIFloat(PipboyColorSettings[c], (color[c] as Float) / 255.0)
		c += 1
	EndWhile
	Swapped = True
EndFunction

; Puts the player's own Pip-Boy colour back.
Function RestorePipboyColor()
	If !Swapped
		Return
	EndIf
	Int c = 0
	While c < 3
		Utility.SetINIFloat(PipboyColorSettings[c], SavedPipboyColor[c])
		c += 1
	EndWhile
	Swapped = False
EndFunction

Function OnTintLoaded(Bool success, String menuName, String sourceVar, String destVar, String assetPath)
	Int i = Menus.Find(menuName)
	If !success || i < 0
		Note("tint did not load into " + menuName)
		Return
	EndIf
	TintPaths[i] = destVar
	ApplyColor(i)
EndFunction

; Sends the current colour to the tint clip in one open menu.
Function ApplyColor(Int i)
	If TintPaths[i] == "" || !UI.IsMenuOpen(Menus[i]) || TCU_Enabled.GetValueInt() == 0
		Return
	EndIf
	UI.Invoke(Menus[i], TintPaths[i] + ".SetColor", MenuColorArgs(i))
EndFunction

; Re-applies the colour to every open terminal menu (after a settings change).
Function Refresh()
	Int i = 0
	While i < Menus.Length
		ApplyColor(i)
		i += 1
	EndWhile
EndFunction

; Shows a change at once: re-tints open terminal menus, and with Pip-Boy FX
; on re-sets the borrowed Pip-Boy colour.
Function UpdateLive()
	Refresh()
	ApplyWorldTint()
	If Swapped
		Var[] color = ColorArgs()
		Int c = 0
		While c < 3
			Utility.SetINIFloat(PipboyColorSettings[c], (color[c] as Float) / 255.0)
			c += 1
		EndWhile
	EndIf
EndFunction

; Holotape actions (TerminalColorsUnlocked:Holotape). MCM writes the
; globals itself, so it doesn't use these.
Function SetEnabled(Bool on)
	If on
		TCU_Enabled.SetValueInt(1)
		ApplyWorldTint()
		Return ; the menu tint shows from the next terminal on
	EndIf
	TCU_Enabled.SetValueInt(0)
	ApplyWorldTint()
	RestorePipboyColor()
	Var[] white = new Var[3]
	white[0] = 255
	white[1] = 255
	white[2] = 255
	Int i = 0
	While i < Menus.Length
		If TintPaths[i] != "" && UI.IsMenuOpen(Menus[i])
			UI.Invoke(Menus[i], TintPaths[i] + ".SetColor", white)
		EndIf
		i += 1
	EndWhile
EndFunction

; mode 0 = holotapes on the Pip-Boy use the Pip-Boy colour, 1 = the terminal colour.
Function SetHolotapeMode(Int mode)
	Note("holotapeMode " + TCU_HolotapeMode.GetValueInt() + " -> " + mode + " FXOn=" + PipboyFXOn() + " pipboyTape=" + PipboyTapeOpen)
	TCU_HolotapeMode.SetValueInt(mode)
	Refresh()
	; A Pip-Boy holotape is open (this settings tape, say) and FX is on: borrow the
	; terminal colour for the Pip-Boy, or give the Pip-Boy colour back.
	If TCU_Enabled.GetValueInt() != 0 && PipboyTapeOpen && UI.IsMenuOpen(Menus[0]) && PipboyFXOn()
		If TapeKeepsPipboyColor()
			RestorePipboyColor()
		Else
			SwapPipboyColor()
			If !UI.IsMenuOpen(Menus[0])
				RestorePipboyColor()
			EndIf
		EndIf
	EndIf
EndFunction

Function ChoosePreset(Int p)
	TCU_Preset.SetValueInt(p)
	ApplyPreset()
	UpdateLive()
EndFunction

; channel 0 = red, 1 = green, 2 = blue. Makes the colour Custom.
Function Nudge(Int channel, Int delta)
	GlobalVariable g = TCU_Red
	If channel == 1
		g = TCU_Green
	ElseIf channel == 2
		g = TCU_Blue
	EndIf
	g.SetValueInt(Clamp(g.GetValueInt() + delta))
	TCU_Preset.SetValueInt(0)
	UpdateLive()
EndFunction

Function ShowColor()
	Var[] c = ColorArgs()
	Debug.MessageBox("Terminal colour: red " + c[0] + ", green " + c[1] + ", blue " + c[2] + ".")
EndFunction

Int Function Clamp(Int value)
	If value < 0
		Return 0
	ElseIf value > 255
		Return 255
	EndIf
	Return value
EndFunction

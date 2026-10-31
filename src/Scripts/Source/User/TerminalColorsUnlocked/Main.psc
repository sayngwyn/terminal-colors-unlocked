Scriptname TerminalColorsUnlocked:Main extends Quest
{Tints terminal screens with the player's chosen colour. Needs only F4SE.
The colour lives in four globals, shared by the MCM page and the holotape.}

GlobalVariable Property TCU_Enabled Auto Const Mandatory
GlobalVariable Property TCU_Red Auto Const Mandatory
GlobalVariable Property TCU_Green Auto Const Mandatory
GlobalVariable Property TCU_Blue Auto Const Mandatory
GlobalVariable Property TCU_Preset Auto Const Mandatory
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
; and the terminal's button bar.
String[] Menus

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
		If i == 0
			RestorePipboyColor()
		EndIf
		Return
	EndIf
	If TCU_Enabled.GetValueInt() == 0
		Return
	EndIf
	If PipboyFXOn()
		If i == 0
			SwapPipboyColor()
		EndIf
		Return
	EndIf
	UI.Load(asMenuName, "root1", TintAsset, Self, "OnTintLoaded")
EndEvent

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
		Debug.Trace("TerminalColorsUnlocked: tint did not load into " + menuName)
		Return
	EndIf
	TintPaths[i] = destVar
	ApplyColor(i)
EndFunction

; Sends the current colour to the tint clip in one open menu.
Function ApplyColor(Int i)
	If TintPaths[i] == "" || !UI.IsMenuOpen(Menus[i])
		Return
	EndIf
	UI.Invoke(Menus[i], TintPaths[i] + ".SetColor", ColorArgs())
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

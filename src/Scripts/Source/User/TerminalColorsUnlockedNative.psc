Scriptname TerminalColorsUnlockedNative Native Hidden
{Functions from TerminalColorsUnlocked.dll (F4SE\Plugins). If the DLL is
missing they return 0, False or 0.0, and GetVersion() == 0 says so.}

; DLL version, or 0 when the DLL isn't loaded.
Int Function GetVersion() global native

; True if the game knows this ini setting, e.g. "fPipboyEffectColorR:Pipboy".
Bool Function HasINISetting(String name) global native

; The setting's current in-memory value (0.0 / False if missing).
Float Function GetINIFloat(String name) global native
Bool Function GetINIBool(String name) global native

; DLL version 2 and up. Live tint: repaints the green prompt and cursor drawn
; on terminal models (loaded now and loaded later) in this colour (0-255).
; False if this game version isn't supported (nothing changes then).
Bool Function SetWorldTint(Int r, Int g, Int b) global native

; DLL version 2 and up. Puts vanilla green back on terminal models and stops
; the live tint until SetWorldTint is called again.
Bool Function ClearWorldTint() global native

; DLL version 3 and up. Writes one line, "TerminalColorsUnlocked: <text>", to the
; DLL's own log (F4SE\TerminalColorsUnlocked.log). Cut at 300 characters; at most
; 1000 lines per game session, then it stops.
Function Log(String text) global native

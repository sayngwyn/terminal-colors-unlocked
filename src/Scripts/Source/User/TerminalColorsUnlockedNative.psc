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

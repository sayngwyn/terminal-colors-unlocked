#pragma once
// Papyrus natives shared by both DLLs (script TerminalColorsUnlockedNative).
// Scripts can set ini values (Utility.SetINIFloat) but never read them; these
// read the game's in-memory settings, so the mod can learn the player's
// Pip-Boy colour and whether Pip-Boy FX is on. Since version 2 they also
// drive the live tint of the prompt on terminal models (WorldTint.h).

#include <atomic>

#include "WorldTint.h"

namespace TCU
{
	// 2 (1.1): adds SetWorldTint / ClearWorldTint (live tint on terminal models).
	// 3 (1.2.1): adds Log.
	inline constexpr std::int32_t kVersion = 3;

	inline bool SameKey(std::string_view a, std::string_view b)
	{
		return a.size() == b.size() &&
		       _strnicmp(a.data(), b.data(), a.size()) == 0;
	}

	inline RE::Setting* Find(RE::INISettingCollection* a_coll, std::string_view a_name)
	{
		if (!a_coll) {
			return nullptr;
		}
		for (auto* setting : a_coll->settings) {
			if (setting && SameKey(setting->GetKey(), a_name)) {
				return setting;
			}
		}
		return nullptr;
	}

	// Fallout4Prefs.ini wins over Fallout4.ini, as in the game.
	inline RE::Setting* FindINI(std::string_view a_name)
	{
		if (auto* s = Find(RE::INIPrefSettingCollection::GetSingleton(), a_name)) {
			return s;
		}
		return Find(RE::INISettingCollection::GetSingleton(), a_name);
	}

	// Int Function GetVersion() global native: 0 means the DLL is missing.
	inline std::int32_t GetVersion(std::monostate)
	{
		return kVersion;
	}

	// Bool Function HasINISetting(String name) global native
	inline bool HasINISetting(std::monostate, RE::BSFixedString a_name)
	{
		return FindINI(a_name.c_str()) != nullptr;
	}

	// Float Function GetINIFloat(String name) global native; 0.0 if missing.
	inline float GetINIFloat(std::monostate, RE::BSFixedString a_name)
	{
		auto* s = FindINI(a_name.c_str());
		return s && s->GetType() == RE::Setting::SETTING_TYPE::kFloat ? s->GetFloat() : 0.0f;
	}

	// Bool Function GetINIBool(String name) global native; false if missing.
	inline bool GetINIBool(std::monostate, RE::BSFixedString a_name)
	{
		auto* s = FindINI(a_name.c_str());
		return s && s->GetType() == RE::Setting::SETTING_TYPE::kBinary && s->GetBinary();
	}

	// Void Function Log(String text) global native: one line in this DLL's own log,
	// for the decisions the scripts make (bug reports carry it). Each text is cut
	// at kLogMaxChars; at most kLogMaxLines lines per game session come through
	// here, then one closing line and silence. Scripts call it on menu events and
	// setting changes, never per frame.
	inline constexpr std::size_t kLogMaxChars = 300;
	inline constexpr std::int32_t kLogMaxLines = 1000;

	inline void Log(std::monostate, RE::BSFixedString a_text)
	{
		static std::atomic<std::int32_t> lines{ 0 };
		if (lines.load() > kLogMaxLines) {
			return;  // limit reached: drop silently
		}
		const auto n = lines.fetch_add(1) + 1;
		if (n > kLogMaxLines + 1) {
			return;  // another thread took the closing line
		}
		if (n == kLogMaxLines + 1) {
			TCU_LOG("TerminalColorsUnlocked: log limit reached, no more lines");
			return;
		}
		const char* raw = a_text.c_str();
		std::string_view text = raw ? std::string_view{ raw } : std::string_view{};
		if (text.size() > kLogMaxChars) {
			text = text.substr(0, kLogMaxChars);
		}
		TCU_LOG("TerminalColorsUnlocked: {}", text);
	}

	inline bool Register(RE::BSScript::IVirtualMachine* a_vm)
	{
		constexpr auto script = "TerminalColorsUnlockedNative"sv;
		a_vm->BindNativeMethod(script, "GetVersion"sv, GetVersion, true);
		a_vm->BindNativeMethod(script, "HasINISetting"sv, HasINISetting, true);
		a_vm->BindNativeMethod(script, "GetINIFloat"sv, GetINIFloat, true);
		a_vm->BindNativeMethod(script, "GetINIBool"sv, GetINIBool, true);
		a_vm->BindNativeMethod(script, "SetWorldTint"sv, Tint::SetWorldTint, true);
		a_vm->BindNativeMethod(script, "ClearWorldTint"sv, Tint::ClearWorldTint, true);
		a_vm->BindNativeMethod(script, "Log"sv, Log, true);
		return true;
	}
}

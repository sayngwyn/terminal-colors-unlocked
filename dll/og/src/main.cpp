#include "pch.h"
#include "Natives.h"
#ifdef TCU_SELFTEST
#	include "SelfTest.h"
#endif

// Version data read by F4SE 0.7.x (1.10.984); flags as in the shared template.
F4SE_EXPORT constinit F4SE::PluginVersionData F4SEPlugin_Version = []() noexcept {
	F4SE::PluginVersionData data{};
	data.PluginVersion(REL::Version{ 1, 0, 0, 0 });
	data.PluginName("TerminalColorsUnlocked"sv);
	data.AuthorName("sayngwyn"sv);
	data.UsesAddressLibrary(true);
	data.UsesSigScanning(false);
	data.IsLayoutDependent(true);
	data.HasNoStructUse(false);
	data.CompatibleVersions({ F4SE::RUNTIME_1_10_163, F4SE::RUNTIME_LATEST });
	return data;
}();

// Query entry point used by the old-gen loader (F4SE 0.6.x, runtime 1.10.163).
F4SE_EXPORT bool F4SEPlugin_Query(const F4SE::QueryInterface* a_f4se, F4SE::PluginInfo* a_info)
{
	a_info->infoVersion = F4SE::PluginInfo::kVersion;
	a_info->name = "TerminalColorsUnlocked";
	a_info->version = TCU::kVersion;

	if (a_f4se->IsEditor()) {
		return false;
	}

	const auto ver = a_f4se->RuntimeVersion();
	return ver == F4SE::RUNTIME_1_10_163 || ver == F4SE::RUNTIME_1_10_980 || ver == F4SE::RUNTIME_1_10_984;
}

namespace
{
	void OnMessage(F4SE::MessagingInterface::Message* a_msg)
	{
		if (a_msg && a_msg->type == F4SE::MessagingInterface::kGameDataReady) {
			TCU::Tint::RegisterEvents();
#ifdef TCU_SELFTEST
			TCU::SelfTest::Start();
#endif
		} else if (a_msg && (a_msg->type == F4SE::MessagingInterface::kPostLoadGame || a_msg->type == F4SE::MessagingInterface::kNewGame)) {
			TCU::Tint::OnGameLoaded();
		}
	}
}

F4SE_PLUGIN_LOAD(const F4SE::LoadInterface* a_f4se)
{
	F4SE::Init(a_f4se);

	const auto papyrus = F4SE::GetPapyrusInterface();
	if (!papyrus || !papyrus->Register(TCU::Register)) {
		F4SE::log::error("TerminalColorsUnlocked: failed to register Papyrus functions");
		return false;
	}

	F4SE::log::info("TerminalColorsUnlocked {} loaded", TCU::kVersion);

	// Live tint: the layouts it relies on are checked at runtime, but only
	// on the runtimes this DLL is built for.
	const auto ver = a_f4se->RuntimeVersion();
	TCU::Tint::State::Get().Init(ver.string(),
		ver == F4SE::RUNTIME_1_10_163 || ver == F4SE::RUNTIME_1_10_980 || ver == F4SE::RUNTIME_1_10_984);
	if (const auto messaging = F4SE::GetMessagingInterface(); !messaging || !messaging->RegisterListener(OnMessage)) {
		F4SE::log::info("TerminalColorsUnlocked: no F4SE messaging; live tint off");
	}
	return true;
}

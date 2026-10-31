#include "Natives.h"
#ifdef TCU_SELFTEST
#	include "SelfTest.h"
#endif

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
		REX::ERROR("TerminalColorsUnlocked: failed to register Papyrus functions");
		return false;
	}

	REX::INFO("TerminalColorsUnlocked {} loaded", TCU::kVersion);

	// Live tint: the layouts it relies on are checked at runtime, but only
	// on the runtime this DLL is built for.
	const auto ver = a_f4se->RuntimeVersion();
	TCU::Tint::State::Get().Init(ver.string(), ver == F4SE::RUNTIME_1_11_240);
	if (const auto messaging = F4SE::GetMessagingInterface(); !messaging || !messaging->RegisterListener(OnMessage)) {
		REX::INFO("TerminalColorsUnlocked: no F4SE messaging; live tint off");
	}
	return true;
}

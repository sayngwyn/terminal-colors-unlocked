#include "Natives.h"

F4SE_PLUGIN_LOAD(const F4SE::LoadInterface* a_f4se)
{
	F4SE::Init(a_f4se);

	const auto papyrus = F4SE::GetPapyrusInterface();
	if (!papyrus || !papyrus->Register(TCU::Register)) {
		REX::ERROR("TerminalColorsUnlocked: failed to register Papyrus functions");
		return false;
	}

	REX::INFO("TerminalColorsUnlocked {} loaded", TCU::kVersion);
	return true;
}

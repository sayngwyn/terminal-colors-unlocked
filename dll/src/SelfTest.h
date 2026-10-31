#pragma once
// Test builds only (build.bat test defines TCU_SELFTEST; never in a release):
// drives an automated in-game check. A starting console command takes the
// game into a cell with vanilla terminals. This waits until Main.psc has
// set the colour through SetWorldTint and terminals are loaded, then checks,
// by reading the materials back:
//   1. the player's colour (from Papyrus) is on every terminal prompt shape,
//      before any test action (logs which path painted them),
//   1b. exterior start: after moving the player across the worldspace, the
//      terminals that load there take the colour with no tint call (sweep),
//   2. with no terminal tracked (as after a save load), a recolour still
//      reaches them all by scanning the loaded cells; then a recolour to
//      magenta, then to blue, reaches the same shapes,
//   3. the same colour again changes nothing (idempotent),
//   4. tint off puts the exact vanilla green back,
//   5. a terminal loading while the tint is off loses a colour we wrote,
//   6. the player's colour again.
// Logs "Test: ..." lines and "Test: RESULT PASS|FAIL", then quits the game.

#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <future>
#include <thread>
#include <unordered_set>
#include <vector>

namespace TCU::SelfTest
{
	using namespace std::chrono_literals;

	// Runs a_fn on the main thread; false if it didn't finish in time.
	template <class F>
	bool OnMain(F a_fn, std::chrono::seconds a_timeout = 10s)
	{
		auto done = std::make_shared<std::promise<void>>();
		auto future = done->get_future();
		auto fn = std::make_shared<F>(std::move(a_fn));
		F4SE::GetTaskInterface()->AddTask([done, fn]() { (*fn)(); done->set_value(); });
		return future.wait_for(a_timeout) == std::future_status::ready;
	}

	struct Probe
	{
		bool          inWorld{ false };
		std::size_t   terminals{ 0 };
		std::uint32_t papyrus{ 0 };
	};

	inline std::string Str(const Tint::Color& c)
	{
		return std::format("{:.4f} {:.4f} {:.4f}", c.r, c.g, c.b);
	}

	// Readback after a pass; true if every material we own holds a_expected
	// and no terminal effect material is left vanilla (when a_on).
	inline bool Check(const char* a_step, const Tint::Color& a_expected, bool a_on, Tint::PassResult* a_pass)
	{
		auto rb = std::make_shared<Tint::Readback>();
		auto pass = std::make_shared<Tint::PassResult>();
		auto ok = OnMain([rb, pass, a_expected, a_pass, a_on]() {
			if (a_pass) {
				*pass = Tint::State::Get().RetintAll("self-test");
			}
			*rb = Tint::State::Get().Read(a_expected);
			(void)a_on;
		});
		if (!ok) {
			TCU_LOG("Test: {}: main thread did not answer", a_step);
			return false;
		}
		if (a_pass) {
			*a_pass = *pass;
		}
		const bool good = a_on ? (rb->matching > 0 && rb->other == 0 && rb->vanilla == 0) :
		                         (rb->matching == 0 && rb->other == 0 && rb->vanilla > 0);
		TCU_LOG("Test: {}: wrote {}; read back {} (ours matching {}, ours other {}, vanilla {}){} -> {}",
			a_step, Str(a_expected), rb->matching + rb->other > 0 ? Str(rb->first) : std::string("-"),
			rb->matching, rb->other, rb->vanilla,
			a_pass ? std::format("; pass: {} shapes, {} values changed", pass->shapes, pass->writes) : std::string(),
			good ? "ok" : "FAILED");
		return good;
	}

	inline void Quit()
	{
		TCU_LOG("TerminalColorsUnlocked: test quitting");
		OnMain([]() {
			if (auto* main = RE::Main::GetSingleton()) {
				main->quitGame = true;
			}
		});
	}

	// Readback limited to terminals not in a_before (main thread).
	struct NewTerminals
	{
		std::size_t   count{ 0 };
		std::uint32_t matching{ 0 };
		std::uint32_t other{ 0 };
		std::uint32_t vanilla{ 0 };
		bool          exterior{ false };
		int           cellX{ 0 };
		int           cellY{ 0 };
	};

	inline bool LaterLoads(const Tint::Color& a_player)
	{
		auto before = std::make_shared<std::unordered_set<RE::TESFormID>>();
		auto moved = std::make_shared<NewTerminals>();
		auto counts = std::make_shared<std::array<std::uint32_t, 2>>();
		OnMain([before, moved, counts]() {
			Tint::ScanLoadedTerminals([&](RE::TESFormID a_id) { before->insert(a_id); });
			(*counts)[0] = Tint::State::Get().EventTerminals();
			(*counts)[1] = Tint::State::Get().SweepTerminals();
			auto* player = RE::PlayerCharacter::GetSingleton();
			auto* cell = player ? player->GetParentCell() : nullptr;
			if (!cell || cell->IsInterior()) {
				return;
			}
			// Easy City Downs (Commonwealth 12, 2): unscripted terminals, far from the start.
			moved->exterior = true;
			RE::NiPoint3 pos{ 12 * 4096.0f + 2048.0f, 2 * 4096.0f + 2048.0f, player->data.location.z + 512.0f };
			player->SetPosition(pos, true);
		});
		if (!moved->exterior) {
			TCU_LOG("Test: later loads: interior start, skipped (run an exterior start for this check)");
			return true;
		}
		TCU_LOG("Test: later loads: moved the player to Commonwealth cell 12,2 ({} terminals loaded before); no tint calls from here", before->size());
		// Wait (up to 60 s) for new terminals with 3D, then 4 s for the sweep.
		auto result = std::make_shared<NewTerminals>();
		auto seenAt = std::chrono::steady_clock::time_point{};
		const auto start = std::chrono::steady_clock::now();
		while (std::chrono::steady_clock::now() - start < 60s) {
			std::this_thread::sleep_for(1s);
			OnMain([before, result]() {
				*result = NewTerminals{};
				Tint::ScanLoadedTerminals([&](RE::TESFormID a_id) {
					if (!before->contains(a_id)) {
						result->count++;
					}
				});
			}, 5s);
			if (result->count > 0) {
				if (seenAt == std::chrono::steady_clock::time_point{}) {
					seenAt = std::chrono::steady_clock::now();
				} else if (std::chrono::steady_clock::now() - seenAt >= 4s) {
					break;
				}
			}
		}
		auto after = std::make_shared<std::array<std::uint32_t, 2>>();
		OnMain([before, result, after, a_player]() {
			*result = NewTerminals{};
			if (auto* player = RE::PlayerCharacter::GetSingleton()) {
				result->cellX = static_cast<int>(std::floor(player->data.location.x / 4096.0f));
				result->cellY = static_cast<int>(std::floor(player->data.location.y / 4096.0f));
			}
			std::vector<RE::TESFormID> fresh;
			Tint::ScanLoadedTerminals([&](RE::TESFormID a_id) {
				if (!before->contains(a_id)) {
					fresh.push_back(a_id);
				}
			});
			result->count = fresh.size();
			for (auto id : fresh) {
				const auto rb = Tint::State::Get().ReadOne(id, a_player);
				result->matching += rb.matching;
				result->other += rb.other;
				result->vanilla += rb.vanilla;
			}
			(*after)[0] = Tint::State::Get().EventTerminals();
			(*after)[1] = Tint::State::Get().SweepTerminals();
		});
		const std::uint32_t byEvent = (*after)[0] - (*counts)[0];
		const std::uint32_t bySweep = (*after)[1] - (*counts)[1];
		const bool          ok = result->count > 0 && result->matching > 0 && result->other == 0 && result->vanilla == 0 && bySweep > 0;
		TCU_LOG("Test: later loads: player now in cell {},{}; {} new terminals; their prompt shapes: player colour {}, other {}, vanilla {}; repainted by load events {}, by the sweep {} -> {}",
			result->cellX, result->cellY, result->count, result->matching, result->other, result->vanilla, byEvent, bySweep, ok ? "ok" : "FAILED");
		return ok;
	}

	inline void Run()
	{
		// Wait for the world, terminals and the Papyrus call (up to 4 minutes).
		Probe probe;
		const auto start = std::chrono::steady_clock::now();
		auto ready = std::chrono::steady_clock::time_point{};
		while (std::chrono::steady_clock::now() - start < 240s) {
			std::this_thread::sleep_for(1s);
			auto p = std::make_shared<Probe>();
			OnMain([p]() {
				auto* player = RE::PlayerCharacter::GetSingleton();
				p->inWorld = player && player->GetParentCell() && player->Get3D();
				p->terminals = Tint::ScanLoadedTerminals([](RE::TESFormID) {}).found;
				p->papyrus = Tint::State::Get().PapyrusCalls();
			}, 5s);
			probe = *p;
			if (probe.inWorld && probe.terminals > 0 && probe.papyrus > 0) {
				if (ready == std::chrono::steady_clock::time_point{}) {
					ready = std::chrono::steady_clock::now();
				} else if (std::chrono::steady_clock::now() - ready >= 8s) {
					break;
				}
			}
		}
		TCU_LOG("Test: in world {}, terminals loaded {}, Papyrus tint calls {}, base colour offset {:#x}",
			probe.inWorld, probe.terminals, probe.papyrus, Tint::State::Get().Offset());
		if (!probe.inWorld || probe.terminals == 0 || probe.papyrus == 0 || Tint::State::Get().Offset() < 0) {
			TCU_LOG("Test: RESULT FAIL (not ready: world {}, terminals {}, Papyrus calls {}, offset {})",
				probe.inWorld, probe.terminals, probe.papyrus, Tint::State::Get().Offset());
			Quit();
			return;
		}

		Tint::Color player;
		const bool  on = Tint::State::Get().Target(player);
		bool        all = on;

		// 1. Real play, no test help yet: every terminal loaded at the start
		// holds the player's colour, whichever path got it there.
		auto counts = std::make_shared<std::array<std::uint32_t, 2>>();
		OnMain([counts]() {
			(*counts)[0] = Tint::State::Get().EventTerminals();
			(*counts)[1] = Tint::State::Get().SweepTerminals();
		});
		TCU_LOG("Test: start, before any test action: {} terminals with 3D in the loaded cells; repainted by load events {}, by the sweep {}; Papyrus tint calls {}",
			probe.terminals, (*counts)[0], (*counts)[1], probe.papyrus);
		all &= Check("player colour from Papyrus (no test help)", player, true, nullptr);

		// 2. Terminals that load later in real play: move the player across
		// the worldspace (exterior start only) and, without any tint call,
		// expect the new terminals in the player's colour.
		all &= LaterLoads(player);

		// As after a save load: no terminal is tracked (no load events fire for
		// references already in the cell). A colour change must find them by
		// scanning the loaded cells.
		Tint::PassResult r;
		auto             forgotten = std::make_shared<std::array<std::size_t, 2>>();
		OnMain([forgotten]() {
			Tint::State::Get().ForgetTerminals();
			(*forgotten)[0] = Tint::State::Get().Terminals();
			(*forgotten)[1] = Tint::ScanLoadedTerminals([](RE::TESFormID) {}).found;
		});
		const auto amber = Tint::FromBytes(255, 182, 66);
		Tint::State::Get().SetColor(amber);
		const bool scanOk = Check("save-load case: nothing tracked, recolour to amber", amber, true, &r) &&
		                    (*forgotten)[0] == 0 && r.terminals >= (*forgotten)[1] && (*forgotten)[1] > 0 && r.shapes > 0;
		TCU_LOG("Test: save-load case: tracked after forgetting {}, terminals repainted via scan {} of {}, shapes {} -> {}",
			(*forgotten)[0], r.terminals, (*forgotten)[1], r.shapes, scanOk ? "ok" : "FAILED");
		all &= scanOk;

		const auto magenta = Tint::FromBytes(255, 0, 255);
		const auto blue = Tint::FromBytes(0, 128, 255);
		Tint::State::Get().SetColor(magenta);  // also queues a pass; Check runs one more
		all &= Check("recolour to magenta", magenta, true, &r);
		Tint::State::Get().SetColor(blue);
		all &= Check("recolour to blue", blue, true, &r);
		const bool repaintedSome = r.shapes > 0;
		all &= repaintedSome;
		Check("blue again", blue, true, &r);
		const bool idempotent = r.writes == 0 && r.shapes > 0;
		TCU_LOG("Test: same colour twice: {} shapes, {} values changed -> {}", r.shapes, r.writes, idempotent ? "ok" : "FAILED");
		all &= idempotent;
		Tint::State::Get().Clear();
		all &= Check("tint off (vanilla green back)", Tint::kVanilla, false, &r);

		// A (cached, shared) material still in our colour when its terminal
		// loads after tint off must go back to vanilla on that load.
		Tint::State::Get().SetColor(blue);
		all &= Check("blue before the reload check", blue, true, &r);
		Tint::State::Get().TestOffWithoutPass();
		const bool replayed = OnMain([]() { Tint::State::Get().TestReloadAll(); });
		all &= replayed;
		all &= Check("terminal loads while tint off (vanilla green back)", Tint::kVanilla, false, nullptr);

		Tint::State::Get().SetColor(player);
		all &= Check("player colour again", player, true, &r);

		TCU_LOG("Test: RESULT {} (offset {:#x}, terminals {}, player colour {}, colours written {})",
			all ? "PASS" : "FAIL", Tint::State::Get().Offset(), probe.terminals, Str(player), Tint::State::Get().ColoursWritten());
		std::this_thread::sleep_for(2s);
		Quit();
	}

	inline void Start()
	{
		static std::atomic_bool started{ false };
		if (started.exchange(true)) {
			return;
		}
		TCU_LOG("Test: self-test build; waiting for the world");
		std::thread(Run).detach();
	}
}

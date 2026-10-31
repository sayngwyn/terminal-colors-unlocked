#pragma once
// Live tint of the prompt and cursor drawn on terminal models (1.1).
//
// A terminal's screen shows a green ">" prompt and a blinking cursor before
// the menu opens. They are BSEffectShaderProperty shapes whose material base
// colour is vanilla green (44, 145, 60) / 255. When a terminal's 3D loads, and
// whenever the player's colour changes, this walks the terminal's scene graph
// and sets that colour to the player's, but only where it is still exactly
// vanilla green or a colour this DLL wrote this session. With the tint off,
// colours this DLL wrote go back to vanilla green, also on terminals that
// load later (models and their materials may be cached and shared).
//
// Finding terminals: TESObjectLoadedEvent reaches only references with
// scripts (Papyrus OnLoad), so it can't be relied on. Every colour change
// scans the loaded cells (the player's interior, or the worldspace's attached
// cells and persistent cell), and a sweep about once a second tints
// terminals whose 3D appeared since (new cells, a save load, fast travel).
//
// Safety: nothing here trusts a hard-coded layout on its own.
// - The property and material are recognised by the class names in the
//   game's own RTTI (read through the vtable, inside SEH guards).
// - The material pointer is read at BSShaderProperty+0x58 (both CommonLibF4
//   forks agree on it) and accepted only if it names a BSEffectShaderMaterial.
// - The base colour is at BSEffectShaderMaterial+0x48 on 1.10.163 and
//   1.11.240 (found by a runtime scan during development). It is confirmed at
//   runtime before any write: the first effect material on a terminal must
//   hold vanilla green there with an alpha in [0, 1] after it. Writes only
//   ever go there, and only where the value read is vanilla green or ours.
// - Unknown runtime, or never confirmed: one log line, nothing written.
// All scene-graph work runs on the main thread (F4SE task interface).
//
// Each DLL's pch.h defines TCU_LOG(...) and TCU_NODE_CHILDREN(node).

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <thread>
#include <unordered_map>
#include <bit>
#include <cmath>
#include <cstring>
#include <memory>
#include <mutex>
#include <set>
#include <unordered_set>
#include <vector>

namespace TCU::Tint
{
	struct Color
	{
		float r{ 0.0f };
		float g{ 0.0f };
		float b{ 0.0f };
	};

	// Vanilla prompt green, bit-exact as stored in the terminal NIFs
	// (bytes b1b0303e 9291113f 80f1703e).
	inline const Color kVanilla{
		std::bit_cast<float>(0x3E30B0B1u),
		std::bit_cast<float>(0x3F119192u),
		std::bit_cast<float>(0x3E70F180u)
	};

	inline constexpr float         kEpsilon = 0.0005f;  // well under 1/255
	inline constexpr std::size_t   kMaterialPtrOffset = 0x58;
	inline constexpr std::size_t   kBaseColorOffset = 0x48;  // NiColorA: r, g, b, a
	inline constexpr std::size_t   kMaxNodes = 4096;
	inline constexpr std::uint32_t kMaxDepth = 64;

	inline bool Near(const Color& a, const Color& b)
	{
		return std::fabs(a.r - b.r) < kEpsilon && std::fabs(a.g - b.g) < kEpsilon && std::fabs(a.b - b.b) < kEpsilon;
	}

	inline bool Same(const Color& a, const Color& b)
	{
		return std::memcmp(&a, &b, sizeof(Color)) == 0;
	}

	inline Color FromBytes(std::int32_t r, std::int32_t g, std::int32_t b)
	{
		auto c = [](std::int32_t v) { return static_cast<float>(v < 0 ? 0 : (v > 255 ? 255 : v)) / 255.0f; };
		return { c(r), c(g), c(b) };
	}

	// ---- guarded memory access (no C++ objects in these functions) ----

	inline bool SafeRead(const void* a_src, void* a_dst, std::size_t a_size) noexcept
	{
		__try {
			std::memcpy(a_dst, a_src, a_size);
			return true;
		} __except (1) {
			return false;
		}
	}

	inline bool SafeWriteColor(void* a_dst, const Color* a_src) noexcept
	{
		__try {
			std::memcpy(a_dst, a_src, sizeof(Color));
			return true;
		} __except (1) {
			return false;
		}
	}

	// MSVC x64 RTTI: vtable[-1] -> CompleteObjectLocator -> TypeDescriptor name.
	// True if the object's most-derived class name is exactly a_mangled
	// (e.g. ".?AVBSEffectShaderMaterial@@").
	inline bool ClassIs(const void* a_obj, const char* a_mangled) noexcept
	{
		if (!a_obj) {
			return false;
		}
		__try {
			const auto vtbl = *reinterpret_cast<const std::uintptr_t*>(a_obj);
			if (!vtbl) {
				return false;
			}
			const auto col = *reinterpret_cast<const std::uintptr_t*>(vtbl - 8);
			if (!col) {
				return false;
			}
			const auto* c = reinterpret_cast<const std::int32_t*>(col);
			if (c[0] != 1) {  // signature 1 = x64 image-relative
				return false;
			}
			const auto base = col - static_cast<std::uintptr_t>(static_cast<std::uint32_t>(c[5]));  // pSelf
			if (*reinterpret_cast<const std::uint16_t*>(base) != 0x5A4D) {  // "MZ"
				return false;
			}
			const auto td = base + static_cast<std::uint32_t>(c[3]);
			const auto* name = reinterpret_cast<const char*>(td + 0x10);
			for (std::size_t i = 0;; ++i) {
				if (name[i] != a_mangled[i]) {
					return false;
				}
				if (a_mangled[i] == '\0') {
					return true;
				}
				if (i > 128) {
					return false;
				}
			}
		} __except (1) {
			return false;
		}
	}

	// A reference whose base form is a terminal (TERM), or null. Safe off the
	// main thread: the form lookup takes the game's form-map lock.
	inline RE::TESObjectREFR* LookupTerminal(RE::TESFormID a_id)
	{
		auto* form = RE::TESForm::GetFormByID(a_id);
		auto* ref = form ? form->IsReference() : nullptr;
		if (!ref) {
			return nullptr;
		}
		auto* base = ref->GetObjectReference();
		return base && base->GetFormType() == RE::ENUM_FORM_ID::kTERM ? ref : nullptr;
	}

	// ---- finding terminals already loaded (after a save load, nothing fires
	// TESObjectLoadedEvent for references already in the cell) ----

	inline constexpr std::size_t   kMaxCells = 256;
	inline constexpr std::uint32_t kMaxRefsPerCell = 65536;
	inline constexpr std::size_t   kMaxFound = 4096;

	// Guarded: adds the form ids of a_cell's terminal references that have 3D.
	// The caller holds the cell's lock. No C++ objects here (SEH).
	inline std::size_t CollectTerminalsRaw(RE::TESObjectCELL* a_cell, RE::TESFormID* a_out, std::size_t a_count) noexcept
	{
		__try {
			const auto n = a_cell->references.size();
			for (std::uint32_t i = 0; i < n && i < kMaxRefsPerCell && a_count < kMaxFound; ++i) {
				RE::TESObjectREFR* ref = a_cell->references[i].get();
				if (!ref) {
					continue;
				}
				auto* base = ref->GetObjectReference();
				if (!base || base->GetFormType() != RE::ENUM_FORM_ID::kTERM || !ref->Get3D()) {
					continue;
				}
				a_out[a_count++] = ref->GetFormID();
			}
		} __except (1) {
		}
		return a_count;
	}

	// Guarded: the attached exterior cells of a worldspace, plus its
	// persistent cell. The cell map is read without a lock, so a pointer is
	// kept only if it really is a cell of this worldspace (the caller then
	// takes that cell's lock). No C++ objects here (SEH).
	inline bool CellOf(RE::TESObjectCELL* a_cell, RE::TESWorldSpace* a_world) noexcept
	{
		return a_cell && a_cell->GetFormType() == RE::ENUM_FORM_ID::kCELL && a_cell->worldSpace == a_world;
	}

	inline std::size_t CollectCellsRaw(RE::TESWorldSpace* a_world, RE::TESObjectCELL** a_out, std::size_t a_count) noexcept
	{
		__try {
			for (auto& entry : a_world->cellMap) {
				if (a_count >= kMaxCells) {
					break;
				}
				RE::TESObjectCELL* cell = entry.second;
				if (CellOf(cell, a_world) && cell->cellState == RE::TESObjectCELL::CELL_STATE::kAttached) {
					a_out[a_count++] = cell;
				}
			}
			if (CellOf(a_world->persistentCell, a_world) && a_count < kMaxCells) {
				a_out[a_count++] = a_world->persistentCell;
			}
		} __except (1) {
		}
		return a_count;
	}

	struct ScanResult
	{
		std::size_t cells{ 0 };
		std::size_t found{ 0 };
		bool        interior{ false };
		bool        noPlayer{ false };
	};

	// Main thread. Calls a_add(formID) for each terminal reference with 3D in
	// the loaded cells: the player's cell when inside, else the worldspace's
	// attached cells (and its persistent cell).
	template <class F>
	inline ScanResult ScanLoadedTerminals(F&& a_add)
	{
		ScanResult r;
		auto*      player = RE::PlayerCharacter::GetSingleton();
		auto*      here = player ? player->GetParentCell() : nullptr;
		if (!here) {
			r.noPlayer = true;
			return r;
		}
		// Buffers allocated once (per thread, in case F4SE runs tasks on more
		// than one), not on every pass.
		thread_local auto cells = std::make_unique<RE::TESObjectCELL*[]>(kMaxCells);
		thread_local auto ids = std::make_unique<RE::TESFormID[]>(kMaxFound);
		r.interior = here->IsInterior();
		if (r.interior) {
			cells[0] = here;
			r.cells = 1;
		} else if (auto* world = here->worldSpace) {
			r.cells = CollectCellsRaw(world, cells.get(), 0);
		}
		for (std::size_t c = 0; c < r.cells; ++c) {
			auto* cell = cells[c];
			cell->spinLock.lock();
			r.found = CollectTerminalsRaw(cell, ids.get(), r.found);
			cell->spinLock.unlock();
		}
		// A persistent reference is listed in its exterior cell and in the
		// worldspace's persistent cell: count each terminal once.
		std::sort(ids.get(), ids.get() + r.found);
		r.found = static_cast<std::size_t>(std::unique(ids.get(), ids.get() + r.found) - ids.get());
		for (std::size_t i = 0; i < r.found; ++i) {
			a_add(ids[i]);
		}
		return r;
	}

	// ---- state ----

	struct PassResult
	{
		std::uint32_t terminals{ 0 };  // terminals with 3D visited
		std::uint32_t shapes{ 0 };     // effect shapes now in the player's colour (or restored)
		std::uint32_t writes{ 0 };     // material colour writes that changed a value
		std::uint32_t effects{ 0 };    // effect shapes seen on terminals
	};

	struct Readback
	{
		std::uint32_t matching{ 0 };  // ours: holds the expected colour
		std::uint32_t other{ 0 };     // ours: holds another colour we wrote
		std::uint32_t vanilla{ 0 };   // effect materials on terminals in vanilla green
		Color         first{};        // value read from the first of ours
	};

	class State
	{
	public:
		static State& Get()
		{
			static State s;
			return s;
		}

		// Called once at plugin load.
		void Init(std::string a_runtime, bool a_supported)
		{
			runtime_ = std::move(a_runtime);
			supported_ = a_supported;
			if (supported_) {
				TCU_LOG("TerminalColorsUnlocked: live tint ready on runtime {} (material at property+{:#x}, base colour at material+{:#x}, confirmed before use)",
					runtime_, kMaterialPtrOffset, kBaseColorOffset);
			} else {
				TCU_LOG("TerminalColorsUnlocked: live tint off: runtime {} is not one this DLL knows", runtime_);
			}
		}

		bool Supported() const { return supported_; }

		// Any thread (Papyrus). Sets the colour and queues a repaint.
		void SetColor(Color a_color)
		{
			{
				std::scoped_lock l(lock_);
				enabled_ = true;
				target_ = a_color;
				papyrusCalls_++;
			}
			active_ = true;
			QueueRetint("colour change");
		}

		// Any thread (Papyrus). Puts vanilla green back and stops tinting.
		void Clear()
		{
			{
				std::scoped_lock l(lock_);
				enabled_ = false;
				papyrusCalls_++;
			}
			active_ = true;
			QueueRetint("tint off");
		}

		std::uint32_t PapyrusCalls() const
		{
			std::scoped_lock l(lock_);
			return papyrusCalls_;
		}

		bool Target(Color& a_out) const
		{
			std::scoped_lock l(lock_);
			a_out = target_;
			return enabled_;
		}

		// Main thread only from here on.

		void OnRefLoaded(RE::TESFormID a_id, bool a_loaded)
		{
			if (!supported_) {
				return;
			}
			auto* ref = LookupTerminal(a_id);
			if (!ref) {
				return;
			}
			if (!a_loaded) {
				terminals_.erase(a_id);
				handled_.erase(a_id);
				return;
			}
			terminals_.insert(a_id);
			Color      target;
			const bool on = Target(target);
			if (!on && written_.empty()) {
				return;  // nothing written this session: a vanilla model needs nothing
			}
			PassResult r;
			TintRef(ref, on ? target : kVanilla, on, r);
			handled_[a_id] = ref->Get3D();
			if (r.shapes > 0) {
				eventTerminals_++;
				TCU_LOG("TerminalColorsUnlocked: tint pass (load {:08X}{}): {} shapes repainted on 1 terminal",
					a_id, on ? "" : ", tint off", r.shapes);
			}
			ReportNotConfirmed(r);
		}

		// Main thread, about once a second once a colour was set: finds
		// terminals in the loaded cells whose 3D this DLL hasn't handled yet
		// (new cells, models that finished loading) and tints them. The game
		// sends TESObjectLoadedEvent only for references with scripts, so most
		// terminals that load during play are only found this way.
		void Sweep()
		{
			if (!supported_) {
				return;
			}
			Color      target;
			const bool on = Target(target);
			if (!on && written_.empty()) {
				return;  // tint off and nothing written this session: nothing to do
			}
			const auto paint = on ? target : kVanilla;
			auto&      found = sweepFound_;
			auto&      seen = sweepSeen_;
			found.clear();
			seen.clear();
			const auto scan = ScanLoadedTerminals([&](RE::TESFormID a_id) { found.push_back(a_id); });
			if (scan.noPlayer) {
				return;
			}
			PassResult    r;
			std::uint32_t fresh = 0;
			std::uint32_t painted = 0;
			for (auto id : found) {
				auto* ref = LookupTerminal(id);
				auto* root = ref ? ref->Get3D() : nullptr;
				if (!root) {
					continue;
				}
				seen[id] = root;
				terminals_.insert(id);
				if (const auto it = handled_.find(id); it != handled_.end() && it->second == root) {
					continue;  // already done for this 3D
				}
				fresh++;
				const auto before = r.shapes;
				TintRef(ref, paint, on, r);
				if (r.shapes > before) {
					painted++;
				}
			}
			handled_.swap(seen);  // forgets terminals no longer loaded (buffers reused)
			sweepTerminals_ += painted;
			if (r.shapes > 0) {
				TCU_LOG("TerminalColorsUnlocked: tint pass (new terminals{}): {} shapes repainted on {} of {} new terminal{} ({} with 3D in {} loaded {} cell{})",
					on ? "" : ", tint off", r.shapes, painted, fresh, fresh == 1 ? "" : "s", scan.found, scan.cells,
					scan.interior ? "interior" : "exterior", scan.cells == 1 ? "" : "s");
			}
			ReportNotConfirmed(r);
		}

		PassResult RetintAll(const char* a_why)
		{
			PassResult r;
			if (!supported_) {
				return r;
			}
			Color      target;
			const bool on = Target(target);
			const auto paint = on ? target : kVanilla;
			// Terminals already in the loaded cells: the load event only covers
			// ones that load later (not those present when a save loads).
			const auto scan = ScanLoadedTerminals([this](RE::TESFormID a_id) { terminals_.insert(a_id); });
			if (scan.noPlayer) {
				TCU_LOG("TerminalColorsUnlocked: scan ({}): player not in a cell yet", a_why);
			} else {
				TCU_LOG("TerminalColorsUnlocked: scan ({}): {} terminal{} with 3D in {} loaded {} cell{}",
					a_why, scan.found, scan.found == 1 ? "" : "s", scan.cells, scan.interior ? "interior" : "exterior", scan.cells == 1 ? "" : "s");
			}
			for (auto it = terminals_.begin(); it != terminals_.end();) {
				auto* ref = LookupTerminal(*it);
				if (!ref) {
					it = terminals_.erase(it);
					continue;
				}
				TintRef(ref, paint, on, r);
				handled_[*it] = ref->Get3D();
				++it;
			}
			TCU_LOG("TerminalColorsUnlocked: tint pass ({}): {} shapes repainted on {} terminal{} ({} values changed; colour {:.4f} {:.4f} {:.4f}{})",
				a_why, r.shapes, r.terminals, r.terminals == 1 ? "" : "s", r.writes, paint.r, paint.g, paint.b, on ? "" : ", vanilla");
			ReportNotConfirmed(r);
			return r;
		}

		// Reads back every effect material on loaded terminals (test builds and
		// diagnostics): how many hold a colour we wrote (a_expected or another),
		// how many are vanilla.
		Readback Read(const Color& a_expected)
		{
			Readback rb;
			bool     firstSet = false;
			if (!confirmed_) {
				return rb;
			}
			std::unordered_set<RE::TESFormID> ids(terminals_);
			ScanLoadedTerminals([&](RE::TESFormID a_id) { ids.insert(a_id); });
			for (auto id : ids) {
				ReadInto(id, a_expected, rb, firstSet);
			}
			return rb;
		}

		// The same for one terminal.
		Readback ReadOne(RE::TESFormID a_id, const Color& a_expected)
		{
			Readback rb;
			bool     firstSet = false;
			if (confirmed_) {
				ReadInto(a_id, a_expected, rb, firstSet);
			}
			return rb;
		}

		std::size_t    Terminals() const { return terminals_.size(); }
		std::ptrdiff_t Offset() const { return confirmed_ ? static_cast<std::ptrdiff_t>(kBaseColorOffset) : -1; }
		std::size_t    ColoursWritten() const { return written_.size(); }

		// Main thread, on a game load or new game: the tracked references
		// belong to the previous game; the next pass finds the loaded ones by
		// scanning (Main.psc's Setup sets the colour right after a load).
		void ForgetTerminals()
		{
			terminals_.clear();
			handled_.clear();
		}

		// Counters for the self-test and diagnostics (main thread).
		std::uint32_t EventTerminals() const { return eventTerminals_; }
		std::uint32_t SweepTerminals() const { return sweepTerminals_; }

		// Any thread: whether a sweep is worth queueing.
		bool              Active() const { return active_.load(); }
		std::atomic_bool& SweepQueued() { return sweepQueued_; }

#ifdef TCU_SELFTEST
		// Test builds: turn the tint off without a repaint, as if a terminal
		// whose (cached) material we tinted loads after tint off.
		void TestOffWithoutPass()
		{
			std::scoped_lock l(lock_);
			enabled_ = false;
		}

		// Test builds: replay the load of every tracked terminal (main thread).
		void TestReloadAll()
		{
			const std::vector<RE::TESFormID> ids(terminals_.begin(), terminals_.end());
			for (auto id : ids) {
				OnRefLoaded(id, true);
			}
		}
#endif

	private:
		using Key = std::array<std::uint32_t, 3>;

		State() = default;

		static Key KeyOf(const Color& a_c)
		{
			return { std::bit_cast<std::uint32_t>(a_c.r), std::bit_cast<std::uint32_t>(a_c.g), std::bit_cast<std::uint32_t>(a_c.b) };
		}

		void ReadInto(RE::TESFormID a_id, const Color& a_expected, Readback& a_rb, bool& a_firstSet)
		{
			auto* ref = LookupTerminal(a_id);
			auto* root = ref ? ref->Get3D() : nullptr;
			if (!root) {
				return;
			}
			ForEachEffectMaterial(root, [&](std::uintptr_t a_mat) {
				Color now;
				if (!SafeRead(reinterpret_cast<void*>(a_mat + kBaseColorOffset), &now, sizeof(now))) {
					return;
				}
				if (Ours(now)) {
					if (!a_firstSet) {
						a_rb.first = now;
						a_firstSet = true;
					}
					if (Same(now, a_expected)) {
						a_rb.matching++;
					} else {
						a_rb.other++;
					}
				} else if (Near(now, kVanilla)) {
					a_rb.vanilla++;
				}
			});
		}

		// True if a_c is bit-exactly a colour this DLL wrote this session.
		bool Ours(const Color& a_c) const { return written_.contains(KeyOf(a_c)); }

		static void QueueRetint(const char* a_why)
		{
			if (!Get().supported_) {
				return;
			}
			if (const auto* tasks = F4SE::GetTaskInterface()) {
				tasks->AddTask([a_why]() { Get().RetintAll(a_why); });
			}
		}

		// Calls a_fn(material address) for each BSEffectShaderMaterial under a_root.
		template <class F>
		static void ForEachEffectMaterial(RE::NiAVObject* a_root, F&& a_fn)
		{
			std::size_t visited = 0;
			Walk(a_root, 0, visited, a_fn);
		}

		template <class F>
		static void Walk(RE::NiAVObject* a_obj, std::uint32_t a_depth, std::size_t& a_visited, F& a_fn)
		{
			if (!a_obj || a_depth > kMaxDepth || ++a_visited > kMaxNodes) {
				return;
			}
			if (auto* node = a_obj->IsNode()) {
				for (auto& child : TCU_NODE_CHILDREN(node)) {
					if (child) {
						Walk(child.get(), a_depth + 1, a_visited, a_fn);
					}
				}
				return;
			}
			auto* geom = a_obj->IsGeometry();
			if (!geom) {
				return;
			}
			for (auto& prop : geom->properties) {
				auto* p = prop.get();
				if (!p || !ClassIs(p, ".?AVBSEffectShaderProperty@@")) {
					continue;
				}
				std::uintptr_t mat = 0;
				if (!SafeRead(reinterpret_cast<const std::byte*>(p) + kMaterialPtrOffset, &mat, sizeof(mat)) || !mat) {
					continue;
				}
				if (!ClassIs(reinterpret_cast<const void*>(mat), ".?AVBSEffectShaderMaterial@@")) {
					continue;
				}
				a_fn(mat);
			}
		}

		// Confirms the base colour offset on a material holding vanilla green:
		// r, g, b at +0x48 and an alpha in [0, 1] after them. Nothing else is
		// accepted.
		bool Confirm(std::uintptr_t a_mat)
		{
			float rgba[4];
			if (!SafeRead(reinterpret_cast<const void*>(a_mat + kBaseColorOffset), rgba, sizeof(rgba))) {
				return false;
			}
			const Color c{ rgba[0], rgba[1], rgba[2] };
			if (!Near(c, kVanilla) || !(rgba[3] >= 0.0f && rgba[3] <= 1.0f)) {
				return false;
			}
			confirmed_ = true;
			TCU_LOG("TerminalColorsUnlocked: runtime {}: BSEffectShaderMaterial base colour confirmed at +{:#x} (vanilla green, alpha {:.3f})",
				runtime_, kBaseColorOffset, rgba[3]);
			return true;
		}

		void TintRef(RE::TESObjectREFR* a_ref, const Color& a_paint, bool a_on, PassResult& a_result)
		{
			auto* root = a_ref->Get3D();
			if (!root) {
				return;
			}
			a_result.terminals++;
			ForEachEffectMaterial(root, [&](std::uintptr_t a_mat) {
				a_result.effects++;
				if (!confirmed_ && !Confirm(a_mat)) {
					return;
				}
				auto* field = reinterpret_cast<void*>(a_mat + kBaseColorOffset);
				Color now;
				if (!SafeRead(field, &now, sizeof(now))) {
					return;
				}
				const bool ours = Ours(now);
				if (!a_on) {
					// Tint off: only colours we wrote go back to vanilla green.
					if (!ours || Same(now, kVanilla)) {
						return;
					}
					if (SafeWriteColor(field, &kVanilla)) {
						a_result.writes++;
						a_result.shapes++;
					}
					return;
				}
				if (!ours && !Near(now, kVanilla)) {
					return;  // someone else's colour: leave it
				}
				if (!Same(now, a_paint)) {
					if (!SafeWriteColor(field, &a_paint)) {
						return;
					}
					a_result.writes++;
				}
				a_result.shapes++;
				written_.insert(KeyOf(a_paint));
			});
		}

		void ReportNotConfirmed(const PassResult& a_r)
		{
			if (!confirmed_ && a_r.effects > 0 && !notConfirmedLogged_) {
				notConfirmedLogged_ = true;
				TCU_LOG("TerminalColorsUnlocked: runtime {}: vanilla green not found at +{:#x} in {} terminal effect materials; nothing changed",
					runtime_, kBaseColorOffset, a_r.effects);
			}
		}

		mutable std::mutex lock_;
		bool               enabled_{ false };
		Color              target_{};
		std::uint32_t      papyrusCalls_{ 0 };

		// main thread only
		std::string                       runtime_;
		bool                              supported_{ false };
		bool                              confirmed_{ false };
		std::unordered_set<RE::TESFormID> terminals_;
		std::set<Key>                     written_;  // colours written this session (bit-exact)
		std::unordered_map<RE::TESFormID, RE::NiAVObject*> handled_;  // terminal -> 3D root already done
		std::vector<RE::TESFormID>                         sweepFound_;  // sweep buffers, reused
		std::unordered_map<RE::TESFormID, RE::NiAVObject*> sweepSeen_;
		std::uint32_t                     eventTerminals_{ 0 };
		std::uint32_t                     sweepTerminals_{ 0 };
		std::atomic_bool                  active_{ false };
		std::atomic_bool                  sweepQueued_{ false };
		bool                              notConfirmedLogged_{ false };
	};

	class LoadSink final : public RE::BSTEventSink<RE::TESObjectLoadedEvent>
	{
	public:
		static LoadSink* Get()
		{
			static LoadSink s;
			return &s;
		}

		RE::BSEventNotifyControl ProcessEvent(const RE::TESObjectLoadedEvent& a_event, RE::BSTEventSource<RE::TESObjectLoadedEvent>*) override
		{
			const auto id = a_event.formID;
			const bool loaded = a_event.loaded;
			// Only terminals go on to the main thread (unloads too, for any we track).
			if (!LookupTerminal(id)) {
				return RE::BSEventNotifyControl::kContinue;
			}
			if (const auto* tasks = F4SE::GetTaskInterface()) {
				tasks->AddTask([id, loaded]() { State::Get().OnRefLoaded(id, loaded); });
			}
			return RE::BSEventNotifyControl::kContinue;
		}
	};

	// Call on F4SE kPostLoadGame and kNewGame.
	inline void OnGameLoaded()
	{
		if (!State::Get().Supported()) {
			return;
		}
		if (const auto* tasks = F4SE::GetTaskInterface()) {
			tasks->AddTask([]() { State::Get().ForgetTerminals(); });
		}
	}

	// Call on kGameDataReady.
	inline void RegisterEvents()
	{
		if (!State::Get().Supported()) {
			return;
		}
		if (auto* source = RE::TESObjectLoadedEvent::GetEventSource()) {
			source->RegisterSink(LoadSink::Get());
			TCU_LOG("TerminalColorsUnlocked: watching scripted terminals load");
		}
		// Terminals without scripts get no load event: a light sweep of the
		// loaded cells, about once a second on the main thread, finds them.
		static std::atomic_bool started{ false };
		if (started.exchange(true)) {
			return;
		}
		std::thread([]() {
			using namespace std::chrono_literals;
			for (;;) {
				std::this_thread::sleep_for(1s);
				auto&       state = State::Get();
				const auto* main = RE::Main::GetSingleton();
				if (main && main->quitGame) {
					return;
				}
				if (!state.Active() || state.SweepQueued().exchange(true)) {
					continue;
				}
				if (const auto* tasks = F4SE::GetTaskInterface()) {
					tasks->AddTask([]() {
						State::Get().Sweep();
						State::Get().SweepQueued() = false;
					});
				} else {
					state.SweepQueued() = false;
				}
			}
		}).detach();
		TCU_LOG("TerminalColorsUnlocked: sweeping loaded cells for new terminals once a second");
	}

	// Papyrus: Bool Function SetWorldTint(Int r, Int g, Int b) global native
	inline bool SetWorldTint(std::monostate, std::int32_t a_r, std::int32_t a_g, std::int32_t a_b)
	{
		if (!State::Get().Supported()) {
			return false;
		}
		State::Get().SetColor(FromBytes(a_r, a_g, a_b));
		return true;
	}

	// Papyrus: Bool Function ClearWorldTint() global native
	inline bool ClearWorldTint(std::monostate)
	{
		if (!State::Get().Supported()) {
			return false;
		}
		State::Get().Clear();
		return true;
	}
}

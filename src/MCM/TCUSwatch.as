package
{
	import flash.display.DisplayObject;
	import flash.display.DisplayObjectContainer;
	import flash.display.MovieClip;
	import flash.display.Sprite;
	import flash.events.Event;
	import flash.filters.GlowFilter;
	import flash.geom.ColorTransform;
	import flash.geom.Point;
	import flash.text.TextField;
	import flash.text.TextFormat;
	import flash.utils.getDefinitionByName;

	// The colour preview on the MCM page (MCM image control, lib.swf): a
	// small terminal screen, black with a few lines in the terminal font,
	// drawn in the chosen colour.
	//
	// Everything here works from MCM's own in-memory list entries (the values
	// the sliders show), never from reading the globals back: global writes
	// made while the pause menu is open aren't readable straight away.
	//
	// - MCM tints its option list (and anything in it) with the HUD colour,
	//   so the screen is drawn on one overlay in MCM's config panel, just
	//   above the list and below the dropdown popup. An instance of this class is only an invisible
	//   placeholder that keeps the screen's room in the list.
	// - MCM throws placeholders away and makes new ones whenever it redraws
	//   the list (hover, selection, dropdown), so the overlay and all state
	//   are static: they outlive placeholders and just follow the newest one.
	// - Presets: picking one copies its colour into the R/G/B entries and
	//   globals; moving a slider sets the preset back to Custom.
	public class TCUSwatch extends MovieClip
	{
		private static const W:Number = 560;
		private static const H:Number = 100;
		private static const PAD:Number = 12;
		// The game maps this name to the font terminals use (FontConfig.txt).
		private static const FONT:String = "$Terminal_Font";
		private static const TEXT:String = "Welcome to ROBCO Industries (TM) Termlink\nPassword Accepted\n> ";
		private static const MOD:String = "TerminalColorsUnlocked";
		private static const PLUGIN:String = "TerminalColorsUnlocked.esp|";
		private static const FORMS:Object = {Red: PLUGIN + "801", Green: PLUGIN + "802", Blue: PLUGIN + "803", Preset: PLUGIN + "805"};

		// Same order as the MCM dropdown and Main.psc's presets; 0 = Custom.
		private static const PRESETS:Array = [null,
			[20, 255, 23],    // Classic green (vanilla Pip-Boy green)
			[255, 182, 66],   // Amber
			[230, 240, 230],  // White
			[46, 207, 255],   // Blue
			[255, 64, 48]];   // Red

		private static var lastPreset:int = -1;
		private static var lastColor:int = -1;

		private static var current:TCUSwatch;   // newest placeholder on stage
		private static var overlay:Sprite;
		private static var screen:TextField;
		private static var cursor:Sprite;
		private static var frames:int = 0;
		private static var shown:int = -1;

		public function TCUSwatch()
		{
			super();
			graphics.beginFill(0, 0);
			graphics.drawRect(0, 0, W, H);
			graphics.endFill();
			addEventListener(Event.ADDED_TO_STAGE, OnAdded);
			addEventListener(Event.REMOVED_FROM_STAGE, OnRemoved);
		}

		private static function Menu():Object
		{
			try
			{
				return getDefinitionByName("mcm.MCM_Menu").instance;
			}
			catch (err:Error)
			{
			}
			return null;
		}

		private function OnAdded(e:Event):void
		{
			current = this;
			var menu:Object = Menu();
			if (menu != null && EnsureOverlay(menu))
			{
				Update();
			}
		}

		private function OnRemoved(e:Event):void
		{
			if (current == this)
			{
				current = null;
			}
		}

		// One overlay per config panel; rebuilt only if MCM's panel changed.
		private static function EnsureOverlay(menu:Object):Boolean
		{
			var panel:DisplayObjectContainer = menu.configPanel_mc as DisplayObjectContainer;
			var list:DisplayObject = menu.configPanel_mc.configList_mc as DisplayObject;
			if (panel == null || list == null)
			{
				return false;
			}
			if (overlay != null && overlay.parent == panel)
			{
				return true;
			}
			if (overlay != null)
			{
				overlay.removeEventListener(Event.ENTER_FRAME, OnOverlayFrame);
				if (overlay.parent != null)
				{
					overlay.parent.removeChild(overlay);
				}
			}
			overlay = new Sprite();
			overlay.mouseEnabled = false;
			overlay.mouseChildren = false;
			overlay.visible = false;
			BuildScreen();
			// Just above the list but below the dropdown popup, so an open
			// dropdown covers the screen instead of the screen covering it.
			var index:int = panel.getChildIndex(list) + 1;
			var popup:DisplayObject = menu.configPanel_mc.DD_popup_mc as DisplayObject;
			if (popup != null && popup.parent == panel)
			{
				index = Math.min(index, panel.getChildIndex(popup));
			}
			panel.addChildAt(overlay, index);
			overlay.addEventListener(Event.ENTER_FRAME, OnOverlayFrame);
			shown = -1;
			return true;
		}

		private static function BuildScreen():void
		{
			screen = new TextField();
			screen.embedFonts = true;
			screen.selectable = false;
			screen.multiline = true;
			screen.x = PAD;
			screen.y = PAD - 4;
			screen.width = W - 2 * PAD;
			screen.height = H - PAD;
			screen.defaultTextFormat = new TextFormat(FONT, 20);
			screen.text = TEXT;
			if (screen.textWidth == 0)
			{
				// Font not found: fall back to a plain font rather than nothing.
				screen.embedFonts = false;
				screen.defaultTextFormat = new TextFormat("_typewriter", 20);
				screen.text = TEXT;
			}
			overlay.addChild(screen);
			// Block cursor after the "> " prompt, blinking like a terminal's.
			cursor = new Sprite();
			var box:Object = screen.getCharBoundaries(screen.text.length - 1);
			cursor.x = screen.x + (box != null ? box.right + 2 : 30);
			cursor.y = screen.y + (box != null ? box.top + 2 : H - PAD - 24);
			overlay.addChild(cursor);
		}

		private static function OnOverlayFrame(e:Event):void
		{
			Update();
		}

		// Syncs presets, repaints if the colour changed, and keeps the screen
		// over the newest placeholder (hidden when there is none on screen).
		private static function Update():void
		{
			var menu:Object = Menu();
			if (overlay == null)
			{
				return;
			}
			if (menu == null || current == null || current.stage == null || !current.ShownOnScreen())
			{
				overlay.visible = false;
				return;
			}
			var entries:Object = Entries(menu);
			if (entries.Red == null || entries.Green == null || entries.Blue == null)
			{
				overlay.visible = false;
				return;
			}
			var color:int = SyncPreset(menu, entries);
			if (color != shown)
			{
				shown = color;
				Paint(color);
			}
			frames++;
			cursor.visible = (frames % 60) < 30;
			Place(menu);
		}

		// Black screen with a thin frame; text, cursor and a soft glow in the colour.
		private static function Paint(color:int):void
		{
			overlay.graphics.clear();
			overlay.graphics.lineStyle(2, 0x808080, 0.8);
			overlay.graphics.beginFill(0x000000, 1);
			overlay.graphics.drawRect(0, 0, W, H);
			overlay.graphics.endFill();
			screen.textColor = color;
			screen.filters = [new GlowFilter(color, 0.45, 6, 6, 1.5)];
			cursor.graphics.clear();
			cursor.graphics.beginFill(color);
			cursor.graphics.drawRect(0, 0, 11, 20);
			cursor.graphics.endFill();
		}

		// This mod's entries in MCM's list, by id.
		private static function Entries(menu:Object):Object
		{
			var found:Object = {};
			for each (var entry:Object in menu.configPanel_mc.configList_mc.entryList)
			{
				if (entry != null && entry.modName == MOD && entry.id != undefined)
				{
					found[entry.id] = entry;
				}
			}
			return found;
		}

		private static function Channel(entry:Object):int
		{
			var v:Number = Number(entry.value);
			return isNaN(v) ? 0 : int(Math.max(0, Math.min(255, Math.round(v))));
		}

		// Applies preset changes both ways; returns the colour to show.
		private static function SyncPreset(menu:Object, entries:Object):int
		{
			var preset:int = entries.Preset != null ? int(entries.Preset.value) : 0;
			var color:int = (Channel(entries.Red) << 16) | (Channel(entries.Green) << 8) | Channel(entries.Blue);
			if (lastPreset >= 0)
			{
				if (preset != lastPreset && preset > 0 && preset < PRESETS.length)
				{
					var p:Array = PRESETS[preset];
					SetEntry(menu, entries.Red, p[0]);
					SetEntry(menu, entries.Green, p[1]);
					SetEntry(menu, entries.Blue, p[2]);
					color = (p[0] << 16) | (p[1] << 8) | p[2];
					Redraw(menu);
				}
				else if (preset == lastPreset && preset != 0 && color != lastColor && entries.Preset != null)
				{
					SetEntry(menu, entries.Preset, 0);
					preset = 0;
					Redraw(menu);
				}
			}
			lastPreset = preset;
			lastColor = color;
			return color;
		}

		private static function SetEntry(menu:Object, entry:Object, value:int):void
		{
			entry.value = value;
			// Number, as MCM itself passes: the native call ignores ints.
			menu.mcmCodeObj.SetGlobalValue(FORMS[entry.id], Number(value));
		}

		// Redraws the list from its entries (not from the globals).
		private static function Redraw(menu:Object):void
		{
			var list:Object = menu.configPanel_mc.configList_mc;
			list.allowValueOverwrite = true;
			list.UpdateList();
			list.allowValueOverwrite = false;
		}

		// Keeps the overlay over the placeholder and untinted. It stays shown
		// while a dropdown is open (the popup sits above it).
		private static function Place(menu:Object):void
		{
			var p:Point = overlay.parent.globalToLocal(current.localToGlobal(new Point(0, 0)));
			overlay.x = p.x;
			overlay.y = p.y;
			overlay.scaleX = current.transform.concatenatedMatrix.a / overlay.parent.transform.concatenatedMatrix.a;
			overlay.scaleY = current.transform.concatenatedMatrix.d / overlay.parent.transform.concatenatedMatrix.d;
			var ct:ColorTransform = overlay.parent.transform.concatenatedColorTransform;
			overlay.transform.colorTransform = new ColorTransform(Inverse(ct.redMultiplier),
				Inverse(ct.greenMultiplier), Inverse(ct.blueMultiplier), 1, 0, 0, 0, 0);
			overlay.visible = true;
		}

		private static function Inverse(m:Number):Number
		{
			return m > 0.01 ? 1 / m : 1;
		}

		private function ShownOnScreen():Boolean
		{
			var node:DisplayObject = this;
			while (node != null && node != stage)
			{
				if (!node.visible)
				{
					return false;
				}
				node = node.parent;
			}
			return node == stage;
		}
	}
}

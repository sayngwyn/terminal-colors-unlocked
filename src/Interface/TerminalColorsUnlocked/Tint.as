package
{
	import flash.display.DisplayObject;
	import flash.display.MovieClip;
	import flash.geom.ColorTransform;

	// Loaded by F4SE's UI.Load into a terminal menu's root. Papyrus then calls
	// SetColor(r, g, b); the whole menu is tinted by multiplying each channel,
	// so white text becomes exactly the chosen colour and black stays black.
	public class Tint extends MovieClip
	{
		public function SetColor(r:Number, g:Number, b:Number):void
		{
			var target:DisplayObject = menuRoot();
			if (target == null)
			{
				return;
			}
			target.transform.colorTransform = new ColorTransform(r / 255, g / 255, b / 255, 1, 0, 0, 0, 0);
		}

		// The menu's root clip: F4SE puts this clip inside a Loader on root1.
		private function menuRoot():DisplayObject
		{
			return root != null && root.parent != null ? root.parent.root : null;
		}
	}
}

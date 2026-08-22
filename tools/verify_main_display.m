//	Copyright (c) 2026
//
//	Hills is free software; you can redistribute it and/or modify
//	it under the terms of the GNU General Public License as published by
//	the Free Software Foundation; either version 2 of the License, or
//	(at your option) any later version.
//
//	Hills is distributed in the hope that it will be useful,
//	but WITHOUT ANY WARRANTY; without even the implied warranty of
//	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//	GNU General Public License for more details.
//
//	You should have received a copy of the GNU General Public License
//	along with Hills; if not, write to the Free Software
//	Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA

// Checks that the saver agrees to draw on the main display -- the regression
// that was ss-hx9, where Hills rendered nothing at all.
//
//	xcrun clang -fobjc-arc -framework Cocoa -framework ScreenSaver \
//	    -o /tmp/verify_main_display tools/verify_main_display.m
//	/tmp/verify_main_display build/Release/Hills.saver
//
// Exits non-zero on failure, so it can gate a script.
//
// WHY THIS IS NOT IN tests/ AND NOT IN CI. The tests workflow globs
// `find tests -type f -name "*.m"` into one binary linked against Foundation
// and OpenGL and runs it on a hosted runner. This needs AppKit and ScreenSaver,
// it loads a *built* .saver bundle rather than compiling a source file, and --
// decisively -- it needs real displays: every assertion below is a statement
// about NSScreen and CGMainDisplayID. A headless runner has nothing meaningful
// to say about either. Dropping it into tests/ would break that build.
//
// That is not a gap to close later. ss-hx9 was a wrong choice of *platform
// API*, and no test with a faked screen could have caught it -- a fake would
// have been written against the same misunderstanding. It took asking the real
// window server. So this is a local check, run by a person, and the honest
// place to say so is here rather than in a CI file that cannot run it.
//
// WHAT IT CHECKS. That the saver draws on the display at the origin of the
// global coordinate space and not on the others, that a preview draws wherever
// it is put, that a view with no window yet draws, and that the GL view follows
// a resize. Those are ss-hx9 and ss-2ty.
//
// WHAT IT CANNOT CHECK, AND THIS MATTERS. It cannot tell the current
// implementation apart from the one it replaced. Kill-checked and the mutant
// SURVIVED: swapping -[NSWindow frame].origin back for the old
// -[NSWindow screen] / CGMainDisplayID() comparison passes every assertion
// here.
//
// That is not a gap in the assertions. In an ordinary process -- this one --
// -[NSWindow screen] is populated and the old comparison is perfectly correct.
// It is nil only inside legacyScreenSaver.appex, and only there does the old
// code fall through to "cannot tell, so draw" and render on every display with
// the preference switched on. That was ss-0d8.
//
// So the evidence for ss-0d8 being fixed is NOT this file. It is instrumented
// measurement inside a live appex run -- 83 samples, window origin (0,0) on the
// main display and (0,-1440) on the secondary, no exceptions -- plus a human
// confirming the saver stopped appearing on the second display. Anyone changing
// isOnMainDisplay should expect this harness to keep passing and should not read
// that as safety.

#import <Cocoa/Cocoa.h>
#import <ScreenSaver/ScreenSaver.h>

// Declared here because this tool does not build against the saver's headers;
// it loads the bundle at runtime, the way the real host does.
@interface NSView (HillsUnderTest)
- (BOOL)isOnMainDisplay;
- (BOOL)shouldDraw;
@end

static unsigned displayNumber(NSScreen *screen)
{
	return (unsigned)[screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
}

int main(int argc, const char **argv)
{
	@autoreleasepool
	{
		if (argc < 2)
		{
			fprintf(stderr, "usage: %s <path to Hills.saver>\n", argv[0]);
			return 2;
		}

		[NSApplication sharedApplication];

		NSBundle *bundle = [NSBundle bundleWithPath:@(argv[1])];
		if (![bundle load])
		{
			NSLog(@"FAIL: could not load %s", argv[1]);
			return 2;
		}

		Class viewClass = [bundle principalClass];
		NSLog(@"principalClass = %@", NSStringFromClass(viewClass));
		if (NSScreen.screens.count == 0)
		{
			NSLog(@"FAIL: no displays; this check is meaningless without them");
			return 2;
		}

		// Seed the preference this tool asserts about, and restore it after.
		//
		// shouldDraw is `!mMainDisplayOnly || isOnMainDisplay`, and the view
		// loads mMainDisplayOnly from saved defaults. Without seeding, a machine
		// where the user has switched "main display only" OFF -- persistence
		// that hills#7 makes work -- makes the secondary-display assertion below
		// fail against perfectly correct code. Review of this branch caught it.
		//
		// This process is not sandboxed, so it writes ~/Library/Preferences,
		// which is a different domain from the appex container the saver itself
		// uses. It cannot disturb the installed saver's settings.
		//
		// The restore at the end removes the key rather than the file, so on a
		// machine that had no saved settings this leaves an empty plist behind.
		// It is an empty dictionary, it shadows nothing, and the saver does not
		// read that path -- but it is a file this tool created, so it is called
		// out here rather than left as a surprise.
		ScreenSaverDefaults *prefs =
			[ScreenSaverDefaults defaultsForModuleWithName:bundle.bundleIdentifier];
		id savedMainDisplay = [prefs objectForKey:@"MainDisplay"];
		[prefs setBool:YES forKey:@"MainDisplay"];
		[prefs synchronize];

		int failures = 0;

		for (NSScreen *screen in NSScreen.screens)
		{
			// Position the window at the screen's OWN origin. The check under
			// test asks whether the window sits at the origin of the global
			// coordinate space, so a test window parked at an arbitrary offset
			// would report "not the main display" for every screen and assert
			// nothing. An earlier version of this file did exactly that.
			NSWindow *window = [[NSWindow alloc]
				initWithContentRect:NSMakeRect(0, 0, 400, 300)
						  styleMask:NSWindowStyleMaskBorderless
							backing:NSBackingStoreBuffered
							  defer:NO
							 screen:screen];
			[window setFrameOrigin:screen.frame.origin];

			// isPreview:NO -- previews are exempt by design, so testing the
			// display logic through one would assert nothing.
			ScreenSaverView *view = [[viewClass alloc]
				initWithFrame:NSMakeRect(0, 0, 400, 300) isPreview:NO];
			if (view == nil)
			{
				NSLog(@"FAIL: the view would not initialise");
				failures++;
				continue;
			}
			[window.contentView addSubview:view];

			// The oracle is the display we deliberately put the window on,
			// compared against CGMainDisplayID(). NOT the window origin: that
			// was character-for-character the body of isOnMainDisplay, so the
			// assertion restated the implementation and could not fail. Review
			// of this branch caught that too.
			BOOL expected = (displayNumber(screen) == CGMainDisplayID());

			NSLog(@"display %u  screenOrigin=%@  windowOrigin=%@  expectMain=%@  isOnMainDisplay=%@  shouldDraw=%@",
				  displayNumber(screen),
				  NSStringFromPoint(screen.frame.origin),
				  NSStringFromPoint(window.frame.origin),
				  expected ? @"YES" : @"no ",
				  [view isOnMainDisplay] ? @"YES" : @"no ",
				  [view shouldDraw] ? @"YES" : @"no ");

			if ([view isOnMainDisplay] != expected)
			{
				NSLog(@"  FAIL: isOnMainDisplay disagrees with CGMainDisplayID");
				failures++;
			}
			if (expected && ![view shouldDraw])
			{
				NSLog(@"  FAIL: refuses to draw on the main display -- ss-hx9");
				failures++;
			}
			if (!expected && [view shouldDraw])
			{
				NSLog(@"  FAIL: draws on a secondary display with the preference on -- ss-0d8");
				failures++;
			}
		}

		// A preview must draw wherever it is put. This is the case the user
		// actually reported: System Settings sitting on a second display, and
		// the thumbnail black. Put one on every non-main display and insist.
		for (NSScreen *screen in NSScreen.screens)
		{
			if (displayNumber(screen) == CGMainDisplayID())
				continue;

			NSWindow *window = [[NSWindow alloc]
				initWithContentRect:NSMakeRect(10, 10, 400, 300)
						  styleMask:NSWindowStyleMaskBorderless
							backing:NSBackingStoreBuffered
							  defer:NO
							 screen:screen];
			ScreenSaverView *preview = [[viewClass alloc]
				initWithFrame:NSMakeRect(0, 0, 400, 300) isPreview:YES];
			[window.contentView addSubview:preview];

			if (preview.window.screen == nil ||
				displayNumber(preview.window.screen) == CGMainDisplayID())
				continue;	// did not land where we wanted; asserts nothing

			NSLog(@"preview on non-main display %u:  shouldDraw=%@",
				  displayNumber(preview.window.screen),
				  [preview shouldDraw] ? @"YES" : @"no ");
			if (![preview shouldDraw])
			{
				NSLog(@"  FAIL: a preview must draw on any display");
				failures++;
			}
		}

		// The host builds the view before placing it in a window, so this path
		// is reached every run. It must fail towards drawing: a saver on one
		// display too many is a smaller failure than a saver on none.
		ScreenSaverView *unplaced = [[viewClass alloc]
			initWithFrame:NSMakeRect(0, 0, 400, 300) isPreview:NO];
		NSLog(@"no window yet:  isOnMainDisplay=%@  shouldDraw=%@",
			  [unplaced isOnMainDisplay] ? @"YES" : @"no",
			  [unplaced shouldDraw] ? @"YES" : @"no");
		if (![unplaced shouldDraw])
		{
			NSLog(@"  FAIL: a view with no window yet must default to drawing");
			failures++;
		}

		// The GL view must follow a resize.
		//
		// The host builds the view small and then sizes it to the display, so
		// a GL view that does not follow leaves a correct little picture in the
		// corner of a large black screen. That is what a hot corner showed:
		// blank. autoresizesSubviews is deliberately NO, so the forwarding in
		// -setFrameSize: is the only thing holding this up.
		ScreenSaverView *resized = [[viewClass alloc]
			initWithFrame:NSMakeRect(0, 0, 400, 300) isPreview:NO];
		NSView *glView = resized.subviews.firstObject;
		if (glView == nil)
		{
			NSLog(@"FAIL: no GL subview to resize");
			failures++;
		}
		else
		{
			NSSize target = NSMakeSize(3440, 1440);
			[resized setFrameSize:target];
			NSLog(@"resize 400x300 -> %.0fx%.0f:  glView is now %.0fx%.0f",
				  target.width, target.height,
				  glView.frame.size.width, glView.frame.size.height);
			if (!NSEqualSizes(glView.frame.size, target))
			{
				NSLog(@"  FAIL: the GL view did not follow the resize");
				failures++;
			}
		}

		if (savedMainDisplay != nil)
			[prefs setObject:savedMainDisplay forKey:@"MainDisplay"];
		else
			[prefs removeObjectForKey:@"MainDisplay"];
		[prefs synchronize];

		NSLog(@"%@", failures ? @"=== FAILURES ===" : @"=== all checks passed ===");
		return failures ? 1 : 0;
	}
}

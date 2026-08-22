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
// WHAT ss-hx9 WAS. -[NSScreen mainScreen] is not the main display; it is the
// screen holding the key window. Hills compared it by pointer against its own
// window's screen. Measured on a two-display Mac while fixing this:
//
//	display 1 (IS main)   shipped code said DO NOT DRAW   <- black saver
//	display 2 (not main)  shipped code said DRAW          <- exactly backwards
//
// So the preference did not merely fail, it inverted.

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

		int failures = 0;

		for (NSScreen *screen in NSScreen.screens)
		{
			// contentRect is in the given screen's own coordinates, so pass a
			// local origin -- and then assert against where the window ACTUALLY
			// landed, not where we meant to put it. Getting this wrong once
			// made the tool report a failure that was its own.
			NSWindow *window = [[NSWindow alloc]
				initWithContentRect:NSMakeRect(10, 10, 400, 300)
						  styleMask:NSWindowStyleMaskBorderless
							backing:NSBackingStoreBuffered
							  defer:NO
							 screen:screen];

			// isPreview:NO -- the preview is exempt from the preference by
			// design, so testing the display logic through a preview instance
			// would assert nothing. The preview rule is checked separately
			// below.
			ScreenSaverView *view = [[viewClass alloc]
				initWithFrame:NSMakeRect(0, 0, 400, 300) isPreview:NO];
			if (view == nil)
			{
				NSLog(@"FAIL: the view would not initialise");
				failures++;
				continue;
			}
			[window.contentView addSubview:view];

			NSScreen *landed = view.window.screen;
			if (landed == nil)
			{
				NSLog(@"SKIP: the window reported no screen");
				continue;
			}

			unsigned number = displayNumber(landed);
			BOOL isMain = (number == CGMainDisplayID());
			BOOL shipped = (landed == NSScreen.mainScreen);	// the ss-hx9 comparison

			NSLog(@"display %u (%@main)  shipped-would-draw=%@  isOnMainDisplay=%@  shouldDraw=%@",
				  number, isMain ? @"IS " : @"not ",
				  shipped ? @"YES" : @"no ",
				  [view isOnMainDisplay] ? @"YES" : @"no ",
				  [view shouldDraw] ? @"YES" : @"no ");

			if ([view isOnMainDisplay] != isMain)
			{
				NSLog(@"  FAIL: isOnMainDisplay disagrees with CGMainDisplayID");
				failures++;
			}
			if (isMain && ![view shouldDraw])
			{
				NSLog(@"  FAIL: refuses to draw on the main display -- this is ss-hx9");
				failures++;
			}
			if (isMain && !shipped)
				NSLog(@"  (the shipped comparison would have gone black here)");
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

		NSLog(@"%@", failures ? @"=== FAILURES ===" : @"=== all checks passed ===");
		return failures ? 1 : 0;
	}
}

//	Copyright (c) 2006 Chris Kent
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

#import "HillsScreensaverView.h"
#import "Scene.h"
#import "HillsOpenGLView.h"

#define DEFAULT_LOOK_AHEAD 5.0f
#define DEFAULT_FOG_DENSITY 0.0f
#define DEFAULT_HILLS_HEIGHT 3.75f
#define DEFAULT_CAMERA_HEIGHT 2.0f
#define DEFAULT_GRID_SIZE 151
#define DEFAULT_SPEED 12.1f

@implementation HillsScreensaverView

- (id)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview
{
    self = [super initWithFrame:frame isPreview:isPreview];

    if (self)
    {
		NSValue *red = [NSNumber numberWithFloat:1.0f]; 
		NSValue *green = [NSNumber numberWithFloat:1.0f]; 
		NSValue *blue = [NSNumber numberWithFloat:1.0f]; 
		NSValue *alpha = [NSNumber numberWithFloat:1.0f]; 
   
		NSDictionary *registrationDefaults = [NSDictionary dictionaryWithObjectsAndKeys:
			[ NSNumber numberWithBool:true ], FSAA_KEY,
			[ NSNumber numberWithBool:false ], WIRE_FRAME_KEY,
			[ NSNumber numberWithFloat: DEFAULT_SPEED ], SPEED_KEY,
			[ NSNumber numberWithBool:true], MAIN_DISPLAY_KEY,
			[ NSNumber numberWithFloat: DEFAULT_HILLS_HEIGHT ], HILLS_HEIGHT_KEY,
			[ NSNumber numberWithFloat: DEFAULT_LOOK_AHEAD ], LOOK_AHEAD_KEY,
			[ NSNumber numberWithFloat: DEFAULT_CAMERA_HEIGHT ], CAMERA_HEIGHT_KEY,
			[ NSNumber numberWithInt: DEFAULT_GRID_SIZE ], GRID_SIZE_KEY,
			[ NSNumber numberWithFloat: DEFAULT_FOG_DENSITY ], FOG_DENSITY_KEY,
			[ NSArray arrayWithObjects:red, green, blue, alpha, nil ], FOG_COLOUR_KEY,
			nil];
			
		NSString *identifier = [[NSBundle bundleForClass:[self class]] bundleIdentifier];
		ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:identifier];
		   
		[defaults registerDefaults: registrationDefaults];
		

        NSRect newFrame = frame;
		
		// Keep the frame size, but zero the origin
		newFrame.origin.x = 0.0f;
		newFrame.origin.y = 0.0f;
		mFSAA = [defaults integerForKey:FSAA_KEY];
		glView = [[HillsOpenGLView alloc] initWithFrame:newFrame FSAA:mFSAA];
		[self loadOptions];
		
		[self setAutoresizesSubviews:NO];
		
		if (glView)
		{
			[self addSubview:glView];
			
			[self setAnimationTimeInterval:0.017];
		}
        else
		{
            NSLog(@"Error: Hills Screen Saver failed to initialize NSOpenGLView!");
		}
    }

    return self;
}

// Whether this view is on the display the user means by "main display".
//
// The obvious spelling, [[self window] screen] != [NSScreen mainScreen], is
// wrong twice over, and it is what made the saver draw nothing at all.
//
// -[NSScreen mainScreen] is not the main display. It is the screen containing
// the window with keyboard focus, so it moves as the user changes focus and it
// is meaningless in a process that has no key window -- which is the situation
// inside legacyScreenSaver.appex, where the saver is now hosted out of process.
// Measured on a two-display Mac: CGMainDisplayID() was 1 while mainScreen was
// display 2, so the test failed even for a view on the actual main display.
//
// NSScreen instances are also not pointer-stable -- AppKit vends distinct
// objects describing the same display -- so == is the wrong comparison even
// when the display is right.
//
// Comparing NSScreenNumber against CGMainDisplayID() asks the question the
// preference actually means: is this the display with the menu bar.
- (BOOL)isOnMainDisplay
{
	NSScreen *screen = [[self window] screen];

	// Not in a window yet, so the question cannot be answered. Draw: a saver
	// that renders on one display too many is a smaller failure than one that
	// renders nowhere, and this is reached every time the host builds the view
	// before placing it.
	if (screen == nil)
		return YES;

	NSNumber *displayID = [screen deviceDescription][@"NSScreenNumber"];
	return displayID != nil && [displayID unsignedIntValue] == CGMainDisplayID();
}

- (BOOL)shouldDraw
{
	// The preview is always drawn, whatever the preference says.
	//
	// "Main display only" is about where the saver runs when it takes over the
	// screen. It was never meant to describe the thumbnail in System Settings,
	// and applying it there produces the worst possible reading: a user whose
	// Settings window happens to be on a second display sees a black rectangle
	// and concludes the saver is broken. Which is exactly how ss-hx9 was
	// reported -- and moving the window to the primary display made it render,
	// which is what identified the mechanism.
	if ([self isPreview])
		return YES;

	return !mMainDisplayOnly || [self isOnMainDisplay];
}

- (void)startAnimation
{
	[glView setRender:[self shouldDraw]];

	// Always start the timer, even when this display will not be drawn on.
	// It used to be started only in the drawing case, which left start and
	// stop asymmetric -- stopAnimation calls super unconditionally -- and left
	// the decision frozen at whatever was true before the view had a window.
	// animateOneFrame re-asks every frame, so the saver now recovers if the
	// answer changes.
	[super startAnimation];
}

- (void)stopAnimation
{
    [super stopAnimation];
}

- (void)drawRect:(NSRect)rect
{
    [glView drawRect:rect];
}


- (void)viewDidMoveToWindow
{
	[super viewDidMoveToWindow];
	if (@available(macOS 12.0, *))	// on Monterey and later, update the time interval for the window's screen's refresh rate
	{
		self.animationTimeInterval = self.window.screen.maximumRefreshInterval;
	}
}


- (void)animateOneFrame
{
	// Re-asked every frame rather than trusted from startAnimation, so the
	// saver corrects itself once the view has a window and if the main display
	// changes underneath it. This carried the same broken screen comparison as
	// startAnimation did, so fixing only one of them would have left the view
	// enabled but never marked dirty.
	bool draw = [self shouldDraw];

	[glView setRender:draw];
	if (draw)
		[glView setNeedsDisplay:YES];
}

- (BOOL)hasConfigureSheet
{
    return YES;
}

- (NSWindow*)configureSheet
{
    mIsConfiguring = YES;
    
    if (mConfigureSheet == nil)
		[[NSBundle bundleForClass:self.class] loadNibNamed:@"ConfigureSheet" owner:self topLevelObjects:NULL];
    
	if (mConfigureSheet != nil)
	{
		NSString *identifier = [[NSBundle bundleForClass:[self class]] bundleIdentifier];
		ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:identifier];

		if([defaults boolForKey:FSAA_KEY])
			[mFSAAButton setState:NSOnState];
		else
			[mFSAAButton setState:NSOffState];

		if([defaults boolForKey:WIRE_FRAME_KEY])
			[mWireFrameButton setState:NSOnState];
		else
			[mWireFrameButton setState:NSOffState];

		if([defaults boolForKey:MAIN_DISPLAY_KEY])
			[mMainDisplayButton setState:NSOnState];
		else
			[mMainDisplayButton setState:NSOffState];

		float speed = [defaults floatForKey:SPEED_KEY];
		[mSpeedSlider setFloatValue:speed];
		[mSpeedTextField setStringValue:[NSString stringWithFormat:@"%.2f ", speed]];

		float look_ahead_distance = [defaults floatForKey:LOOK_AHEAD_KEY];
		[mLookAheadSlider setFloatValue:look_ahead_distance];
		[mLookAheadTextField setStringValue:[NSString stringWithFormat:@"%.2f ", look_ahead_distance]];

		float hills_height = [defaults floatForKey:HILLS_HEIGHT_KEY];
		[mHillsHeightSlider setFloatValue:hills_height];
		[mHillsHeightTextField setStringValue:[NSString stringWithFormat:@"%.2f ", hills_height]];
		
		float fog_density = [defaults floatForKey:FOG_DENSITY_KEY];
		[mFogDensitySlider setFloatValue:fog_density];
		[mFogDensityTextField setStringValue:[NSString stringWithFormat:@"%.3f ", fog_density * 0.01]];
		
		float camera_height = [defaults floatForKey:CAMERA_HEIGHT_KEY];
		[mCameraHeightSlider setFloatValue:camera_height];
		[mCameraHeightTextField setStringValue:[NSString stringWithFormat:@"%.2f ", camera_height]];

		GLsizei grid_size = (GLsizei)[defaults integerForKey:GRID_SIZE_KEY];
		[mGridSizeSlider setIntValue:grid_size];
		[mGridSizeTextField setStringValue:[NSString stringWithFormat:@"%d ", grid_size]];

		NSArray *fog_colour_array = [defaults objectForKey:FOG_COLOUR_KEY];
		float redc = [[fog_colour_array objectAtIndex:0] floatValue];
		float greenc = [[fog_colour_array objectAtIndex:1] floatValue];
		float bluec = [[fog_colour_array objectAtIndex:2] floatValue];
		float alphac = [[fog_colour_array objectAtIndex:3] floatValue];
		NSColor *fog_colour = [NSColor colorWithCalibratedRed:redc green:greenc blue:bluec alpha:alphac];
		[mFogColourButton setColor:fog_colour];
	}
    
    return mConfigureSheet;
}

- (IBAction)closeSheet:(id)sender
{
	NSString *identifier = [[NSBundle bundleForClass:[self class]] bundleIdentifier];
	ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:identifier]; 
	
    if ([sender tag]==NSOKButton)
    {
		[self loadOptions];

		NSRect frame = [glView frame];
		//NSLog(@"%f %f", frame.size.width, frame.size.height);
		if ([glView respondsToSelector:@selector(convertRectToBacking:)] && glView.wantsBestResolutionOpenGLSurface)
			[[glView getScene] setViewportRect:[glView convertRectToBacking:frame]];
		else
			[[glView getScene] setViewportRect:frame];
    }
    
    mIsConfiguring= NO;
    
    if ([self isAnimating]==YES)
    {
        [self stopAnimation];
        [self startAnimation];
    }
    [defaults synchronize];
    [NSApp endSheet:mConfigureSheet];
}

- (void) loadOptions
{
	NSString *identifier = [[NSBundle bundleForClass:[self class]] bundleIdentifier];
	ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:identifier];    

	mFSAA = [defaults integerForKey:FSAA_KEY];
	mWireFrame = [defaults integerForKey:WIRE_FRAME_KEY];
	mMainDisplayOnly = [defaults integerForKey:MAIN_DISPLAY_KEY];
	
	[glView setWireFrame:mWireFrame];

	float speed = [defaults floatForKey:SPEED_KEY];
	[[glView getScene] setAnimationSpeed:speed];

	float hills_height = [defaults floatForKey:HILLS_HEIGHT_KEY];
	[[glView getScene] setHillsHeight:hills_height];
	
	float look_ahead_distance = [defaults floatForKey:LOOK_AHEAD_KEY];
	[[glView getScene] setLookAhead:look_ahead_distance];

	float fog_density = [defaults floatForKey:FOG_DENSITY_KEY];
	[[glView getScene] setFogDensity:fog_density * 0.01f];

	float camera_height = [defaults floatForKey:CAMERA_HEIGHT_KEY];
	[[glView getScene] setCameraHeight:camera_height];

	GLsizei grid_size = (GLsizei)[defaults integerForKey:GRID_SIZE_KEY];
	[[glView getScene] setGridSize:grid_size];

	NSArray *fog_colour_array = [defaults objectForKey:FOG_COLOUR_KEY];
	float redc = [[fog_colour_array objectAtIndex:0] floatValue];
	float greenc = [[fog_colour_array objectAtIndex:1] floatValue];
	float bluec = [[fog_colour_array objectAtIndex:2] floatValue];
	float alphac = [[fog_colour_array objectAtIndex:3] floatValue];

	[[glView getScene]  setFogColour_red: redc green:greenc blue:bluec alpha:alphac];
}

- (IBAction)selectFSAAButton:(id)sender
{
	NSString *identifier = [[NSBundle bundleForClass:[self class]] bundleIdentifier];
	ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:identifier];
	
	[defaults setBool:([sender state] == NSOnState) forKey:FSAA_KEY];
}

- (IBAction)selectWireFrameButton:(id)sender
{
	NSString *identifier = [[NSBundle bundleForClass:[self class]] bundleIdentifier];
	ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:identifier];
	
	[defaults setBool:([sender state] == NSOnState) forKey:WIRE_FRAME_KEY];
}

- (IBAction)selectMainDisplayButton:(id)sender
{
	NSString *identifier = [[NSBundle bundleForClass:[self class]] bundleIdentifier];
	ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:identifier];
	
	[defaults setBool:([sender state] == NSOnState) forKey:MAIN_DISPLAY_KEY];
}

- (IBAction)selectSpeedSlider:(id)sender
{
	float speed = [sender floatValue];
	[mSpeedTextField setStringValue:[NSString stringWithFormat:@"%.2f ", speed]];

	NSString *identifier = [[NSBundle bundleForClass:[self class]] bundleIdentifier];
	ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:identifier];
	
	[defaults setFloat:speed forKey:SPEED_KEY];
}

- (IBAction)selectHillsHeightSlider:(id)sender
{
	float hills_height = [sender floatValue];
	[mHillsHeightTextField setStringValue:[NSString stringWithFormat:@"%.2f ", hills_height]];

	NSString *identifier = [[NSBundle bundleForClass:[self class]] bundleIdentifier];
	ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:identifier];
	
	[defaults setFloat:hills_height forKey:HILLS_HEIGHT_KEY];
}

- (IBAction)selectFogDensitySlider:(id)sender
{
	float fog_density = [sender floatValue];
	[mFogDensityTextField setStringValue:[NSString stringWithFormat:@"%.3f ", fog_density * 0.01]];

	NSString *identifier = [[NSBundle bundleForClass:[self class]] bundleIdentifier];
	ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:identifier];
	
	[defaults setFloat:fog_density forKey:FOG_DENSITY_KEY];
}

- (IBAction)selectCameraHeightSlider:(id)sender
{
	float camera_height = [sender floatValue];
	[mCameraHeightTextField setStringValue:[NSString stringWithFormat:@"%.2f ", camera_height]];
	
	NSString *identifier = [[NSBundle bundleForClass:[self class]] bundleIdentifier];
	ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:identifier];
	
	[defaults setFloat:camera_height forKey:CAMERA_HEIGHT_KEY];
}

- (IBAction)selectLookAheadSlider:(id)sender
{
	float look_ahead_distance = [sender floatValue];
	[mLookAheadTextField setStringValue:[NSString stringWithFormat:@"%.2f ", look_ahead_distance]];

	NSString *identifier = [[NSBundle bundleForClass:[self class]] bundleIdentifier];
	ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:identifier];
	
	[defaults setFloat:look_ahead_distance forKey:LOOK_AHEAD_KEY];
}

- (IBAction)selectGridSizeSlider:(id)sender
{
	int grid_size = [sender intValue];
	[mGridSizeTextField setStringValue:[NSString stringWithFormat:@"%d ", grid_size]];

	NSString *identifier = [[NSBundle bundleForClass:[self class]] bundleIdentifier];
	ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:identifier];
	
	[defaults setInteger:grid_size forKey:GRID_SIZE_KEY];
}

- (IBAction)selectFogColourButton:(id)sender
{
	NSColor *color = [[sender color] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
#if CGFLOAT_IS_DOUBLE == 1
	NSNumber *red = [NSNumber numberWithDouble:[color redComponent]];
	NSNumber *green = [NSNumber numberWithDouble:[color greenComponent]];
	NSNumber *blue = [NSNumber numberWithDouble:[color blueComponent]];
	NSNumber *alpha = [NSNumber numberWithDouble:[color alphaComponent]];
#else
	NSNumber *red = [NSNumber numberWithFloat:[color redComponent]];
	NSNumber *green = [NSNumber numberWithFloat:[color greenComponent]];
	NSNumber *blue = [NSNumber numberWithFloat:[color blueComponent]];
	NSNumber *alpha = [NSNumber numberWithFloat:[color alphaComponent]];
#endif

	NSArray *colarray = [NSArray arrayWithObjects:red, green, blue, alpha, nil];

	NSString *identifier = [[NSBundle bundleForClass:[self class]] bundleIdentifier];
	ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:identifier];

	[defaults setObject:colarray forKey:FOG_COLOUR_KEY];
}

- (IBAction)selectDefaultSettings:(id)sender
{
	NSString *identifier = [[NSBundle bundleForClass:[self class]] bundleIdentifier];
	ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:identifier];

	[defaults setFloat:DEFAULT_LOOK_AHEAD forKey:LOOK_AHEAD_KEY];
	[defaults setFloat:DEFAULT_FOG_DENSITY forKey:FOG_DENSITY_KEY];
	[defaults setInteger:DEFAULT_GRID_SIZE forKey:GRID_SIZE_KEY];
	[defaults setFloat:DEFAULT_CAMERA_HEIGHT forKey:CAMERA_HEIGHT_KEY];
	[defaults setFloat:DEFAULT_HILLS_HEIGHT forKey:HILLS_HEIGHT_KEY];
	[defaults setFloat:DEFAULT_SPEED forKey:SPEED_KEY];

	NSValue *red = [NSNumber numberWithFloat:1.0f]; 
	NSValue *green = [NSNumber numberWithFloat:1.0f]; 
	NSValue *blue = [NSNumber numberWithFloat:1.0f]; 
	NSValue *alpha = [NSNumber numberWithFloat:1.0f]; 
	[defaults setObject:[NSArray arrayWithObjects:red, green, blue, alpha, nil] forKey:FOG_COLOUR_KEY];
	
	[self updateControls];
}

- (void)updateControls
{
	NSString *identifier = [[NSBundle bundleForClass:[self class]] bundleIdentifier];
	ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:identifier];

	float speed = [defaults floatForKey:SPEED_KEY];
	[mSpeedSlider setFloatValue:speed];
	[mSpeedTextField setStringValue:[NSString stringWithFormat:@"%.2f ", speed]];

	float hills_height = [defaults floatForKey:HILLS_HEIGHT_KEY];
	[mHillsHeightSlider setFloatValue:hills_height];
	[mHillsHeightTextField setStringValue:[NSString stringWithFormat:@"%.2f ", hills_height]];

	float look_ahead_distance = [defaults floatForKey:LOOK_AHEAD_KEY];
	[mLookAheadSlider setFloatValue:look_ahead_distance];
	[mLookAheadTextField setStringValue:[NSString stringWithFormat:@"%.2f ", look_ahead_distance]];

	float fog_density = [defaults floatForKey:FOG_DENSITY_KEY];
	[mFogDensitySlider setFloatValue:fog_density];
	[mFogDensityTextField setStringValue:[NSString stringWithFormat:@"%.3f ", fog_density * 0.01]];

	float camera_height = [defaults floatForKey:CAMERA_HEIGHT_KEY];
	[mCameraHeightSlider setFloatValue:camera_height];
	[mCameraHeightTextField setStringValue:[NSString stringWithFormat:@"%.2f ", camera_height]];

	GLsizei grid_size = (GLsizei)[defaults integerForKey:GRID_SIZE_KEY];
	[mGridSizeSlider setIntValue:grid_size];
	[mGridSizeTextField setStringValue:[NSString stringWithFormat:@"%d ", grid_size]];

	NSArray *fog_colour_array = [defaults objectForKey:FOG_COLOUR_KEY];
	float redc = [[fog_colour_array objectAtIndex:0] floatValue];
	float greenc = [[fog_colour_array objectAtIndex:1] floatValue];
	float bluec = [[fog_colour_array objectAtIndex:2] floatValue];
	float alphac = [[fog_colour_array objectAtIndex:3] floatValue];
	NSColor *fog_colour = [NSColor colorWithCalibratedRed:redc green:greenc blue:bluec alpha:alphac];
	[mFogColourButton setColor:fog_colour];
}

@end

/*
 File: AVCamViewController.m
 Abstract: View controller for camera interface.
 Version: 3.1
 
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 
 */

#import "AVCamViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <ImageIO/CGImageSource.h>
#import <ImageIO/CGImageProperties.h>


#import <MediaPlayer/MediaPlayer.h>
#import "MBProgressHUD/MBProgressHUD.h"


@interface AVCamViewController ()

// For use in the storyboards.
@property (nonatomic, weak) IBOutlet GPUImageView  *previewView;

// Session management.
@property (nonatomic) dispatch_queue_t sessionQueue; // Communicate with the session and other session objects on this queue.
@property (nonatomic) AVCaptureDevice *videoDevice;

// Utilities.
@property (nonatomic, getter = isDeviceAuthorized) BOOL deviceAuthorized;
@property (nonatomic, readonly, getter = isSessionRunningAndDeviceAuthorized) BOOL sessionRunningAndDeviceAuthorized;

@end

@implementation AVCamViewController

- (BOOL)isSessionRunningAndDeviceAuthorized
{
	return stillCamera.captureSession.isRunning && [self isDeviceAuthorized];
}

+ (NSSet *)keyPathsForValuesAffectingSessionRunningAndDeviceAuthorized
{
	return [NSSet setWithObjects:@"session.running", @"deviceAuthorized", nil];
}

- (void)viewDidLoad
{
	[super viewDidLoad];
    
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryAmbient error:nil];
	[self start];
}

#pragma mark Start

-(void)start
{
	modeCurrent = 0;
	isPressed = 0;
	
	[self templateStart];
	[self captureStart];
    
    [self changeMode:0];
	[self savingEnabledCheck];
    
    [_videoDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
    [_videoDevice setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
    
    // listen to loading completion event from MWPhoto
    [[NSNotificationCenter defaultCenter] addObserverForName:MWPHOTO_LOADING_DID_END_NOTIFICATION object:nil queue:nil usingBlock:^(NSNotification *note) {
        
        if(processingMWPhoto == nil)
            return;

        // do a chain filter applying to the selected images
        // continue from processing MWPhoto
        UIImage *image = processingMWPhoto.underlyingImage;
        
        // apply with noir filter
        GPUImagePicture *stillImageSource = [[GPUImagePicture alloc] initWithImage:image];
        
        [stillImageSource addTarget:noirOutputFilter_forManualApply];
        [noirOutputFilter_forManualApply useNextFrameForImageCapture];
        [stillImageSource processImage];
        
        UIImage *processedImage = [noirOutputFilter_forManualApply imageFromCurrentFramebuffer];
        
        // apply with sharp noir filter
        GPUImagePicture *stillImageSource2 = [[GPUImagePicture alloc] initWithImage:processedImage];
        
        [stillImageSource2 addTarget:sharpOutputFilter_forManualApply];
        [sharpOutputFilter_forManualApply useNextFrameForImageCapture];
        [stillImageSource2 processImage];
        
        processedImage = [sharpOutputFilter_forManualApply imageFromCurrentFramebuffer];
        
        dispatch_async(queue, ^{
            @autoreleasepool
            {
                [assetLibrary writeImageDataToSavedPhotosAlbum:UIImageJPEGRepresentation(processedImage, 1.0) metadata:[stillCamera currentCaptureMetadata] completionBlock:^(NSURL *assetURL, NSError *error) {
                    if(error)
                        NSLog(@"error = %@", error);
                    else
                        NSLog(@"assetURL = %@", assetURL);
                    
                    NSLog(@"Finished applying filter");
                    
                    // finish with this one
                    processingMWPhoto = nil;
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        // hide hud
                        [MBProgressHUD hideHUDForView:self.view animated:YES];
                    });
                }];
                
                //[self saveImage:UIImageJPEGRepresentation(processedImage, 1.0) withMode:0 andEXIF:[stillCamera currentCaptureMetadata]];
            }
        });
    }];
    
    // load assets in the background
    [self loadAssets];
}

-(void)savingEnabledCheck
{
	ALAuthorizationStatus status = [ALAssetsLibrary authorizationStatus];
	if (status != ALAuthorizationStatusAuthorized && status!= ALAuthorizationStatusNotDetermined) {
		_loadingIndicator.backgroundColor = [UIColor redColor];
		isAuthorized = 0;
	}
	else{
		isAuthorized = 1;
	}
	
	if( isAuthorized == 0 ){
		[self displayModeMessage:@"Settings -> Privacy -> Photos"];
	}
}

-(void)templateStart
{
	screen = [[UIScreen mainScreen] bounds];
	tileSize = screen.size.width/8;
	
	_gridView.frame = CGRectMake(0, 0, screen.size.width, screen.size.height);
	_gridView.backgroundColor = [UIColor clearColor];
	
	_blackScreenView.frame = CGRectMake(0, 0, screen.size.width, screen.size.height);
	_blackScreenView.backgroundColor = [UIColor blackColor];
	_blackScreenView.alpha = 0;
	
	_centerHorizontalGrid.backgroundColor = [UIColor colorWithWhite:1 alpha:1];
	_centerHorizontalGrid.frame = CGRectMake(screen.size.width/2, screen.size.height/2, 1, 1);
	
	_centerVerticalGrid.backgroundColor = [UIColor colorWithWhite:1 alpha:1];
	_centerVerticalGrid.frame = CGRectMake(screen.size.width/2, screen.size.height/2, 1, 1);
	
	_centerHorizontalGridSecondary1.backgroundColor = [UIColor colorWithWhite:1 alpha:0];
	_centerHorizontalGridSecondary1.frame = CGRectMake(0, 0, 0, 1);
	
	_centerHorizontalGridSecondary2.backgroundColor = [UIColor colorWithWhite:1 alpha:0];
	_centerHorizontalGridSecondary2.frame = CGRectMake( 0, screen.size.height, screen.size.width, 1);
	
	_centerVerticalGridSecondary1.backgroundColor = [UIColor colorWithWhite:1 alpha:0];
	_centerVerticalGridSecondary1.frame = CGRectMake(0, 0, 1, screen.size.height);
	
	_centerVerticalGridSecondary2.backgroundColor = [UIColor colorWithWhite:1 alpha:0];
	_centerVerticalGridSecondary2.frame = CGRectMake(screen.size.width, 0, 1, screen.size.height);
	
	_loadingIndicator.backgroundColor = [UIColor whiteColor];
	_loadingIndicator.frame = CGRectMake( screen.size.width/2, screen.size.height/2, 1, 1);
	
	_touchIndicatorX.backgroundColor = [UIColor whiteColor];
	_touchIndicatorX.frame = CGRectMake( (screen.size.width - tileSize)+ 15, (screen.size.height - tileSize)+ 15, 5, 5);
	_touchIndicatorX.layer.cornerRadius = 2.5;
    
    _focusTextLabel.frame = CGRectMake(tileSize/4, screen.size.height-tileSize-13, tileSize, tileSize);
	_focusLabel.frame = CGRectMake(tileSize/4, screen.size.height-tileSize, tileSize, tileSize);
    
    _isoTextLabel.frame = CGRectMake(tileSize/4 + tileSize, screen.size.height-tileSize-13, tileSize, tileSize);
    _isoLabel.frame = CGRectMake(tileSize/4 + tileSize, screen.size.height-tileSize, tileSize, tileSize);
    
    _rollTextLabel.frame = CGRectMake(tileSize/4 + (tileSize*6), screen.size.height-tileSize-13, tileSize, tileSize);
    _rollLabel.frame = CGRectMake(tileSize/4 + (tileSize*6), screen.size.height-tileSize, tileSize, tileSize);
    _rollLabel.text = [NSString stringWithFormat:@"%@",[[NSUserDefaults standardUserDefaults] objectForKey:@"photoCount"]];
    
    _modeTextLabel.frame = CGRectMake(tileSize/4 + (tileSize*7), screen.size.height-tileSize-13, tileSize, tileSize);
    _modeLabel.frame = CGRectMake(tileSize/4 + (tileSize*7), screen.size.height-tileSize, tileSize, tileSize);
    _modeButton.frame = CGRectMake(0, screen.size.height-tileSize, screen.size.width, tileSize);
    
	_touchIndicatorX.frame = CGRectMake( screen.size.width/2, screen.size.height/2, 1,1 );
	_touchIndicatorY.frame = CGRectMake( screen.size.width/2, screen.size.height/2, 1, 1);
    
    _imageSelectionButton.frame = CGRectMake(0, 0, screen.size.width, tileSize);
    _imageSelectionButton.enabled = NO;
	
	_isoTextLabel.alpha = 0;
	_focusTextLabel.alpha = 0;
	
	[self gridAnimationIn];
}

-(void)gridAnimationIn
{
	NSLog(@"grid animatio -> In");
	
	[UIView beginAnimations: @"Splash Intro" context:nil];
	[UIView setAnimationDuration:0.3];
	[UIView setAnimationCurve:UIViewAnimationCurveEaseInOut];
	
	_centerHorizontalGrid.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"tile.png"]];
	_centerHorizontalGrid.frame = CGRectMake(0, screen.size.height/2, screen.size.width, 1);
	
	_centerVerticalGrid.backgroundColor = [UIColor colorWithWhite:1 alpha:0.3];
	_centerVerticalGrid.frame = CGRectMake(screen.size.width/2, 0, 1, screen.size.height);
	
	_centerHorizontalGridSecondary1.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
	_centerHorizontalGridSecondary1.frame = CGRectMake(0, (screen.size.height/2) - (2*tileSize), screen.size.width, 1);
	
	_centerHorizontalGridSecondary2.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
	_centerHorizontalGridSecondary2.frame = CGRectMake( 0, (screen.size.height/2) + (2*tileSize), screen.size.width, 1);
	
	_centerVerticalGridSecondary1.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
	_centerVerticalGridSecondary1.frame = CGRectMake(tileSize*3, 0, 1, screen.size.height);
	
	_centerVerticalGridSecondary2.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
	_centerVerticalGridSecondary2.frame = CGRectMake(tileSize*5, 0, 1, screen.size.height);
	
	[UIView commitAnimations];
}

-(void)gridAnimationOut
{
	NSLog(@"grid animatio -> Out");
	[UIView beginAnimations: @"Splash Intro" context:nil];
	[UIView setAnimationDuration:0.5];
	[UIView setAnimationCurve:UIViewAnimationCurveEaseInOut];
	
	_centerHorizontalGrid.frame = CGRectMake(screen.size.width/4, screen.size.height/2, screen.size.width/2, 1);
	
	_centerVerticalGrid.backgroundColor = [UIColor colorWithWhite:1 alpha:0.3];
	_centerVerticalGrid.frame = CGRectMake(screen.size.width/2, (screen.size.height/2)-((screen.size.height/40)/2), 1, screen.size.height/40);
	
	_centerHorizontalGridSecondary1.backgroundColor = [UIColor colorWithWhite:1 alpha:0];
	_centerHorizontalGridSecondary1.frame = CGRectMake(0, 0, screen.size.width, 1);
	
	_centerHorizontalGridSecondary2.backgroundColor = [UIColor colorWithWhite:1 alpha:0];
	_centerHorizontalGridSecondary2.frame = CGRectMake( 0, screen.size.height, screen.size.width, 1);
	
	_centerVerticalGridSecondary1.backgroundColor = [UIColor colorWithWhite:1 alpha:0];
	_centerVerticalGridSecondary1.frame = CGRectMake(0, 0, 1, screen.size.height);
	
	_centerVerticalGridSecondary2.backgroundColor = [UIColor colorWithWhite:1 alpha:0];
	_centerVerticalGridSecondary2.frame = CGRectMake(screen.size.width, 0, 1, screen.size.height);
	
	[UIView commitAnimations];
}

-(void)updateLensData
{
    if([_videoDevice respondsToSelector:@selector(lensPosition)] && [_videoDevice respondsToSelector:@selector(exposureDuration)] ) {
		_focusLabel.text = [NSString stringWithFormat:@"%d%%", (int)([_videoDevice lensPosition] * 100) ];
		_isoLabel.text = [NSString stringWithFormat:@"%d", (int)([_videoDevice ISO])+2 ];
		_isoTextLabel.alpha = 1;
		_focusTextLabel.alpha = 1;
	}
}

-(void)captureStart
{
    [stillCamera stopCameraCapture];
    [stillCamera removeAllTargets];
    [self checkDeviceAuthorizationStatus];
    
    dispatch_queue_t sessionQueue = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL);
    [self setSessionQueue:sessionQueue];
    
    //Setting up filters takes a little while do it in a background queue where it won't block
    dispatch_async(sessionQueue, ^{
        stillCamera = [[GPUImageStillCamera alloc] initWithSessionPreset:AVCaptureSessionPresetPhoto cameraPosition:AVCaptureDevicePositionBack];
        
        stillCamera.outputImageOrientation = UIInterfaceOrientationPortrait;
        
        [stillCamera removeAllTargets];
        
        inputFilter = [ScreenAspectRatioCropFilter new];
        
        noirOutputFilter = [NoirFilter new];
        sharpOutputFilter = [NoirSharpFilter new];
        
        [stillCamera addTarget:inputFilter];
        
        [inputFilter addTarget:noirOutputFilter];
        
        [noirOutputFilter addTarget:sharpOutputFilter];
        
        [sharpOutputFilter addTarget:self.previewView];
        
        [stillCamera startCameraCapture];
        
        _videoDevice = stillCamera.inputCamera;
        self.previewView.fillMode = kGPUImageFillModePreserveAspectRatioAndFill;
        if([_videoDevice respondsToSelector:@selector(lensPosition)]) {
            [_videoDevice addObserver:self forKeyPath:@"lensPosition" options:NSKeyValueObservingOptionNew context:nil];
            [_videoDevice addObserver:self forKeyPath:@"ISO" options:NSKeyValueObservingOptionNew context:nil];
        }
        
        // setting up for manual apply
        noirOutputFilter_forManualApply = [NoirFilter new];
        sharpOutputFilter_forManualApply = [NoirSharpFilter new];
        
        //[noirOutputFilter_forManualApply addTarget:sharpOutputFilter_forManualApply];
    });
    
    [self installVolume];
	
	[self apiContact:@"noirca":@"analytics":@"launch":@"1"];
    
    queue = dispatch_queue_create("com.XXIIVV.SaveImageQueue", NULL);
    
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if([keyPath isEqualToString:@"lensPosition"] || [keyPath isEqualToString:@"ISO"]) {
        [self updateLensData];
    }
}

- (BOOL)prefersStatusBarHidden
{
	return YES;
}

- (BOOL)shouldAutorotate
{
    return false;
}

- (NSUInteger)supportedInterfaceOrientations
{
	return UIInterfaceOrientationMaskPortrait;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
	[[(AVCaptureVideoPreviewLayer *)[[self previewView] layer] connection] setVideoOrientation:AVCaptureVideoOrientationPortrait];
}

#pragma mark Touch

- (void) touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
	UITouch *theTouch = [touches anyObject];
	startPoint = [theTouch locationInView:self.focusView];
	
	isReady = 1;
	
	[self updateLensData];
}

-(void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
	UITouch *theTouch = [touches anyObject];
	movedPoint = [theTouch locationInView:self.focusView];
	
	[self updateLensData];
}

- (void) touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
	if(isReady == 1){
		[self takePicture];
		[self updateLensData];
	}
	
	isPressed = 0;
}

#pragma mark Picture

-(void)takePicture
{
	if( isAuthorized == 0 ){
		[self savingEnabledCheck];
		[self displayModeMessage:@"--"];
		return;
	}

	int pictureCount = [[[NSUserDefaults standardUserDefaults] objectForKey:@"photoCount"] intValue];
	
	// Remove preview image
	if( self.previewThing.image ){
		[UIView beginAnimations: @"Splash Intro" context:nil];
		[UIView setAnimationDuration:1];
		[UIView setAnimationCurve:UIViewAnimationCurveEaseInOut];
		_loadingIndicator.alpha = 1;
		_blackScreenView.alpha = 0;
		[UIView commitAnimations];
		
		self.previewThing.image = NULL;
	
		[self gridAnimationIn];
		return;
	}
    
    if( isRendering > 0 || capturing  || !stillCamera.captureSession.isRunning){  //disallow if the user has already taken two images
        [self displayModeMessage:@"wait"];
        return;
    }
	
	_previewThing.alpha = 0;
	
	// Save
	
    stillCamera.outputImageOrientation = UIInterfaceOrientationPortrait;
    
    capturing = true;
    [stillCamera capturePhotoAsImageProcessedUpToFilter:sharpOutputFilter withOrientation:UIImageOrientationUp withCompletionHandler:^(UIImage *processedImage, NSError *error) {
        if (processedImage)
        {
            
            dispatch_async(queue, ^{
                @autoreleasepool
                {
                    dispatch_async(dispatch_get_main_queue(), ^ {
                        @autoreleasepool
                        {
                            
                            [UIView animateWithDuration:0.5 animations:^{
                                _previewThing.alpha = 1;
                            } completion:^(BOOL finished) {
                                capturing = false;
                            }];
                            self.previewThing.image = [self imageScaledToScreen:processedImage];
                            [[NSUserDefaults standardUserDefaults] setInteger:pictureCount+1 forKey:@"photoCount"];
                        }
                    });
                    [self clearBuffers];
                    [self saveImage:UIImageJPEGRepresentation(processedImage, 1.0) withMode:0 andEXIF:[stillCamera currentCaptureMetadata]];
                }
            });
        }
        if(error) {
            isRendering--;
            capturing=false;
        }
    }];
    
	[self gridAnimationOut];
    
    _rollLabel.text = [NSString stringWithFormat:@"%@",[[NSUserDefaults standardUserDefaults] objectForKey:@"photoCount"]];
	
	_blackScreenView.alpha = 1;
	
}

-(void) applyFilterToSelectedPhotos
{
    if( isAuthorized == 0 ){
        [self savingEnabledCheck];
        [self displayModeMessage:@"--"];
        return;
    }
    
    for(int i=0; i<[selections count]; i++)
    {
        NSNumber *selectionNumber = [selections objectAtIndex:i];
        
        if([selectionNumber boolValue])
        {
            // set to processing MWPhoto
            processingMWPhoto = [photos objectAtIndex:i];
            
            // when it finishes, it will notifies via notification, then we continue
            // the task at that point.
            [processingMWPhoto loadUnderlyingImageAndNotify];
            
            // TODO: fix this to support multiple photos selection
            break;
        }
    }
}

-(void) clearBuffers
{
    [stillCamera stopCameraCapture];
    [[GPUImageContext sharedFramebufferCache] purgeAllUnassignedFramebuffers];
    [stillCamera startCameraCapture];
    [self changeMode:0];
}

-(UIImage*)imageScaledToScreen: (UIImage*) sourceImage
{
    //CGSize bounds = sourceImage.size;
    float oldHeight = sourceImage.size.height;
    float screenHeight =[[UIScreen mainScreen] bounds].size.height*[[UIScreen mainScreen] scale];
    float scaleFactor = screenHeight / oldHeight;
    
    float newWidth = sourceImage.size.width * scaleFactor;
    float newHeight = screenHeight;
    
    /*UIGraphicsBeginImageContext(CGSizeMake(newWidth, newHeight));
    [sourceImage drawInRect:CGRectMake(0, 0, newWidth, newHeight)];
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newImage;*/
    
    CGImageRef imageRef = sourceImage.CGImage;
    
    // Build a context that's the same dimensions as the new size
    CGContextRef bitmap = CGBitmapContextCreate(NULL,
                                                newWidth,
                                                newHeight,
                                                CGImageGetBitsPerComponent(imageRef),
                                                0,
                                                CGImageGetColorSpace(imageRef),
                                                CGImageGetBitmapInfo(imageRef));
    
    // Rotate and/or flip the image if required by its orientation
    //CGContextConcatCTM(bitmap, transform);
    
    // Draw into the context; this scales the image
    CGContextDrawImage(bitmap, CGRectMake(0, 0, newWidth, newHeight), imageRef);
    
    // Get the resized image from the context and a UIImage
    CGImageRef newImageRef = CGBitmapContextCreateImage(bitmap);
    UIImage *newImage = [UIImage imageWithCGImage:newImageRef];
    
    // Clean up
    CGContextRelease(bitmap);
    CGImageRelease(newImageRef);
    
    return newImage;
}

-(void)displayModeMessage :(NSString*)message
{
	_modeLabel.alpha = 0;
	_modeLabel.text = message;
	
	[UIView beginAnimations: @"Splash Intro" context:nil];
	[UIView setAnimationCurve:UIViewAnimationCurveEaseInOut];
	[UIView setAnimationDelay:0];
	[UIView setAnimationDuration:0.5];
	_modeLabel.alpha = 1;
	_loadingIndicator.alpha = 1;
	[UIView commitAnimations];
}

-(void)saveImage:(NSData*)imageData withMode:(int)mode andEXIF:(NSDictionary*)exifData
{
	UIBackgroundTaskIdentifier bgTask = UIBackgroundTaskInvalid;
    bgTask =   [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        // Clean up any unfinished task business by marking where you
        // stopped or ending the task outright.
        [[UIApplication sharedApplication] endBackgroundTask:bgTask];
    }];
    
    dispatch_async(queue, ^{
        @autoreleasepool
        {
            NSMutableDictionary *exifm = [exifData mutableCopy];
            
            [exifm setObject:[NSNumber numberWithInt:0] forKey:@"Orientation"];
            
            [assetLibrary writeImageDataToSavedPhotosAlbum:imageData metadata:exifm completionBlock:^(NSURL *assetURL, NSError *error) {
                [[UIApplication sharedApplication] endBackgroundTask:bgTask];
                isRendering--;
                
                if(error)
                    NSLog(@"error = %@", error);
                else
                    NSLog(@"assetURL = %@", assetURL);
            }];
        }
    });
}



#pragma mark UI

- (void)runStillImageCaptureAnimation
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[[[self previewView] layer] setOpacity:0.0];
		[UIView animateWithDuration:.25 animations:^{
			[[[self previewView] layer] setOpacity:1.0];
		}];
	});
}

- (void)checkDeviceAuthorizationStatus
{
	NSString *mediaType = AVMediaTypeVideo;
	
	[AVCaptureDevice requestAccessForMediaType:mediaType completionHandler:^(BOOL granted) {
		if (granted)
		{
			//Granted access to mediaType
			[self setDeviceAuthorized:YES];
		}
		else
		{
			//Not granted access to mediaType
			dispatch_async(dispatch_get_main_queue(), ^{
				[[[UIAlertView alloc] initWithTitle:@"AVCam!"
											message:@"AVCam doesn't have permission to use Camera, please change privacy settings"
										   delegate:self
								  cancelButtonTitle:@"OK"
								  otherButtonTitles:nil] show];
				[self setDeviceAuthorized:NO];
			});
		}
	}];
}

#pragma mark Volume Button

/* Instructions:
 1. Add the Media player framework to your project.
 2. Insert following code into the controller for your shutter view.
 3. Add [self installVolume] to your viewdidload function
 4. add your shutter trigger code to the volumeChanged function
 5. Call uninstallVolume whenever you want to remove the volume changed notification
 
 note: If the user holds the volume+ button down, the volumeChanged function will be called repeatedly, be sure to add a rate limiter if your application isn't setup to take multiple photos a second.
 
 */

float currentVolume; //Current Volume

-(void)installVolume { /*Installs the volume button view and sets up the notifications to trigger the volumechange and the resetVolume button*/
    MPVolumeView *volumeView = [[MPVolumeView alloc] initWithFrame:CGRectMake(-100, -100, 1, 1)];
    volumeView.showsRouteButton = NO;
    [self.previewView addSubview:volumeView];
    [self.previewView sendSubviewToBack:volumeView];
    
    [self resetVolumeButton];
    
    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(volumeChanged:)
     name:@"AVSystemController_SystemVolumeDidChangeNotification"
     object:nil];
    
    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(resetVolumeButton) name:UIApplicationDidBecomeActiveNotification object:nil];
}

-(void)uninstallVolume { /*removes notifications, install when you are closing the app or the camera view*/
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:@"AVSystemController_SystemVolumeDidChangeNotification"
                                                  object:nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIApplicationDidBecomeActiveNotification
                                                  object:nil];
}

-(void)resetVolumeButton { /*gets the current volume and sets up the button, needs to be called when the app returns from background.*/
    currentVolume=-1;
    AVAudioPlayer* p = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"silence.wav"]] error:NULL];
    
    [p prepareToPlay];
    [p stop];
}

- (void)volumeChanged:(NSNotification *)notification{
    float volume = [[[notification userInfo] objectForKey:@"AVSystemController_AudioVolumeNotificationParameter"] floatValue];
    if( [[[notification userInfo]objectForKey:@"AVSystemController_AudioVolumeChangeReasonNotificationParameter"]isEqualToString:@"ExplicitVolumeChange"]) {
        if(volume>=currentVolume && volume>0) {
            /* Do shutter button stuff here!*/
            [self takePicture];
        }
    }
    currentVolume=volume;
}

- (IBAction)modeButton:(id)sender
{
    [self changeMode:1];
}

- (IBAction)imageSelectButton:(id)sender {
    NSLog(@"Touched Image selection button");
    
    dispatch_async(dispatch_get_main_queue(), ^{
        MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        hud.mode = MBProgressHUDModeIndeterminate;
        hud.labelText = @"Displaying ...";
    });
    
    photos = [NSMutableArray array];
    thumbs = [NSMutableArray array];
    
    // start
    @synchronized(assets) {
        NSMutableArray *copy = [assets copy];
        for (ALAsset *asset in copy) {
            [photos addObject:[MWPhoto photoWithURL:asset.defaultRepresentation.url]];
            [thumbs addObject:[MWPhoto photoWithImage:[UIImage imageWithCGImage:asset.thumbnail]]];
        }
    }
    
    // Create browser
    MWPhotoBrowser *browser = [[MWPhotoBrowser alloc] initWithDelegate:self];
    browser.displayActionButton = NO;
    browser.displayNavArrows = YES;
    browser.displaySelectionButtons = YES;
    browser.alwaysShowControls = YES;
    browser.zoomPhotosToFill = YES;
#if __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_7_0
    browser.wantsFullScreenLayout = YES;
#endif
    browser.enableGrid = YES;
    browser.startOnGrid = YES;
    browser.enableSwipeToDismiss = YES;
    [browser setCurrentPhotoIndex:0];
    
    // Reset selections
    selections = [NSMutableArray new];
    for (int i = 0; i < photos.count; i++) {
        [selections addObject:[NSNumber numberWithBool:NO]];
    }
    
    // Modal
    UINavigationController *nc = [[UINavigationController alloc] initWithRootViewController:browser];
    nc.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:nc animated:YES completion:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            // hide hud
            [MBProgressHUD hideHUDForView:self.view animated:YES];
        });
    }];
}

-(NSUInteger)numberOfPhotosInPhotoBrowser:(MWPhotoBrowser *)photoBrowser
{
    return photos.count;
}

-(id<MWPhoto>)photoBrowser:(MWPhotoBrowser *)photoBrowser photoAtIndex:(NSUInteger)index
{
    if(index < photos.count)
        return [photos objectAtIndex:index];
    return nil;
}

- (id <MWPhoto>)photoBrowser:(MWPhotoBrowser *)photoBrowser thumbPhotoAtIndex:(NSUInteger)index {
    if (index < thumbs.count)
        return [thumbs objectAtIndex:index];
    return nil;
}

-(BOOL)photoBrowser:(MWPhotoBrowser *)photoBrowser isPhotoSelectedAtIndex:(NSUInteger)index
{
    return [[selections objectAtIndex:index] boolValue];
}

-(void)photoBrowser:(MWPhotoBrowser *)photoBrowser photoAtIndex:(NSUInteger)index selectedChanged:(BOOL)selected
{
    [selections replaceObjectAtIndex:index withObject:[NSNumber numberWithBool:selected]];
}

-(void)photoBrowserDidFinishModalPresentation:(MWPhotoBrowser *)photoBrowser
{
    // finally dismiss modal view
    [photoBrowser dismissViewControllerAnimated:YES completion:^{
        NSLog(@"Dismiss view controller");
    }];
    
    BOOL atLeastOneIsSelected = NO;
    for(NSNumber *selected in selections)
    {
        if([selected boolValue])
            atLeastOneIsSelected = YES;
    }
    
    if(atLeastOneIsSelected)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
            hud.mode = MBProgressHUDModeIndeterminate;
            hud.labelText = @"Applying ...";
        });
    }
    
    // process selected photos with noir filter
    [self applyFilterToSelectedPhotos];
}

- (void)loadAssets {
    
    // Initialise
    assets = [NSMutableArray new];
    assetLibrary = [[ALAssetsLibrary alloc] init];
    
    // Run in the background as it takes a while to get all assets from the library
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        NSMutableArray *assetGroups = [[NSMutableArray alloc] init];
        NSMutableArray *assetURLDictionaries = [[NSMutableArray alloc] init];
        
        // Process assets
        void (^assetEnumerator)(ALAsset *, NSUInteger, BOOL *) = ^(ALAsset *result, NSUInteger index, BOOL *stop) {
            if (result != nil) {
                if ([[result valueForProperty:ALAssetPropertyType] isEqualToString:ALAssetTypePhoto]) {
                    [assetURLDictionaries addObject:[result valueForProperty:ALAssetPropertyURLs]];
                    NSURL *url = result.defaultRepresentation.url;
                    [assetLibrary assetForURL:url
                                   resultBlock:^(ALAsset *asset) {
                                       if (asset) {
                                           @synchronized(assets) {
                                               [assets addObject:asset];
                                           }
                                       }
                                   }
                                  failureBlock:^(NSError *error){
                                      NSLog(@"operation was not successfull!");
                                  }];
                    
                }
            }
        };
        
        // Process groups
        void (^ assetGroupEnumerator) (ALAssetsGroup *, BOOL *) = ^(ALAssetsGroup *group, BOOL *stop) {
            if (group != nil) {
                [group enumerateAssetsWithOptions:NSEnumerationReverse usingBlock:assetEnumerator];
                [assetGroups addObject:group];
            }
        };
        
        // Process!
        [assetLibrary enumerateGroupsWithTypes:ALAssetsGroupSavedPhotos
                                         usingBlock:assetGroupEnumerator
                                       failureBlock:^(NSError *error) {
                                           NSLog(@"There is an error");
                                       }];
        
        // get as much as it can load at this point
        _imageSelectionButton.enabled = YES;
        NSLog(@"Successfully loaded assets so far");
    });
    
}

-(void)changeMode:(int)increment {
    [_videoDevice lockForConfiguration:nil];
    
    if(![_videoDevice respondsToSelector:@selector(lensPosition)] || ![_videoDevice respondsToSelector:@selector(exposureDuration)] ) {
        return;
    }
    
    modeCurrent += increment;
    if(modeCurrent < 0 ) {
        modeCurrent = 0;
    }
    if(modeCurrent > 3 || (modeCurrent > 2 && !_videoDevice.torchAvailable)){
        modeCurrent = 0;
    }
    
    if( modeCurrent == 0 ){
        [_videoDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
        [_videoDevice setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
        _modeLabel.textColor = [UIColor redColor];
        [self displayModeMessage:@"A"];
    }
    if( modeCurrent == 1 ){
        [_videoDevice setExposureModeCustomWithDuration:[_videoDevice exposureDuration] ISO:60 completionHandler:nil];
        [_videoDevice setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
        _modeLabel.textColor = [UIColor whiteColor];
        [self displayModeMessage:@"Q"];
    }
    else if( modeCurrent == 2 ){
        [_videoDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
        [_videoDevice setFocusModeLockedWithLensPosition:0 completionHandler:nil];
        _modeLabel.textColor = [UIColor whiteColor];
        [self displayModeMessage:@"M"];
    }
    if( modeCurrent == 3 ){
        [_videoDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
        [_videoDevice setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
        [_videoDevice setTorchMode:AVCaptureTorchModeOn];
        _modeLabel.textColor = [UIColor whiteColor];
        [self displayModeMessage:@"F"];
    }
    else{
        if(_videoDevice.torchAvailable)
            [_videoDevice setTorchMode:AVCaptureTorchModeOff];
    }
}

-(void)audioPlayer: (NSString *)filename;
{
	NSString *resourcePath = [[NSBundle mainBundle] resourcePath];
	resourcePath = [resourcePath stringByAppendingString: [NSString stringWithFormat:@"/%@", filename] ];
	NSError* err;
	audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL: [NSURL fileURLWithPath:resourcePath] error:&err];
	
	audioPlayer.volume = 0.5;
	audioPlayer.numberOfLoops = 0;
	audioPlayer.currentTime = 0;
	
	if(err)	{ NSLog(@"%@",err); }
	else	{
		[audioPlayer prepareToPlay];
		[audioPlayer play];
	}
}
-(void)apiContact:(NSString*)source :(NSString*)method :(NSString*)term :(NSString*)value
{
	NSString *post = [NSString stringWithFormat:@"values={\"term\":\"%@\",\"value\":\"%@\"}",term,value];
	NSData *postData = [post dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
	
	NSString *postLength = [NSString stringWithFormat:@"%lu", (unsigned long)[postData length]];
	
	NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
	[request setURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://api.xxiivv.com/%@/%@",source,method]]];
	[request setHTTPMethod:@"POST"];
	[request setValue:postLength forHTTPHeaderField:@"Content-Length"];
	[request setValue:@"application/x-www-form-urlencoded;charset=UTF-8" forHTTPHeaderField:@"Content-Type"];
	[request setHTTPBody:postData];
	
	NSURLResponse *response;
	NSData *POSTReply = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:nil];
	NSString *theReply = [[NSString alloc] initWithBytes:[POSTReply bytes] length:[POSTReply length] encoding: NSASCIIStringEncoding];
	NSLog(@"& API  | %@: %@",method, theReply);
	
	return;
}



@end

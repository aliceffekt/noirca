/*
     File: AVCamViewController.h
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

#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import "GPUImage.h"
#import "NoirFilter.h"
#import "NoirSharpFilter.h"
#import "ScreenAspectRatioCropFilter.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import "MWPhotoBrowser.h"

@interface AVCamViewController : UIViewController <MWPhotoBrowserDelegate> {
    GPUImageStillCamera* stillCamera;
    GPUImageFilter* inputFilter;
    GPUImageFilter* sharpOutputFilter;
    GPUImageFilter* noirOutputFilter;
    BOOL capturing;
    
    CGRect screen;
    NSTimer *blink;
    NSTimer *checkLooper;
    int isRendering;
    int isAuthorized;
    int isReady;
    int isPressed;
    int modeCurrent;
    CGPoint startPoint;
    CGPoint movedPoint;
    AVAudioPlayer * audioPlayer;
    dispatch_queue_t queue;
    
    ALAssetsLibrary * assetLibrary;
    NSMutableArray *assets;
    float tileSize;
    
    // Hold Trigger Timer
    NSTimer *longPressTimer;
    
    NSString *modeLens;
    
    // Photos in library
    // use in case to process a filter over them
    NSMutableArray *photos;
    NSMutableArray *thumbs;
}
@property (strong, nonatomic) IBOutlet UIImageView *previewThing;
@property (strong, nonatomic) IBOutlet UIView *gridView;
@property (strong, nonatomic) IBOutlet UIView *centerVerticalGrid;
@property (strong, nonatomic) IBOutlet UIView *centerHorizontalGrid;

@property (strong, nonatomic) IBOutlet UIView *centerVerticalGridSecondary1;
@property (strong, nonatomic) IBOutlet UIView *centerVerticalGridSecondary2;
@property (strong, nonatomic) IBOutlet UIView *centerHorizontalGridSecondary1;
@property (strong, nonatomic) IBOutlet UIView *centerHorizontalGridSecondary2;

@property (strong, nonatomic) IBOutlet UIView *blackScreenView;

@property (strong, nonatomic) IBOutlet UIButton *modeButton;
@property (strong, nonatomic) IBOutlet UILabel *modeLabel;
@property (strong, nonatomic) IBOutlet UIView *focusView;

@property (strong, nonatomic) IBOutlet UILabel *isoLabel;
@property (strong, nonatomic) IBOutlet UILabel *focusLabel;
@property (strong, nonatomic) IBOutlet UILabel *isoTextLabel;
@property (strong, nonatomic) IBOutlet UILabel *focusTextLabel;
@property (weak, nonatomic) IBOutlet UILabel *rollLabel;
@property (weak, nonatomic) IBOutlet UILabel *rollTextLabel;
@property (weak, nonatomic) IBOutlet UILabel *modeTextLabel;

@property (strong, nonatomic) IBOutlet UIView *loadingIndicator;
@property (strong, nonatomic) IBOutlet UIView *touchIndicatorX;
@property (strong, nonatomic) IBOutlet UIView *touchIndicatorY;
@property (weak, nonatomic) IBOutlet UIButton *imageSelectionButton;

- (IBAction)modeButton:(id)sender;
- (IBAction)imageSelectButton:(id)sender;

@end







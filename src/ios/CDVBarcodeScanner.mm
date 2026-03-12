/*
 * PhoneGap is available under *either* the terms of the modified BSD license *or* the
 * MIT License (2008). See http://opensource.org/licenses/alphabetical for full text.
 *
 * Copyright 2011 Matt Kane. All rights reserved.
 * Copyright (c) 2011, IBM Corporation
 */

#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <Cordova/CDVPlugin.h>


//------------------------------------------------------------------------------
// Delegate to handle orientation functions
//------------------------------------------------------------------------------
@protocol CDVBarcodeScannerOrientationDelegate <NSObject>

- (NSUInteger)supportedInterfaceOrientations;
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;
- (BOOL)shouldAutorotate;

@end

//------------------------------------------------------------------------------
// Adds a shutter button to the UI, and changes the scan from continuous to
// only performing a scan when you click the shutter button.  For testing.
//------------------------------------------------------------------------------
#define USE_SHUTTER 0

//------------------------------------------------------------------------------
@class CDVbcsProcessor;
@class CDVbcsViewController;

//------------------------------------------------------------------------------
// plugin class
//------------------------------------------------------------------------------
@interface CDVBarcodeScanner : CDVPlugin {}
- (NSString*)isScanNotPossible;
- (void)scan:(CDVInvokedUrlCommand*)command;
- (void)encode:(CDVInvokedUrlCommand*)command;
- (void)returnImage:(NSString*)filePath format:(NSString*)format callback:(NSString*)callback;
- (void)returnSuccess:(NSString*)scannedText format:(NSString*)format cancelled:(BOOL)cancelled flipped:(BOOL)flipped callback:(NSString*)callback;
- (void)returnError:(NSString*)message callback:(NSString*)callback;
@end

//------------------------------------------------------------------------------
// class that does the grunt work
//------------------------------------------------------------------------------
@interface CDVbcsProcessor : NSObject <AVCaptureMetadataOutputObjectsDelegate> {}
@property (nonatomic, retain) CDVBarcodeScanner*           plugin;
@property (nonatomic, retain) NSString*                   callback;
@property (nonatomic, retain) UIViewController*           parentViewController;
@property (nonatomic, retain) CDVbcsViewController*        viewController;
@property (nonatomic, retain) AVCaptureSession*           captureSession;
@property (nonatomic, retain) AVCaptureVideoPreviewLayer* previewLayer;
@property (nonatomic, retain) NSString*                   alternateXib;
@property (nonatomic, retain) NSMutableArray*             results;
@property (nonatomic, retain) NSString*                   formats;
@property (nonatomic)         BOOL                        is1D;
@property (nonatomic)         BOOL                        is2D;
@property (nonatomic)         BOOL                        capturing;
@property (nonatomic)         BOOL                        isFrontCamera;
@property (nonatomic)         BOOL                        isShowFlipCameraButton;
@property (nonatomic)         BOOL                        isShowTorchButton;
@property (nonatomic)         BOOL                        isFlipped;
@property (nonatomic)         BOOL                        isTransitionAnimated;
@property (nonatomic)         BOOL                        isSuccessBeepEnabled;
@property (nonatomic)         BOOL                        isSuccess;
@property (nonatomic)         BOOL                        isCancelled;
@property (nonatomic, retain) NSString*                   reticleStyle;  // "square", "rectangle", or "auto"


- (id)initWithPlugin:(CDVBarcodeScanner*)plugin callback:(NSString*)callback parentViewController:(UIViewController*)parentViewController alterateOverlayXib:(NSString *)alternateXib;
- (void)scanBarcode;
- (void)barcodeScanSucceeded:(NSString*)text format:(NSString*)format;
- (void)barcodeScanFailed:(NSString*)message;
- (void)barcodeScanCancelled;
- (void)openDialog;
- (NSString*)setUpCaptureSession;
- (void)captureOutput:(AVCaptureOutput*)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection*)connection;
@end

//------------------------------------------------------------------------------
// Qr encoder processor
//------------------------------------------------------------------------------
@interface CDVqrProcessor: NSObject
@property (nonatomic, retain) CDVBarcodeScanner*          plugin;
@property (nonatomic, retain) NSString*                   callback;
@property (nonatomic, retain) NSString*                   stringToEncode;
@property                     NSInteger                   size;

- (id)initWithPlugin:(CDVBarcodeScanner*)plugin callback:(NSString*)callback stringToEncode:(NSString*)stringToEncode;
- (void)generateImage;
@end

//------------------------------------------------------------------------------
// view controller for the ui
//------------------------------------------------------------------------------
@interface CDVbcsViewController : UIViewController <CDVBarcodeScannerOrientationDelegate> {}
@property (nonatomic, retain) CDVbcsProcessor*  processor;
@property (nonatomic, retain) NSString*        alternateXib;
@property (nonatomic)         BOOL             shutterPressed;
@property (nonatomic, retain) IBOutlet UIView* overlayView;
@property (nonatomic, retain) UIToolbar * toolbar;
@property (nonatomic, retain) UIView * reticleView;
// unsafe_unretained is equivalent to assign - used to prevent retain cycles in the property below
@property (nonatomic, unsafe_unretained) id orientationDelegate;

- (id)initWithProcessor:(CDVbcsProcessor*)processor alternateOverlay:(NSString *)alternateXib;
- (void)startCapturing;
- (UIView*)buildOverlayView;
- (UIImage*)buildReticleImage;
- (void)shutterButtonPressed;
- (IBAction)cancelButtonPressed:(id)sender;
- (IBAction)flipCameraButtonPressed:(id)sender;
- (IBAction)torchButtonPressed:(id)sender;

@end

//------------------------------------------------------------------------------
// plugin class
//------------------------------------------------------------------------------
@implementation CDVBarcodeScanner

//--------------------------------------------------------------------------
- (NSString*)isScanNotPossible {
    NSString* result = nil;

    Class aClass = NSClassFromString(@"AVCaptureSession");
    if (aClass == nil) {
        return @"AVFoundation Framework not available";
    }

    return result;
}

-(BOOL)notHasPermission
{
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    return (authStatus == AVAuthorizationStatusDenied ||
            authStatus == AVAuthorizationStatusRestricted);
}

-(BOOL)isUsageDescriptionSet
{
  NSDictionary * plist = [[NSBundle mainBundle] infoDictionary];
  if ([plist objectForKey:@"NSCameraUsageDescription" ] ||
      [[NSBundle mainBundle] localizedStringForKey: @"NSCameraUsageDescription" value: nil table: @"InfoPlist"]) {
    return YES;
  }
  return NO;
}



//--------------------------------------------------------------------------
- (void)scan:(CDVInvokedUrlCommand*)command {
    CDVbcsProcessor* processor;
    NSString*       callback;
    NSString*       capabilityError;

    callback = command.callbackId;

    NSDictionary* options;
    if (command.arguments.count == 0) {
      options = [NSDictionary dictionary];
    } else {
      options = command.arguments[0];
    }

    BOOL preferFrontCamera = [options[@"preferFrontCamera"] boolValue];
    BOOL showFlipCameraButton = [options[@"showFlipCameraButton"] boolValue];
    BOOL showTorchButton = [options[@"showTorchButton"] boolValue];
    BOOL disableAnimations = [options[@"disableAnimations"] boolValue];
    BOOL disableSuccessBeep = [options[@"disableSuccessBeep"] boolValue];

    // We allow the user to define an alternate xib file for loading the overlay.
    NSString *overlayXib = options[@"overlayXib"];

    capabilityError = [self isScanNotPossible];
    if (capabilityError) {
        [self returnError:capabilityError callback:callback];
        return;
    } else if ([self notHasPermission]) {
        NSString * error = NSLocalizedString(@"Access to the camera has been prohibited; please enable it in the Settings app to continue.",nil);
        [self returnError:error callback:callback];
        return;
    } else if (![self isUsageDescriptionSet]) {
      NSString * error = NSLocalizedString(@"NSCameraUsageDescription is not set in the info.plist", nil);
      [self returnError:error callback:callback];
      return;
    }

    processor = [[CDVbcsProcessor alloc]
                initWithPlugin:self
                      callback:callback
          parentViewController:self.viewController
            alterateOverlayXib:overlayXib
            ];
    // queue [processor scanBarcode] to run on the event loop

    if (preferFrontCamera) {
      processor.isFrontCamera = true;
    }

    if (showFlipCameraButton) {
      processor.isShowFlipCameraButton = true;
    }

    if (showTorchButton) {
      processor.isShowTorchButton = true;
    }

    processor.isSuccessBeepEnabled = !disableSuccessBeep;

    processor.isTransitionAnimated = !disableAnimations;

    processor.formats = options[@"formats"];

    // Parse reticle style: "square", "rectangle", or "auto" (default)
    // "auto" will use square for 2D-only formats, rectangle for 1D or mixed
    NSString* reticleStyle = options[@"reticleStyle"];
    if (reticleStyle && [reticleStyle length] > 0) {
        processor.reticleStyle = reticleStyle;
    } else {
        processor.reticleStyle = @"auto";  // Default to auto-detect based on formats
    }

    [processor performSelector:@selector(scanBarcode) withObject:nil afterDelay:0];
}

//--------------------------------------------------------------------------
- (void)encode:(CDVInvokedUrlCommand*)command {
    if([command.arguments count] < 1)
        [self returnError:@"Too few arguments!" callback:command.callbackId];

    CDVqrProcessor* processor;
    NSString*       callback;
    callback = command.callbackId;

    processor = [[CDVqrProcessor alloc]
                 initWithPlugin:self
                 callback:callback
                 stringToEncode: command.arguments[0][@"data"]
                 ];
    // queue [processor generateImage] to run on the event loop
    [processor performSelector:@selector(generateImage) withObject:nil afterDelay:0];
}

- (void)returnImage:(NSString*)filePath format:(NSString*)format callback:(NSString*)callback{
    NSMutableDictionary* resultDict = [[NSMutableDictionary alloc] init];
    resultDict[@"format"] = format;
    resultDict[@"file"] = filePath;

    CDVPluginResult* result = [CDVPluginResult
                               resultWithStatus: CDVCommandStatus_OK
                               messageAsDictionary:resultDict
                               ];

    [[self commandDelegate] sendPluginResult:result callbackId:callback];
}

//--------------------------------------------------------------------------
- (void)returnSuccess:(NSString*)scannedText format:(NSString*)format cancelled:(BOOL)cancelled flipped:(BOOL)flipped callback:(NSString*)callback{
    NSLog(@"[BarcodeScanner] returnSuccess called");
    NSLog(@"[BarcodeScanner] scannedText: %@", scannedText);
    NSLog(@"[BarcodeScanner] format: %@", format);
    NSLog(@"[BarcodeScanner] cancelled: %d", cancelled);
    NSLog(@"[BarcodeScanner] callback: %@", callback);
    NSLog(@"[BarcodeScanner] commandDelegate: %@", self.commandDelegate);

    NSNumber* cancelledNumber = @(cancelled ? 1 : 0);

    NSMutableDictionary* resultDict = [NSMutableDictionary new];
    resultDict[@"text"] = scannedText;
    resultDict[@"format"] = format;
    resultDict[@"cancelled"] = cancelledNumber;

    NSLog(@"[BarcodeScanner] resultDict: %@", resultDict);

    CDVPluginResult* result = [CDVPluginResult
                               resultWithStatus: CDVCommandStatus_OK
                               messageAsDictionary: resultDict
                               ];

    NSLog(@"[BarcodeScanner] Sending plugin result to callback %@", callback);
    [self.commandDelegate sendPluginResult:result callbackId:callback];
    NSLog(@"[BarcodeScanner] Plugin result sent!");
}

//--------------------------------------------------------------------------
- (void)returnError:(NSString*)message callback:(NSString*)callback {
    CDVPluginResult* result = [CDVPluginResult
                               resultWithStatus: CDVCommandStatus_ERROR
                               messageAsString: message
                               ];

    [self.commandDelegate sendPluginResult:result callbackId:callback];
}

@end

//------------------------------------------------------------------------------
// class that does the grunt work
//------------------------------------------------------------------------------
@implementation CDVbcsProcessor

@synthesize plugin               = _plugin;
@synthesize callback             = _callback;
@synthesize parentViewController = _parentViewController;
@synthesize viewController       = _viewController;
@synthesize captureSession       = _captureSession;
@synthesize previewLayer         = _previewLayer;
@synthesize alternateXib         = _alternateXib;
@synthesize is1D                 = _is1D;
@synthesize is2D                 = _is2D;
@synthesize capturing            = _capturing;
@synthesize results              = _results;

SystemSoundID _soundFileObject;

//--------------------------------------------------------------------------
- (id)initWithPlugin:(CDVBarcodeScanner*)plugin
            callback:(NSString*)callback
parentViewController:(UIViewController*)parentViewController
  alterateOverlayXib:(NSString *)alternateXib {
    self = [super init];
    if (!self) return self;

    self.plugin               = plugin;
    self.callback             = callback;
    self.parentViewController = parentViewController;
    self.alternateXib         = alternateXib;

    self.is1D      = YES;
    self.is2D      = YES;
    self.capturing = NO;
    self.results = [NSMutableArray new];

    CFURLRef soundFileURLRef  = CFBundleCopyResourceURL(CFBundleGetMainBundle(), CFSTR("CDVBarcodeScanner.bundle/beep"), CFSTR ("caf"), NULL);
    AudioServicesCreateSystemSoundID(soundFileURLRef, &_soundFileObject);

    return self;
}

//--------------------------------------------------------------------------
- (void)dealloc {
    self.plugin = nil;
    self.callback = nil;
    self.parentViewController = nil;
    self.viewController = nil;
    self.captureSession = nil;
    self.previewLayer = nil;
    self.alternateXib = nil;
    self.results = nil;

    self.capturing = NO;

    AudioServicesRemoveSystemSoundCompletion(_soundFileObject);
    AudioServicesDisposeSystemSoundID(_soundFileObject);
}

//--------------------------------------------------------------------------
- (void)scanBarcode {

//    self.captureSession = nil;
//    self.previewLayer = nil;
    NSString* errorMessage = [self setUpCaptureSession];
    if (errorMessage) {
        [self barcodeScanFailed:errorMessage];
        return;
    }

    self.viewController = [[CDVbcsViewController alloc] initWithProcessor: self alternateOverlay:self.alternateXib];
    // here we set the orientation delegate to the MainViewController of the app (orientation controlled in the Project Settings)
    self.viewController.orientationDelegate = self.plugin.viewController;

    // delayed [self openDialog];
    [self performSelector:@selector(openDialog) withObject:nil afterDelay:1];
}

//--------------------------------------------------------------------------
- (void)openDialog {
    if (@available(iOS 13.0, *)) {
        [self.viewController setModalPresentationStyle:UIModalPresentationFullScreen];
    }
    [self.parentViewController
     presentViewController:self.viewController
     animated:self.isTransitionAnimated completion:nil
     ];
}

//--------------------------------------------------------------------------
- (void)barcodeScanDone:(void (^)(void))callbackBlock {
    NSLog(@"[BarcodeScanner] barcodeScanDone called");
    self.capturing = NO;
    [self.captureSession stopRunning];

    // Cleanup camera
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    [device lockForConfiguration:nil];
    if([device isAutoFocusRangeRestrictionSupported]) {
        [device setAutoFocusRangeRestriction:AVCaptureAutoFocusRangeRestrictionNone];
    }
    [device unlockForConfiguration];

    // Optional callback (for flipCamera)
    void (^savedCallback)(void) = callbackBlock ? [callbackBlock copy] : nil;

    // Dismiss the scanner view
    __weak typeof(self) weakSelf = self;
    NSLog(@"[BarcodeScanner] Dismissing view controller...");
    [self.parentViewController dismissViewControllerAnimated:self.isTransitionAnimated completion:^{
        NSLog(@"[BarcodeScanner] View controller dismissed");
        if (savedCallback) {
            savedCallback();
        }
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            strongSelf.viewController = nil;
        }
    }];
}

//--------------------------------------------------------------------------
- (BOOL)checkResult:(NSString *)result {
    [self.results addObject:result];

    // Reduced threshold for faster scanning (was 7, now 3)
    NSInteger treshold = 3;

    if (self.results.count > treshold) {
        [self.results removeObjectAtIndex:0];
    }

    if (self.results.count < treshold)
    {
        return NO;
    }

    BOOL allEqual = YES;
    NSString *compareString = self.results[0];

    for (NSString *aResult in self.results)
    {
        if (![compareString isEqualToString:aResult])
        {
            allEqual = NO;
            //NSLog(@"Did not fit: %@",self.results);
            break;
        }
    }

    return allEqual;
}

//--------------------------------------------------------------------------
// Helper to check if string contains binary/non-printable characters
- (BOOL)containsBinaryData:(NSString*)text {
    if (!text || text.length == 0) return NO;

    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        // Check for control characters (except common whitespace)
        if (c < 32 && c != '\n' && c != '\r' && c != '\t') {
            return YES;
        }
        // Check for DEL and other non-printable
        if (c == 127) {
            return YES;
        }
    }
    return NO;
}

//--------------------------------------------------------------------------
- (void)barcodeScanSucceeded:(NSString*)text format:(NSString*)format {
    NSLog(@"[BarcodeScanner] barcodeScanSucceeded called - text length: %lu, format: %@", (unsigned long)text.length, format);
    NSLog(@"[BarcodeScanner] self.plugin: %@, self.callback: %@", self.plugin, self.callback);

    // Store values for callback - capture everything we need NOW before any async operations
    CDVBarcodeScanner* plugin = self.plugin;
    NSString* callbackId = self.callback;

    if (!plugin || !callbackId) {
        NSLog(@"[BarcodeScanner] ERROR: plugin or callback is nil!");
        return;
    }

    // Check for binary data and encode if needed
    NSString* safeText = text;
    BOOL isBinary = [self containsBinaryData:text];

    if (isBinary) {
        NSLog(@"[BarcodeScanner] Binary data detected, base64 encoding...");
        NSData* textData = [text dataUsingEncoding:NSUTF8StringEncoding];
        if (!textData) {
            // If UTF8 fails, try Latin1
            textData = [text dataUsingEncoding:NSISOLatin1StringEncoding];
        }
        if (textData) {
            safeText = [NSString stringWithFormat:@"BASE64:%@", [textData base64EncodedStringWithOptions:0]];
            NSLog(@"[BarcodeScanner] Encoded to: %@", [safeText substringToIndex:MIN(100, safeText.length)]);
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"[BarcodeScanner] On main queue, playing beep...");
        self.isSuccess = true;
        if (self.isSuccessBeepEnabled) {
            AudioServicesPlaySystemSound(_soundFileObject);
        }

        // Call plugin callback DIRECTLY here, before dismiss
        NSLog(@"[BarcodeScanner] Calling returnSuccess directly...");
        [plugin returnSuccess:safeText format:format cancelled:FALSE flipped:FALSE callback:callbackId];
        NSLog(@"[BarcodeScanner] returnSuccess called, now dismissing...");

        [self barcodeScanDone:nil];
    });
}

//--------------------------------------------------------------------------
- (void)barcodeScanFailed:(NSString*)message {
    NSLog(@"[BarcodeScanner] barcodeScanFailed: %@", message);

    CDVBarcodeScanner* plugin = self.plugin;
    NSString* callbackId = self.callback;

    dispatch_block_t block = ^{
        NSLog(@"[BarcodeScanner] Calling returnError...");
        [plugin returnError:message callback:callbackId];
        [self barcodeScanDone:nil];
    };
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

//--------------------------------------------------------------------------
- (void)barcodeScanCancelled {
    NSLog(@"[BarcodeScanner] barcodeScanCancelled called");

    // Store values for callback
    CDVBarcodeScanner* plugin = self.plugin;
    NSString* callbackId = self.callback;
    BOOL wasFlipped = self.isFlipped;

    if (self.isFlipped) {
        self.isFlipped = NO;
    }

    // Call callback DIRECTLY before dismiss
    NSLog(@"[BarcodeScanner] Calling returnSuccess for cancel...");
    [plugin returnSuccess:@"" format:@"" cancelled:TRUE flipped:wasFlipped callback:callbackId];
    NSLog(@"[BarcodeScanner] returnSuccess called for cancel");

    [self barcodeScanDone:nil];
}

- (void)flipCamera {
    self.isFlipped = YES;
    self.isFrontCamera = !self.isFrontCamera;
    [self barcodeScanDone:^{
        if (self.isFlipped) {
            self.isFlipped = NO;
        }
    [self performSelector:@selector(scanBarcode) withObject:nil afterDelay:0.1];
    }];
}

- (void)toggleTorch {
  AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
  [device lockForConfiguration:nil];
  if (device.flashActive) {
    [device setTorchMode:AVCaptureTorchModeOff];
    [device setFlashMode:AVCaptureFlashModeOff];
  } else {
    [device setTorchModeOnWithLevel:AVCaptureMaxAvailableTorchLevel error:nil];
    [device setFlashMode:AVCaptureFlashModeOn];
  }
  [device unlockForConfiguration];
}

//--------------------------------------------------------------------------
- (NSString*)setUpCaptureSession {
    NSError* error = nil;

    AVCaptureSession* captureSession = [[AVCaptureSession alloc] init];
    self.captureSession = captureSession;

    AVCaptureDevice* device = nil;

    if (self.isFrontCamera) {
        // Use discovery session for front camera (modern API)
        AVCaptureDeviceDiscoverySession *discoverySession = [AVCaptureDeviceDiscoverySession
            discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera]
            mediaType:AVMediaTypeVideo
            position:AVCaptureDevicePositionFront];
        NSArray *devices = discoverySession.devices;
        if (devices.count > 0) {
            device = devices.firstObject;
        }
    } else {
        // For back camera on iPhone 14/15/16 Pro and similar devices:
        // Use virtual camera devices that support automatic macro mode switching
        // Priority: TripleCamera > DualWideCamera > WideAngleCamera
        // Virtual devices automatically switch to ultra-wide for close focus (macro)

        // Try TripleCamera first (iPhone Pro models)
        AVCaptureDeviceDiscoverySession *tripleDiscovery = [AVCaptureDeviceDiscoverySession
            discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInTripleCamera]
            mediaType:AVMediaTypeVideo
            position:AVCaptureDevicePositionBack];
        if (tripleDiscovery.devices.count > 0) {
            device = tripleDiscovery.devices.firstObject;
            NSLog(@"[BarcodeScanner] Using TripleCamera (macro supported)");
        }

        // Try DualWideCamera (iPhone 13+ non-Pro)
        if (!device) {
            AVCaptureDeviceDiscoverySession *dualWideDiscovery = [AVCaptureDeviceDiscoverySession
                discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInDualWideCamera]
                mediaType:AVMediaTypeVideo
                position:AVCaptureDevicePositionBack];
            if (dualWideDiscovery.devices.count > 0) {
                device = dualWideDiscovery.devices.firstObject;
                NSLog(@"[BarcodeScanner] Using DualWideCamera (macro supported)");
            }
        }

        // Fallback to standard wide-angle camera
        if (!device) {
            AVCaptureDeviceDiscoverySession *wideDiscovery = [AVCaptureDeviceDiscoverySession
                discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera]
                mediaType:AVMediaTypeVideo
                position:AVCaptureDevicePositionBack];
            if (wideDiscovery.devices.count > 0) {
                device = wideDiscovery.devices.firstObject;
                NSLog(@"[BarcodeScanner] Using WideAngleCamera (fallback)");
            }
        }

        // Last resort fallback
        if (!device) {
            device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
            NSLog(@"[BarcodeScanner] Using default camera (last fallback)");
        }
    }

    if (!device) return @"unable to obtain video capture device";

    NSLog(@"[BarcodeScanner] Camera selected: %@", device.localizedName);
    NSLog(@"[BarcodeScanner] Device type: %@", device.deviceType);

    // set focus params if available to improve focusing
    [device lockForConfiguration:&error];
    if (error == nil) {
        // Enable continuous autofocus
        if([device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
            [device setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
            NSLog(@"[BarcodeScanner] Enabled continuous autofocus");
        }

        // Don't restrict focus range - PDF417 and other document barcodes need full range
        if([device isAutoFocusRangeRestrictionSupported]) {
            [device setAutoFocusRangeRestriction:AVCaptureAutoFocusRangeRestrictionNone];
            NSLog(@"[BarcodeScanner] Set autofocus range to None (full range)");
        }

        // Enable smooth autofocus for better tracking
        if([device isSmoothAutoFocusSupported]) {
            [device setSmoothAutoFocusEnabled:YES];
        }

        // For virtual devices (Triple/DualWide), enable automatic camera switching for macro
        if (@available(iOS 15.4, *)) {
            if ([device respondsToSelector:@selector(setAutomaticallyAdjustsFaceDrivenAutoFocusEnabled:)]) {
                // Disable face-driven focus for barcode scanning
                device.automaticallyAdjustsFaceDrivenAutoFocusEnabled = NO;
            }
        }

        // Set focus point to center initially
        if ([device isFocusPointOfInterestSupported]) {
            device.focusPointOfInterest = CGPointMake(0.5, 0.5);
            NSLog(@"[BarcodeScanner] Set focus point to center");
        }

        // Enable auto exposure
        if ([device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
            device.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
        }

        // Log focus capabilities
        NSLog(@"[BarcodeScanner] Min focus distance: %f", device.minimumFocusDistance);
        NSLog(@"[BarcodeScanner] Zoom factor range: %f - %f", device.minAvailableVideoZoomFactor, device.maxAvailableVideoZoomFactor);
    }
    [device unlockForConfiguration];

    AVCaptureDeviceInput* input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (!input) return @"unable to obtain video capture device input";

    AVCaptureMetadataOutput* output = [[AVCaptureMetadataOutput alloc] init];
    if (!output) return @"unable to obtain video capture output";

    [output setMetadataObjectsDelegate:self queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0)];

    // Use 1920x1080 resolution for better barcode detection (avoid Photo preset which causes blur)
    if ([captureSession canSetSessionPreset:AVCaptureSessionPreset1920x1080]) {
        captureSession.sessionPreset = AVCaptureSessionPreset1920x1080;
        NSLog(@"[BarcodeScanner] Using 1920x1080 preset");
    } else if ([captureSession canSetSessionPreset:AVCaptureSessionPresetHigh]) {
        captureSession.sessionPreset = AVCaptureSessionPresetHigh;
    } else if ([captureSession canSetSessionPreset:AVCaptureSessionPresetMedium]) {
        captureSession.sessionPreset = AVCaptureSessionPresetMedium;
    } else {
        return @"unable to preset high nor medium quality video capture";
    }

    if ([captureSession canAddInput:input]) {
        [captureSession addInput:input];
    }
    else {
        return @"unable to add video capture device input to session";
    }

    if ([captureSession canAddOutput:output]) {
        [captureSession addOutput:output];
    }
    else {
        return @"unable to add video capture output to session";
    }

    [output setMetadataObjectTypes:[self formatObjectTypes]];

    // Apply initial zoom for back camera to help with minimum focus distance
    // This gives more barcode pixels for the decoder on newer iPhones
    if (!self.isFrontCamera) {
        [device lockForConfiguration:nil];
        CGFloat targetZoom = 1.5; // 1.5x zoom helps with focus distance compensation
        if (targetZoom <= device.maxAvailableVideoZoomFactor && targetZoom >= device.minAvailableVideoZoomFactor) {
            device.videoZoomFactor = targetZoom;
            NSLog(@"[BarcodeScanner] Set initial zoom to %f", targetZoom);
        }
        [device unlockForConfiguration];
    }

    // setup capture preview layer
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:captureSession];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;

    // run on next event loop pass [captureSession startRunning]
    [captureSession performSelector:@selector(startRunning) withObject:nil afterDelay:0];

    return nil;
}

//--------------------------------------------------------------------------
// this method gets sent the captured frames
//--------------------------------------------------------------------------
- (void)captureOutput:(AVCaptureOutput*)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects fromConnection:(AVCaptureConnection*)connection {

    if (!self.capturing) return;

#if USE_SHUTTER
    if (!self.viewController.shutterPressed) return;
    self.viewController.shutterPressed = NO;

    UIView* flashView = [[UIView alloc] initWithFrame:self.viewController.view.frame];
    [flashView setBackgroundColor:[UIColor whiteColor]];
    [self.viewController.view.window addSubview:flashView];

    [UIView
     animateWithDuration:.4f
     animations:^{
         [flashView setAlpha:0.f];
     }
     completion:^(BOOL finished){
         [flashView removeFromSuperview];
     }
     ];
#endif


    try {
        // This will bring in multiple entities if there are multiple 2D codes in frame.
        for (AVMetadataObject *metaData in metadataObjects) {
            AVMetadataMachineReadableCodeObject* code = (AVMetadataMachineReadableCodeObject*)[self.previewLayer transformedMetadataObjectForMetadataObject:(AVMetadataMachineReadableCodeObject*)metaData];

            if ([self checkResult:code.stringValue]) {
                [self barcodeScanSucceeded:code.stringValue format:[self formatStringFromMetadata:code]];
            }
        }
    }
    catch (...) {
        //            NSLog(@"decoding: unknown exception");
        //            [self barcodeScanFailed:@"unknown exception decoding barcode"];
    }

    //        NSTimeInterval timeElapsed  = [NSDate timeIntervalSinceReferenceDate] - timeStart;
    //        NSLog(@"decoding completed in %dms", (int) (timeElapsed * 1000));

}

//--------------------------------------------------------------------------
// convert metadata object information to barcode format string
//--------------------------------------------------------------------------
- (NSString*)formatStringFromMetadata:(AVMetadataMachineReadableCodeObject*)format {
    if (format.type == AVMetadataObjectTypeQRCode)          return @"QR_CODE";
    if (format.type == AVMetadataObjectTypeAztecCode)       return @"AZTEC";
    if (format.type == AVMetadataObjectTypeDataMatrixCode)  return @"DATA_MATRIX";
    if (format.type == AVMetadataObjectTypeUPCECode)        return @"UPC_E";
    // According to Apple documentation, UPC_A is EAN13 with a leading 0.
    if (format.type == AVMetadataObjectTypeEAN13Code && [format.stringValue characterAtIndex:0] == '0') return @"UPC_A";
    if (format.type == AVMetadataObjectTypeEAN8Code)        return @"EAN_8";
    if (format.type == AVMetadataObjectTypeEAN13Code)       return @"EAN_13";
    if (format.type == AVMetadataObjectTypeCode128Code)     return @"CODE_128";
    if (format.type == AVMetadataObjectTypeCode93Code)      return @"CODE_93";
    if (format.type == AVMetadataObjectTypeCode39Code)      return @"CODE_39";
    if (format.type == AVMetadataObjectTypeInterleaved2of5Code) return @"ITF";
    if (format.type == AVMetadataObjectTypeITF14Code)          return @"ITF_14";

    if (format.type == AVMetadataObjectTypePDF417Code)      return @"PDF_417";
    return @"???";
}

//--------------------------------------------------------------------------
// convert string formats to metadata objects
//--------------------------------------------------------------------------
- (NSArray*) formatObjectTypes {
    NSArray *supportedFormats = nil;
    if (self.formats != nil) {
        supportedFormats = [self.formats componentsSeparatedByString:@","];
    }

    NSMutableArray * formatObjectTypes = [NSMutableArray array];

    if (self.formats == nil || [supportedFormats containsObject:@"QR_CODE"]) [formatObjectTypes addObject:AVMetadataObjectTypeQRCode];
    if (self.formats == nil || [supportedFormats containsObject:@"AZTEC"]) [formatObjectTypes addObject:AVMetadataObjectTypeAztecCode];
    if (self.formats == nil || [supportedFormats containsObject:@"DATA_MATRIX"]) [formatObjectTypes addObject:AVMetadataObjectTypeDataMatrixCode];
    if (self.formats == nil || [supportedFormats containsObject:@"UPC_E"]) [formatObjectTypes addObject:AVMetadataObjectTypeUPCECode];
    if (self.formats == nil || [supportedFormats containsObject:@"EAN_8"]) [formatObjectTypes addObject:AVMetadataObjectTypeEAN8Code];
    if (self.formats == nil || [supportedFormats containsObject:@"EAN_13"]) [formatObjectTypes addObject:AVMetadataObjectTypeEAN13Code];
    if (self.formats == nil || [supportedFormats containsObject:@"CODE_128"]) [formatObjectTypes addObject:AVMetadataObjectTypeCode128Code];
    if (self.formats == nil || [supportedFormats containsObject:@"CODE_93"]) [formatObjectTypes addObject:AVMetadataObjectTypeCode93Code];
    if (self.formats == nil || [supportedFormats containsObject:@"CODE_39"]) [formatObjectTypes addObject:AVMetadataObjectTypeCode39Code];
    if (self.formats == nil || [supportedFormats containsObject:@"ITF"]) [formatObjectTypes addObject:AVMetadataObjectTypeInterleaved2of5Code];
    if (self.formats == nil || [supportedFormats containsObject:@"ITF_14"]) [formatObjectTypes addObject:AVMetadataObjectTypeITF14Code];
    if (self.formats == nil || [supportedFormats containsObject:@"PDF_417"]) [formatObjectTypes addObject:AVMetadataObjectTypePDF417Code];

    return formatObjectTypes;
}

@end

//------------------------------------------------------------------------------
// qr encoder processor
//------------------------------------------------------------------------------
@implementation CDVqrProcessor
@synthesize plugin               = _plugin;
@synthesize callback             = _callback;
@synthesize stringToEncode       = _stringToEncode;
@synthesize size                 = _size;

- (id)initWithPlugin:(CDVBarcodeScanner*)plugin callback:(NSString*)callback stringToEncode:(NSString*)stringToEncode{
    self = [super init];
    if (!self) return self;

    self.plugin          = plugin;
    self.callback        = callback;
    self.stringToEncode  = stringToEncode;
    self.size            = 300;

    return self;
}

//--------------------------------------------------------------------------
- (void)dealloc {
    self.plugin = nil;
    self.callback = nil;
    self.stringToEncode = nil;
}
//--------------------------------------------------------------------------
- (void)generateImage{
    /* setup qr filter */
    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [filter setDefaults];

    /* set filter's input message
     * the encoding string has to be convert to a UTF-8 encoded NSData object */
    [filter setValue:[self.stringToEncode dataUsingEncoding:NSUTF8StringEncoding]
              forKey:@"inputMessage"];

    /* on ios >= 7.0  set low image error correction level */
    if (floor(NSFoundationVersionNumber) >= NSFoundationVersionNumber_iOS_7_0)
        [filter setValue:@"L" forKey:@"inputCorrectionLevel"];

    /* prepare cgImage */
    CIImage *outputImage = [filter outputImage];
    CIContext *context = [CIContext contextWithOptions:nil];
    CGImageRef cgImage = [context createCGImage:outputImage
                                       fromRect:[outputImage extent]];

    /* returned qr code image */
    UIImage *qrImage = [UIImage imageWithCGImage:cgImage
                                           scale:1.
                                     orientation:UIImageOrientationUp];
    /* resize generated image */
    CGFloat width = _size;
    CGFloat height = _size;

    UIGraphicsBeginImageContext(CGSizeMake(width, height));

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
    [qrImage drawInRect:CGRectMake(0, 0, width, height)];
    qrImage = UIGraphicsGetImageFromCurrentImageContext();

    /* clean up */
    UIGraphicsEndImageContext();
    CGImageRelease(cgImage);

    /* save image to file */
    NSString* fileName = [[[NSProcessInfo processInfo] globallyUniqueString] stringByAppendingString:@".jpg"];
    NSString* filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
    [UIImageJPEGRepresentation(qrImage, 1.0) writeToFile:filePath atomically:YES];

    /* return file path back to cordova */
    [self.plugin returnImage:filePath format:@"QR_CODE" callback: self.callback];
}
@end

//------------------------------------------------------------------------------
// view controller for the ui
//------------------------------------------------------------------------------
@implementation CDVbcsViewController
@synthesize processor      = _processor;
@synthesize shutterPressed = _shutterPressed;
@synthesize alternateXib   = _alternateXib;
@synthesize overlayView    = _overlayView;

//--------------------------------------------------------------------------
- (id)initWithProcessor:(CDVbcsProcessor*)processor alternateOverlay:(NSString *)alternateXib {
    self = [super init];
    if (!self) return self;

    self.processor = processor;
    self.shutterPressed = NO;
    self.alternateXib = alternateXib;
    self.overlayView = nil;
    return self;
}

//--------------------------------------------------------------------------
- (void)dealloc {
    self.view = nil;
    self.processor = nil;
    self.shutterPressed = NO;
    self.alternateXib = nil;
    self.overlayView = nil;
}

//--------------------------------------------------------------------------
- (void)loadView {
    self.view = [[UIView alloc] initWithFrame: self.processor.parentViewController.view.frame];
}

//--------------------------------------------------------------------------
- (void)viewWillAppear:(BOOL)animated {

    // set video orientation to what the camera sees
    self.processor.previewLayer.connection.videoOrientation = [self interfaceOrientationToVideoOrientation:[UIApplication sharedApplication].statusBarOrientation];

    // this fixes the bug when the statusbar is landscape, and the preview layer
    // starts up in portrait (not filling the whole view)
    self.processor.previewLayer.frame = self.view.bounds;
}

- (void)viewWillDisappear:(BOOL)animated{
    // Don't trigger cancel if we're flipping cameras, already cancelled, or already succeeded
    if ( !(self.processor.isCancelled) && !(self.processor.isSuccess) && !(self.processor.isFlipped) )
    {
        [self.processor performSelector:@selector(barcodeScanCancelled) withObject:nil afterDelay:0];
    }
}
//--------------------------------------------------------------------------
- (void)viewDidAppear:(BOOL)animated {
    // setup capture preview layer
    AVCaptureVideoPreviewLayer* previewLayer = self.processor.previewLayer;
    previewLayer.frame = self.view.bounds;
    previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;

    if ([previewLayer.connection isVideoOrientationSupported]) {
        previewLayer.connection.videoOrientation = [self interfaceOrientationToVideoOrientation:[UIApplication sharedApplication].statusBarOrientation];
    }

    [self.view.layer insertSublayer:previewLayer below:[[self.view.layer sublayers] objectAtIndex:0]];

    [self.view addSubview:[self buildOverlayView]];

    // Add tap gesture for tap-to-focus
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapToFocus:)];
    [self.view addGestureRecognizer:tapGesture];

    // Add pinch gesture for zoom control
    UIPinchGestureRecognizer *pinchGesture = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinchToZoom:)];
    [self.view addGestureRecognizer:pinchGesture];

    [self startCapturing];

    [super viewDidAppear:animated];
}

//--------------------------------------------------------------------------
// Tap to focus - helps with back camera focus issues
//--------------------------------------------------------------------------
- (void)handleTapToFocus:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded) return;

    CGPoint tapPoint = [gesture locationInView:self.view];
    CGPoint focusPoint = [self.processor.previewLayer captureDevicePointOfInterestForPoint:tapPoint];

    NSLog(@"[BarcodeScanner] Tap to focus at screen point: %@", NSStringFromCGPoint(tapPoint));
    NSLog(@"[BarcodeScanner] Converted to device point: %@", NSStringFromCGPoint(focusPoint));

    // Get the actual device from the capture session input
    AVCaptureDevice *device = nil;
    for (AVCaptureInput *input in self.processor.captureSession.inputs) {
        if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
            device = [(AVCaptureDeviceInput *)input device];
            break;
        }
    }

    if (!device) {
        NSLog(@"[BarcodeScanner] ERROR: Could not find capture device from session");
        return;
    }

    NSLog(@"[BarcodeScanner] Device: %@, position: %ld", device.localizedName, (long)device.position);
    NSLog(@"[BarcodeScanner] Focus POI supported: %d, Focus modes - Auto: %d, Continuous: %d, Locked: %d",
          device.isFocusPointOfInterestSupported,
          [device isFocusModeSupported:AVCaptureFocusModeAutoFocus],
          [device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus],
          [device isFocusModeSupported:AVCaptureFocusModeLocked]);

    NSError *error = nil;

    if ([device lockForConfiguration:&error]) {
        // IMPORTANT: Set focus point BEFORE changing focus mode
        if ([device isFocusPointOfInterestSupported]) {
            device.focusPointOfInterest = focusPoint;
            NSLog(@"[BarcodeScanner] Set focus point of interest");
        }

        // Use AutoFocus mode - this triggers a single focus operation at the point
        if ([device isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
            device.focusMode = AVCaptureFocusModeAutoFocus;
            NSLog(@"[BarcodeScanner] Triggered AutoFocus");
        }

        // Also adjust exposure
        if ([device isExposurePointOfInterestSupported]) {
            device.exposurePointOfInterest = focusPoint;
        }
        if ([device isExposureModeSupported:AVCaptureExposureModeAutoExpose]) {
            device.exposureMode = AVCaptureExposureModeAutoExpose;
        }

        [device unlockForConfiguration];

        // Show visual feedback
        [self showFocusIndicatorAtPoint:tapPoint];

        // After a delay, switch back to continuous autofocus for ongoing scanning
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSError *err = nil;
            if ([device lockForConfiguration:&err]) {
                if ([device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
                    device.focusMode = AVCaptureFocusModeContinuousAutoFocus;
                    NSLog(@"[BarcodeScanner] Returned to continuous autofocus");
                }
                [device unlockForConfiguration];
            }
        });
    } else {
        NSLog(@"[BarcodeScanner] Failed to lock device: %@", error);
    }
}

- (void)showFocusIndicatorAtPoint:(CGPoint)point {
    // Create focus indicator view
    UIView *focusView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 80, 80)];
    focusView.center = point;
    focusView.layer.borderColor = [UIColor yellowColor].CGColor;
    focusView.layer.borderWidth = 2.0;
    focusView.layer.cornerRadius = 40;
    focusView.backgroundColor = [UIColor clearColor];
    focusView.alpha = 0.0;

    [self.view addSubview:focusView];

    // Animate
    [UIView animateWithDuration:0.15 animations:^{
        focusView.alpha = 1.0;
        focusView.transform = CGAffineTransformMakeScale(0.7, 0.7);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.5 delay:0.5 options:0 animations:^{
            focusView.alpha = 0.0;
        } completion:^(BOOL finished) {
            [focusView removeFromSuperview];
        }];
    }];
}

//--------------------------------------------------------------------------
// Pinch to zoom - allows manual zoom control for barcode scanning
//--------------------------------------------------------------------------
static CGFloat _initialZoomFactor = 1.0;

- (void)handlePinchToZoom:(UIPinchGestureRecognizer *)gesture {
    // Get the actual device from the capture session input
    AVCaptureDevice *device = nil;
    for (AVCaptureInput *input in self.processor.captureSession.inputs) {
        if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
            device = [(AVCaptureDeviceInput *)input device];
            break;
        }
    }

    if (!device) return;

    if (gesture.state == UIGestureRecognizerStateBegan) {
        _initialZoomFactor = device.videoZoomFactor;
    }

    if (gesture.state == UIGestureRecognizerStateChanged) {
        NSError *error = nil;
        CGFloat newZoom = _initialZoomFactor * gesture.scale;

        // Clamp zoom to valid range (limit max to 5x for barcode scanning)
        CGFloat minZoom = device.minAvailableVideoZoomFactor;
        CGFloat maxZoom = MIN(device.maxAvailableVideoZoomFactor, 5.0);
        newZoom = MAX(minZoom, MIN(newZoom, maxZoom));

        if ([device lockForConfiguration:&error]) {
            device.videoZoomFactor = newZoom;
            [device unlockForConfiguration];
        }
    }

    // Show zoom level indicator
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        NSLog(@"[BarcodeScanner] Zoom level: %.1fx", device.videoZoomFactor);
    }
}

- (AVCaptureVideoOrientation)interfaceOrientationToVideoOrientation:(UIInterfaceOrientation)orientation {
    switch (orientation) {
        case UIInterfaceOrientationPortrait:
            return AVCaptureVideoOrientationPortrait;
        case UIInterfaceOrientationPortraitUpsideDown:
            return AVCaptureVideoOrientationPortraitUpsideDown;
        case UIInterfaceOrientationLandscapeLeft:
            return AVCaptureVideoOrientationLandscapeLeft;
        case UIInterfaceOrientationLandscapeRight:
            return AVCaptureVideoOrientationLandscapeRight;
        default:
            return AVCaptureVideoOrientationPortrait;
   }
}

//--------------------------------------------------------------------------
- (void)startCapturing {
    self.processor.capturing = YES;
}

//--------------------------------------------------------------------------
- (IBAction)shutterButtonPressed {
    self.shutterPressed = YES;
}

//--------------------------------------------------------------------------
- (IBAction)cancelButtonPressed:(id)sender {
    self.processor.isCancelled = true;
    [self.processor performSelector:@selector(barcodeScanCancelled) withObject:nil afterDelay:0];
}

- (IBAction)flipCameraButtonPressed:(id)sender
{
    [self.processor performSelector:@selector(flipCamera) withObject:nil afterDelay:0];
}

- (IBAction)torchButtonPressed:(id)sender
{
  [self.processor performSelector:@selector(toggleTorch) withObject:nil afterDelay:0];
}

//--------------------------------------------------------------------------
- (UIView *)buildOverlayViewFromXib
{
    [[NSBundle mainBundle] loadNibNamed:self.alternateXib owner:self options:NULL];

    if ( self.overlayView == nil )
    {
        NSLog(@"%@", @"An error occurred loading the overlay xib.  It appears that the overlayView outlet is not set.");
        return nil;
    }

	self.overlayView.autoresizesSubviews = YES;
    self.overlayView.autoresizingMask    = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.overlayView.opaque              = NO;

	CGRect bounds = self.view.bounds;
    bounds = CGRectMake(0, 0, bounds.size.width, bounds.size.height);

	[self.overlayView setFrame:bounds];

    return self.overlayView;
}

//--------------------------------------------------------------------------
- (UIView*)buildOverlayView {

    if ( nil != self.alternateXib )
    {
        return [self buildOverlayViewFromXib];
    }
    CGRect bounds = self.view.frame;
    bounds = CGRectMake(0, 0, bounds.size.width, bounds.size.height);

    UIView* overlayView = [[UIView alloc] initWithFrame:bounds];
    overlayView.autoresizesSubviews = YES;
    overlayView.autoresizingMask    = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlayView.opaque              = NO;

    self.toolbar = [[UIToolbar alloc] init];
    self.toolbar.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    id cancelButton = [[UIBarButtonItem alloc]
                       initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                       target:(id)self
                       action:@selector(cancelButtonPressed:)
                       ];


    id flexSpace = [[UIBarButtonItem alloc]
                    initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                    target:nil
                    action:nil
                    ];

    id flipCamera = [[UIBarButtonItem alloc]
                       initWithBarButtonSystemItem:UIBarButtonSystemItemCamera
                       target:(id)self
                       action:@selector(flipCameraButtonPressed:)
                       ];

    NSMutableArray *items;

#if USE_SHUTTER
    id shutterButton = [[UIBarButtonItem alloc]
                        initWithBarButtonSystemItem:UIBarButtonSystemItemCamera
                        target:(id)self
                        action:@selector(shutterButtonPressed)
                        ];

    if (_processor.isShowFlipCameraButton) {
      items = [NSMutableArray arrayWithObjects:flexSpace, cancelButton, flexSpace, flipCamera, shutterButton, nil];
    } else {
      items = [NSMutableArray arrayWithObjects:flexSpace, cancelButton, flexSpace, shutterButton, nil];
    }
#else
    if (_processor.isShowFlipCameraButton) {
      items = [@[flexSpace, cancelButton, flexSpace, flipCamera] mutableCopy];
    } else {
      items = [@[flexSpace, cancelButton, flexSpace] mutableCopy];
    }
#endif

    if (_processor.isShowTorchButton && !_processor.isFrontCamera) {
      AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
      if ([device hasTorch] && [device hasFlash]) {
        NSURL *bundleURL = [[NSBundle mainBundle] URLForResource:@"CDVBarcodeScanner" withExtension:@"bundle"];
        NSBundle *bundle = [NSBundle bundleWithURL:bundleURL];
        NSString *imagePath = [bundle pathForResource:@"torch" ofType:@"png"];
        UIImage *image = [UIImage imageWithContentsOfFile:imagePath];

        id torchButton = [[UIBarButtonItem alloc]
                           initWithImage:image
                                   style:UIBarButtonItemStylePlain
                                  target:(id)self
                                  action:@selector(torchButtonPressed:)
                           ];

      [items insertObject:torchButton atIndex:0];
    }
  }
    self.toolbar.items = items;
    [overlayView addSubview: self.toolbar];

    UIImage* reticleImage = [self buildReticleImage];
    self.reticleView = [[UIImageView alloc] initWithImage:reticleImage];

    self.reticleView.opaque           = NO;
    self.reticleView.contentMode      = UIViewContentModeScaleAspectFit;
    self.reticleView.autoresizingMask = (UIViewAutoresizing) (0
        | UIViewAutoresizingFlexibleLeftMargin
        | UIViewAutoresizingFlexibleRightMargin
        | UIViewAutoresizingFlexibleTopMargin
        | UIViewAutoresizingFlexibleBottomMargin)
    ;

    [overlayView addSubview: self.reticleView];
    [self resizeElements];
    return overlayView;
}

//--------------------------------------------------------------------------

// Reticle dimensions - configurable based on reticleStyle
#define RETICLE_SIZE_BASE    600.0f   // Base size for square reticle
#define RETICLE_LINE_WIDTH     8.0f
#define RETICLE_OFFSET        20.0f
#define RETICLE_ALPHA          0.5f

//-------------------------------------------------------------------------
// Helper to determine if we should use square (1:1) or rectangular (3:1) reticle
// Returns the aspect ratio (width/height): 1.0 for square, 3.0 for rectangle
//-------------------------------------------------------------------------
- (CGFloat)reticleAspectRatio {
    NSString* style = self.processor.reticleStyle;

    // Explicit style takes precedence
    if ([style isEqualToString:@"square"]) {
        return 1.0f;
    }
    if ([style isEqualToString:@"rectangle"]) {
        return 3.0f;
    }

    // "auto" mode: use square for 2D-only formats (QR, DataMatrix, Aztec)
    // Use rectangle for 1D formats or mixed (PDF417, linear barcodes)
    if (self.processor.is2D && !self.processor.is1D) {
        // Only scanning 2D codes - use square
        return 1.0f;
    }

    // Mixed or 1D only - use rectangle for better PDF417/barcode coverage
    return 3.0f;
}

//-------------------------------------------------------------------------
// builds the green box and red line for barcode scanning
// Uses square for 2D codes (QR/DataMatrix) or rectangle for 1D/PDF417
//-------------------------------------------------------------------------
- (UIImage*)buildReticleImage {
    UIImage* result;

    CGFloat aspectRatio = [self reticleAspectRatio];
    CGFloat reticleWidth = RETICLE_SIZE_BASE * aspectRatio;
    CGFloat reticleHeight = RETICLE_SIZE_BASE;

    // For square reticles, use a reasonable size
    if (aspectRatio == 1.0f) {
        reticleWidth = RETICLE_SIZE_BASE;
        reticleHeight = RETICLE_SIZE_BASE;
    }

    UIGraphicsBeginImageContext(CGSizeMake(reticleWidth, reticleHeight));
    CGContextRef context = UIGraphicsGetCurrentContext();

    if (self.processor.is1D) {
        // Red horizontal scan line in the middle
        UIColor* color = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:RETICLE_ALPHA];
        CGContextSetStrokeColorWithColor(context, color.CGColor);
        CGContextSetLineWidth(context, RETICLE_LINE_WIDTH);
        CGContextBeginPath(context);
        CGFloat lineOffset = (CGFloat) (RETICLE_OFFSET+(0.5*RETICLE_LINE_WIDTH));
        CGContextMoveToPoint(context, lineOffset, reticleHeight/2);
        CGContextAddLineToPoint(context, reticleWidth-lineOffset, reticleHeight/2);
        CGContextStrokePath(context);
    }

    if (self.processor.is2D) {
        // Green border (square or rectangular based on aspect ratio)
        UIColor* color = [UIColor colorWithRed:0.0 green:1.0 blue:0.0 alpha:RETICLE_ALPHA];
        CGContextSetStrokeColorWithColor(context, color.CGColor);
        CGContextSetLineWidth(context, RETICLE_LINE_WIDTH);
        CGContextStrokeRect(context,
                            CGRectMake(
                                       RETICLE_OFFSET,
                                       RETICLE_OFFSET,
                                       reticleWidth-2*RETICLE_OFFSET,
                                       reticleHeight-2*RETICLE_OFFSET
                                       )
                            );
    }

    result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

#pragma mark CDVBarcodeScannerOrientationDelegate

- (BOOL)shouldAutorotate
{
    return YES;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation
{
    return [[UIApplication sharedApplication] statusBarOrientation];
}

- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(shouldAutorotateToInterfaceOrientation:)]) {
        return [self.orientationDelegate shouldAutorotateToInterfaceOrientation:interfaceOrientation];
    }

    return YES;
}

- (void) willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)orientation duration:(NSTimeInterval)duration
{
    [UIView setAnimationsEnabled:NO];
    AVCaptureVideoPreviewLayer* previewLayer = self.processor.previewLayer;
    previewLayer.frame = self.view.bounds;

    if (orientation == UIInterfaceOrientationLandscapeLeft) {
        [previewLayer setOrientation:AVCaptureVideoOrientationLandscapeLeft];
    } else if (orientation == UIInterfaceOrientationLandscapeRight) {
        [previewLayer setOrientation:AVCaptureVideoOrientationLandscapeRight];
    } else if (orientation == UIInterfaceOrientationPortrait) {
        [previewLayer setOrientation:AVCaptureVideoOrientationPortrait];
    } else if (orientation == UIInterfaceOrientationPortraitUpsideDown) {
        [previewLayer setOrientation:AVCaptureVideoOrientationPortraitUpsideDown];
    }

    previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;

    [self resizeElements];
    [UIView setAnimationsEnabled:YES];
}

-(void) resizeElements {
    CGRect bounds = self.view.bounds;
    if (@available(iOS 11.0, *)) {
        bounds = CGRectMake(bounds.origin.x, bounds.origin.y, bounds.size.width, self.view.safeAreaLayoutGuide.layoutFrame.size.height+self.view.safeAreaLayoutGuide.layoutFrame.origin.y);
    }

    [self.toolbar sizeToFit];
    CGFloat toolbarHeight  = [self.toolbar frame].size.height;
    CGFloat rootViewHeight = CGRectGetHeight(bounds);
    CGFloat rootViewWidth  = CGRectGetWidth(bounds);
    CGRect  rectArea       = CGRectMake(0, rootViewHeight - toolbarHeight, rootViewWidth, toolbarHeight);
    [self.toolbar setFrame:rectArea];

    // Get aspect ratio based on reticleStyle setting
    CGFloat aspectRatio = [self reticleAspectRatio];

    CGFloat reticleWidth;
    CGFloat reticleHeight;
    CGFloat availableHeight = rootViewHeight - toolbarHeight;

    if (aspectRatio == 1.0f) {
        // Square reticle for 2D codes (QR, DataMatrix)
        // Use 60% of the smaller dimension
        CGFloat minDimension = MIN(rootViewWidth, availableHeight);
        reticleWidth = minDimension * 0.6f;
        reticleHeight = reticleWidth;

        // Make sure it fits
        if (reticleHeight > availableHeight * 0.7f) {
            reticleHeight = availableHeight * 0.7f;
            reticleWidth = reticleHeight;
        }
    } else {
        // Rectangular reticle (3:1) for 1D/PDF417 barcodes
        // Fit to 85% of screen width, maintaining aspect ratio
        reticleWidth = rootViewWidth * 0.85f;
        reticleHeight = reticleWidth / aspectRatio;

        // Make sure it doesn't exceed available height
        CGFloat maxHeight = availableHeight * 0.5f;
        if (reticleHeight > maxHeight) {
            reticleHeight = maxHeight;
            reticleWidth = reticleHeight * aspectRatio;
        }
    }

    rectArea = CGRectMake(
                          (CGFloat) (0.5 * (rootViewWidth  - reticleWidth)),
                          (CGFloat) (0.5 * (rootViewHeight - reticleHeight)),
                          reticleWidth,
                          reticleHeight
                          );

    [self.reticleView setFrame:rectArea];
    self.reticleView.center = CGPointMake(self.view.center.x, self.view.center.y-self.toolbar.frame.size.height/2);
}

@end

//
//  ViewController.m
//  Produce-AR
//
//  Created by Ankush Gola on 10/6/17.
//  Copyright © 2017 Ankush Gola. All rights reserved.
//

#import "BluetoothManager.h"
#import "SoundManager.h"
#import "ViewController.h"

// Bluetooth UUID
static NSString *const UUID = @"19B10010-E8F2-537E-4F6C-D104768A1214";

// Geometric Constants (in meters)
static float const kPLANE_WIDTH = 2.0;
static float const kPLANE_HEIGHT = 1.0;

static float const kPLANE_X = 0.0;
static float const kPLANE_Y = -0.5;
static float const kPLANE_Z = -2;

static float const kORTH_PLANE_HEIGHT = 0.5;

static NSUInteger const kNumMeasures = 8;
static NSUInteger const kAnimateQuantize = 128;

static float const X_SCRN = -50;

@interface ViewController () <ARSCNViewDelegate, BlueToothManagerDelegate>

@property (nonatomic, strong) IBOutlet ARSCNView *sceneView;
@property (atomic) BOOL isAnimating;
@property (atomic) BOOL isRecording;
@property (atomic) BOOL isPlaying;
@end

@interface SCNNodeWrapper : NSObject

@property SCNNode *node;
@property NSString *soundKey;

@end

@implementation SCNNodeWrapper
@end

    
@implementation ViewController
{
    BluetoothManager *_bluetoothManager; // manages Bluetooth I/O
    SoundManager *_soundManager; // manages sound
    SCNNode *_orthoPlaneNode; // panning plane
    NSMutableSet *_addedWaves; // waves added by bluetooth
    NSLock *_arrayLock; // locks the _addedWaves array
    NSMutableArray<SCNNodeWrapper*> *_nodesInArrangement; // holds references to all nodes in arrangement
    
    BOOL _isInArrangementMode;
    BOOL _isInPlaybackMode;
    
    // Buttons
    CGFloat _screenWidth;
    CGFloat _screenHeight;
    UIButton *_playbackButton;
    UIButton *_arrangmentButton;
    UIButton *_recordButton;
    UIButton *_playButton;
    
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Set the view's delegate
    self.sceneView.delegate = self;
    
    // Show statistics such as fps and timing information
    self.sceneView.showsStatistics = YES;
    
    // Container to hold all of the 3D geometry
    SCNScene *scene = [SCNScene new];
    
    // Set the scene to the view
    self.sceneView.scene = scene;
    
    CGRect screenRect = [[UIScreen mainScreen] bounds];
    _screenWidth = MAX(screenRect.size.width, screenRect.size.height);
    _screenHeight = MIN(screenRect.size.width, screenRect.size.height);
    
    // Start off in Arrangement Mode
    _isInArrangementMode = YES;
    _isInPlaybackMode = NO;
    _isRecording = NO;
    _isPlaying = NO;
    
    // Set up initial plane
    [self setupGrid];
    // Set up orthogonal panning pane
    [self setUpOrthoMovingPlane];
    
    // Initialize lock, waves array
    _addedWaves = [NSMutableSet new];
    _arrayLock = [NSLock new];
    _nodesInArrangement = [NSMutableArray new];
    
    // Initialize SoundManager
    _soundManager = [[SoundManager alloc] initWithDefaults];
    
    [self setUpInitialButtons];

    UIButton *button1;
    button1 = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    button1.frame = CGRectMake(30, 200, 60, 60);
    [button1 setTitle:@"Kick"
             forState:(UIControlState)UIControlStateNormal];
    [button1 setBackgroundColor:[UIColor blueColor]];
    [button1 addTarget:self
                action:@selector(playSound1:)
      forControlEvents:(UIControlEvents)UIControlEventTouchDown];
    [self.view addSubview:button1];
    
    UIButton *button2;
    button2 = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    button2.frame = CGRectMake(30, 90, 60, 60);
    [button2 setTitle:@"Snare"
             forState:(UIControlState)UIControlStateNormal];
    [button2 setBackgroundColor:[UIColor blueColor]];
    [button2 addTarget:self
                action:@selector(playSound2:)
      forControlEvents:(UIControlEvents)UIControlEventTouchDown];
    [self.view addSubview:button2];
    
    UIButton *button3;
    button3 = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    button3.frame = CGRectMake(30, 150, 60, 60);
    [button3 setTitle:@"Hat"
             forState:(UIControlState)UIControlStateNormal];
    [button3 setBackgroundColor:[UIColor blueColor]];
    [button3 addTarget:self
                action:@selector(playSound3:)
      forControlEvents:(UIControlEvents)UIControlEventTouchDown];
    [self.view addSubview:button3];
    
    // Initiliaze BluetoothManager
    _bluetoothManager = [[BluetoothManager alloc] initWithServiceUUID:UUID
                                             bluetoothManagerDelegate:self
                                                                queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)];
}

- (void) setUpInitialButtons
{
    // Playback button (DEFAULT - OFF)
    _playbackButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    _playbackButton.frame = CGRectMake(_screenWidth/2 - 60 + X_SCRN,
                               _screenHeight/2 + 110,
                               120,
                               60);
    [_playbackButton setTitle:@"Playback"
             forState:(UIControlState)UIControlStateNormal];
    [_playbackButton setTitleColor:[UIColor whiteColor]
                  forState:(UIControlState)UIControlStateNormal];
    _playbackButton.titleLabel.font = [UIFont systemFontOfSize:16.0];
    [_playbackButton addTarget:self
                action:@selector(playbackMode:)
      forControlEvents:(UIControlEvents)UIControlEventTouchDown];
    CALayer *layer = _playbackButton.layer;
    layer.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.5].CGColor;
    layer.borderColor = [[UIColor darkGrayColor] CGColor];
    layer.borderWidth = 1.0f;
    [self.view addSubview:_playbackButton];
    
    // Arrangement button (DEFAULT - ON)
    _arrangmentButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    _arrangmentButton.frame = CGRectMake(_screenWidth/2 + 60 + X_SCRN,
                                         _screenHeight/2 + 110,
                                         120,
                                         60);
    [_arrangmentButton setTitle:@"Arrangement"
             forState:(UIControlState)UIControlStateNormal];
    [_arrangmentButton setTitleColor:[UIColor whiteColor]
                          forState:(UIControlState)UIControlStateNormal];
    _arrangmentButton.titleLabel.font = [UIFont systemFontOfSize:16.0];
    [_arrangmentButton addTarget:self
                action:@selector(arrangementMode:)
      forControlEvents:(UIControlEvents)UIControlEventTouchDown];
    CALayer *alayer = _arrangmentButton.layer;
    alayer.backgroundColor = [UIColor blackColor].CGColor;
    alayer.borderColor = [[UIColor darkGrayColor] CGColor];
    alayer.borderWidth = 1.0f;
    [self.view addSubview:_arrangmentButton];
    
    [self setUpRecordingButton];
}

- (void)setUpRecordingButton
{
    _recordButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    _recordButton.frame = CGRectMake(30,
                                     30,
                                     60,
                                     60);
    [_recordButton setTitle:@"REC"
                       forState:(UIControlState)UIControlStateNormal];
    [_recordButton setTitleColor:[UIColor whiteColor]
                            forState:(UIControlState)UIControlStateNormal];
    _recordButton.titleLabel.font = [UIFont systemFontOfSize:16.0];
    
    [_recordButton addTarget:self
                      action:@selector(recordingMode:)
                forControlEvents:(UIControlEvents)UIControlEventTouchDown];
    CALayer *layer = _recordButton.layer;
    layer.backgroundColor = [UIColor redColor].CGColor;
    layer.borderColor = [[UIColor darkGrayColor] CGColor];
    layer.borderWidth = 1.0f;
    [self.view addSubview:_recordButton];
}

- (void)setUpPlayButton
{
    _playButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    _playButton.frame = CGRectMake(30,
                                     30,
                                     60,
                                     60);
    [_playButton setTitle:@"PLAY"
                   forState:(UIControlState)UIControlStateNormal];
    [_playButton setTitleColor:[UIColor whiteColor]
                        forState:(UIControlState)UIControlStateNormal];
    _playButton.titleLabel.font = [UIFont systemFontOfSize:16.0];
    
    [_playButton addTarget:self
                    action:@selector(playingMode:)
            forControlEvents:(UIControlEvents)UIControlEventTouchDown];
    CALayer *layer = _playButton.layer;
    layer.backgroundColor = [UIColor greenColor].CGColor;
    layer.borderColor = [[UIColor darkGrayColor] CGColor];
    layer.borderWidth = 1.0f;
    [self.view addSubview:_playButton];
}

- (void)playbackMode:(id)sender {
    if (_isInPlaybackMode) {
        return;
    }
    
    // Set BOOLs
    _isInPlaybackMode = YES;
    _isInArrangementMode = NO;
    
    // Update buttons
    CALayer *alayer = _arrangmentButton.layer;
    alayer.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.5].CGColor;
    
    CALayer *player = _playbackButton.layer;
    player.backgroundColor = [UIColor blackColor].CGColor;
    
    [_recordButton removeFromSuperview];
    [self setUpPlayButton];
    
    // TODO: setup immersive playback/regular playback buttons
}

- (void)arrangementMode:(id)sender {
    if (_isInArrangementMode) {
        return;
    }

    // Set BOOLs
    _isInPlaybackMode = NO;
    _isInArrangementMode = YES;
    
    // Update buttons
    CALayer *alayer = _arrangmentButton.layer;
    alayer.backgroundColor = [UIColor blackColor].CGColor;
    
    CALayer *player = _playbackButton.layer;
    player.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.5].CGColor;
    
    [_playButton removeFromSuperview];
    [self setUpRecordingButton];
}

- (void)recordingMode:(id)sender
{
    if (_isRecording) {
        return;
    }
    _isRecording = YES;
    [self startPanningArrangement:90];
}

- (void)playingMode:(id)sender
{
    if (_isPlaying) {
        return;
    }
    _isPlaying = YES;
    [self startPanningPlayback:90];
}

-(void) playSound1:(id)sender {
    [_soundManager playSound:kKickKey];
    
    if (_isRecording) {
        [_arrayLock lock];
        [_addedWaves addObject:kKickKey];
        [_arrayLock unlock];
    }
}

-(void) playSound2:(id)sender {
    [_soundManager playSound:kSnareKey];
    if (_isRecording) {
        [_arrayLock lock];
        [_addedWaves addObject:kSnareKey];
        [_arrayLock unlock];
    }
}

-(void) playSound3:(id)sender {
    [_soundManager playSound:kHatKey];
    if (_isRecording) {
        [_arrayLock lock];
        [_addedWaves addObject:kHatKey];
        [_arrayLock unlock];
    }
}

# pragma mark - playback and recording with animations

- (void)startPanningPlayback:(float)bpm
{
    float bps = bpm / 60.0; // beats per second
    float totalPanningDuration = (float)kNumMeasures / bps;
    const float loopPanningDuration = totalPanningDuration / (float)kAnimateQuantize;
    
    const float constY = _orthoPlaneNode.position.y;
    const float constZ = _orthoPlaneNode.position.z;
    
    _isAnimating = YES;
    SCNAction *pan = [SCNAction moveByX:kPLANE_WIDTH y:0 z:0 duration:totalPanningDuration];
    [_orthoPlaneNode runAction:pan completionHandler:^{
        _isAnimating = NO;
        _orthoPlaneNode.position = SCNVector3Make(0.0-kPLANE_WIDTH/2, constY, constZ);
        _isPlaying = NO;
    }];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^void () {
        NSMutableSet *arrangementCopy = [NSMutableSet setWithArray:_nodesInArrangement];
        float timeSinceAnimation = 0.0;
        while (_isAnimating) {
            float currentX = _orthoPlaneNode.position.x;
            for (SCNNodeWrapper *sound in _nodesInArrangement) {
                if (![arrangementCopy containsObject:sound]) {
                    continue;
                }
                if (currentX >= (sound.node.position.x - 0.1/2)) {
                    [_soundManager playSound:sound.soundKey];
                    [arrangementCopy removeObject:sound];
                }
            }
            timeSinceAnimation += loopPanningDuration;
            [NSThread sleepForTimeInterval:loopPanningDuration];
        }
    });
}

- (void)startPanningArrangement:(float)bpm
{
    float bps = bpm / 60.0; // beats per second
    float totalPanningDuration = (float)kNumMeasures / bps;
    const float loopPanningDuration = totalPanningDuration / (float)kAnimateQuantize;
    
    const float constY = _orthoPlaneNode.position.y;
    const float constZ = _orthoPlaneNode.position.z;
    
    // Get rid of existing arrangement
    for (SCNNodeWrapper *nodeWrapper in _nodesInArrangement) {
        [nodeWrapper.node removeFromParentNode];
    }
    [_nodesInArrangement removeAllObjects];

    _isAnimating = YES;
    SCNAction *pan = [SCNAction moveByX:kPLANE_WIDTH y:0 z:0 duration:totalPanningDuration];
    [_orthoPlaneNode runAction:pan completionHandler:^{
        _isAnimating = NO;
        _orthoPlaneNode.position = SCNVector3Make(0.0-kPLANE_WIDTH/2, constY, constZ);
        _isRecording = NO;
    }];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^void () {
        float timeSinceAnimation = 0.0;
        NSMutableSet *newSounds = [NSMutableSet new];
        while (_isAnimating) {
            float currentX = _orthoPlaneNode.position.x;
            [_arrayLock lock];
            for (id sound in _addedWaves) {
                [newSounds addObject:sound];
            }
            [_addedWaves removeAllObjects];
            [_arrayLock unlock];
            
            for (NSString *newSound in newSounds) {
                SCNBox *boxGeometry = [SCNBox boxWithWidth:0.1
                                                    height:0.1
                                                    length:0.1
                                             chamferRadius:0.0];
                float zPos;
                if ([newSound isEqualToString:kKickKey]) {
                    zPos = constZ + kPLANE_HEIGHT/3;
                    boxGeometry.firstMaterial.diffuse.contents = SKColor.blueColor;
                } else if ([newSound isEqualToString:kSnareKey]) {
                    zPos = constZ;
                    boxGeometry.firstMaterial.diffuse.contents = SKColor.redColor;
                } else {
                    zPos = constZ - kPLANE_HEIGHT/3;
                    boxGeometry.firstMaterial.diffuse.contents = SKColor.greenColor;
                }
                SCNNode *boxNode = [SCNNode nodeWithGeometry:boxGeometry];
                boxNode.position = SCNVector3Make(currentX + 0.1/2.0, constY, zPos);
                [self.sceneView.scene.rootNode addChildNode: boxNode];
                SCNNodeWrapper *nodeWrapper = [SCNNodeWrapper new];
                nodeWrapper.soundKey = newSound;
                nodeWrapper.node = boxNode;
                [_nodesInArrangement addObject:nodeWrapper];
            }
            [newSounds removeAllObjects];
            timeSinceAnimation += loopPanningDuration;
            [NSThread sleepForTimeInterval:loopPanningDuration];
        }
    });
    
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // Create a session configuration
    ARWorldTrackingConfiguration *configuration = [ARWorldTrackingConfiguration new];

    // Run the view's session
    [self.sceneView.session runWithConfiguration:configuration];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    // Pause the view's session
    [self.sceneView.session pause];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - ARSCNViewDelegate

/*
// Override to create and configure nodes for anchors added to the view's session.
- (SCNNode *)renderer:(id<SCNSceneRenderer>)renderer nodeForAnchor:(ARAnchor *)anchor {
    SCNNode *node = [SCNNode new];
 
    // Add geometry to the node...
 
    return node;
}
*/

#pragma mark - Grid Setup

// Set up the Grid used to anchor all patterns
- (void)setupGrid
{
    // Initialize the material
    SCNMaterial *material = [SCNMaterial new];
    UIImage *img = [UIImage imageNamed:@"tron_grid"];
    material.diffuse.contents = img;
    material.doubleSided = YES;
    
    // Set up horizontal planes
    SCNMaterial *materialH = [material copy];
    materialH.diffuse.contentsTransform = SCNMatrix4MakeScale(kPLANE_WIDTH, kPLANE_HEIGHT, 1);
    materialH.diffuse.wrapS = SCNWrapModeRepeat;
    materialH.diffuse.wrapT = SCNWrapModeRepeat;
    SCNPlane *planeGeometry = [SCNPlane planeWithWidth:kPLANE_WIDTH height:kPLANE_HEIGHT];
    planeGeometry.materials = @[materialH];
    
    SCNNode *planeNode = [SCNNode nodeWithGeometry:planeGeometry];
    
    // Rotate the plane (it's vertical by default)
    planeNode.transform = SCNMatrix4MakeRotation(-M_PI / 2.0, 1.0, 0.0, 0.0);
    
    // place it 1 meter in front of the camera
    planeNode.position = SCNVector3Make(kPLANE_X, kPLANE_Y, kPLANE_Z);
    
    [self.sceneView.scene.rootNode addChildNode:planeNode];
    
    // Setup vertical plane
    material.diffuse.contentsTransform = SCNMatrix4MakeScale(kPLANE_HEIGHT, kORTH_PLANE_HEIGHT, 1);
    material.diffuse.wrapS = SCNWrapModeRepeat;
    material.diffuse.wrapT = SCNWrapModeRepeat;
    SCNPlane *vertPlane = [SCNPlane planeWithWidth:kPLANE_HEIGHT height:kORTH_PLANE_HEIGHT];
    vertPlane.materials = @[material];
    
    SCNNode *vertPlaneNode = [SCNNode nodeWithGeometry:vertPlane];
    
    // Rotate the plane along y axis
    vertPlaneNode.transform = SCNMatrix4MakeRotation(-M_PI / 2.0, 0.0, 1.0, 0.0);
    
    // place it 1 meter in front of the camera
    vertPlaneNode.position = SCNVector3Make(0.0-kPLANE_WIDTH/2, kPLANE_Y+kORTH_PLANE_HEIGHT/2, kPLANE_Z);
    
    [self.sceneView.scene.rootNode addChildNode:vertPlaneNode];
}

- (void)setUpOrthoMovingPlane
{
    SCNPlane *planeGeometry = [SCNPlane planeWithWidth:kPLANE_HEIGHT height:kORTH_PLANE_HEIGHT];
    planeGeometry.firstMaterial.doubleSided = YES;
    
    SCNNode *planeNode = [SCNNode nodeWithGeometry:planeGeometry];
    
    // Rotate the plane along y axis
    planeNode.transform = SCNMatrix4MakeRotation(-M_PI / 2.0, 0.0, 1.0, 0.0);
    
    // place it 1 meter in front of the camera
    planeNode.position = SCNVector3Make(0.0-kPLANE_WIDTH/2, kPLANE_Y+kORTH_PLANE_HEIGHT/2, kPLANE_Z);
    
    // TODO add texture scale
    planeNode.opacity = 0.5;
    
    _orthoPlaneNode = planeNode;

    [self.sceneView.scene.rootNode addChildNode:_orthoPlaneNode];
}

- (void)session:(ARSession *)session didFailWithError:(NSError *)error {
    // Present an error message to the user
    
}

- (void)sessionWasInterrupted:(ARSession *)session {
    // Inform the user that the session has been interrupted, for example, by presenting an overlay
    
}

- (void)sessionInterruptionEnded:(ARSession *)session {
    // Reset tracking and/or remove existing anchors if consistent tracking is required
    
}

#pragma mark - BluetoothManagerDelegate

- (void)didReceiveValueFromBluetoothPeripheral:(NSData *)value
{
    NSString *strData = [[NSString alloc]initWithData:value encoding:NSUTF8StringEncoding];
    NSLog(@"recv: %@", strData);
    
    uint8_t theData = 'a';
    NSData *data = [NSData dataWithBytes:&theData length:1];
    [_bluetoothManager writeValue:data];
}

@end

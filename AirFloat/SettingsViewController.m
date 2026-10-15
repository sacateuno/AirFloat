//
//  SettingsViewController.m
//  AirFloat
//
//  Copyright (c) 2013, Kristian Trenskow All rights reserved.
//
//  Redistribution and use in source and binary forms, with or
//  without modification, are permitted provided that the following
//  conditions are met:
//
//  Redistributions of source code must retain the above copyright
//  notice, this list of conditions and the following disclaimer.
//  Redistributions in binary form must reproduce the above
//  copyright notice, this list of conditions and the following
//  disclaimer in the documentation and/or other materials provided
//  with the distribution. THIS SOFTWARE IS PROVIDED BY THE
//  COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
//  IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
//  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
//  PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER
//  OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
//  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
//  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
//  OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
//  CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
//  STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
//  ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

#import "UIView+AirFloatAdditions.h"
#import "NSUserDefaults+AirFloatAdditions.h"

#import "AirFloatAppDelegate.h"
#import "AirFloatSwitch.h"
#import "AirFloatBarButton.h"
#import "SettingsViewController.h"

static UIColor* AirFloatHexColor(uint32_t hex) {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0 green:((hex >> 8) & 0xFF) / 255.0 blue:(hex & 0xFF) / 255.0 alpha:1.0];
}

// Status panel palette: dim and bright phosphor greens, with amber and red kept for warnings.
#define StatusPanelBackground 0x040A06
#define StatusPanelBorder     0x1F5A36
#define StatusLabelColor      0x3C8F5A
#define StatusValueColor      0x3DDC7A
#define StatusHighlightColor  0x8CFFB8
#define StatusSeparatorColor  0x2F6B47
#define StatusAddressColor    0x56D4E0
#define StatusWarningColor    0xFFB000
#define StatusErrorColor      0xFF5A4F
#define StatusGlowColor       0x39FF7A

NSString *const SettingsUpdatedNotification = @"SettingsUpdatedNotification";

@interface SettingsViewController () <UITextFieldDelegate, UIScrollViewDelegate>

@property (nonatomic, strong) IBOutlet UITextField* nameField;
@property (nonatomic, strong) IBOutlet UIView* nameFieldHighlightedBackground;
@property (nonatomic, strong) IBOutlet UIButton* nameClearButton;
@property (nonatomic, strong) IBOutlet UITextField* authenticationField;
@property (nonatomic, strong) IBOutlet UIView* authenticationFieldHighlightedBackground;
@property (nonatomic, strong) IBOutlet UIButton* authenticationClearButton;
@property (nonatomic, strong) IBOutlet AirFloatSwitch* authenticationEnabledSwitch;
@property (nonatomic, strong) IBOutlet AirFloatSwitch* keepScreenLitSwitch;
@property (nonatomic, strong) IBOutlet UILabel* keepScreenLitOnlyWhenReceivingLabel;
@property (nonatomic, strong) IBOutlet AirFloatSwitch* keepScreenLitOnlyWhenReceivingSwitch;
@property (nonatomic, strong) IBOutlet UILabel* keepScreenLitOnlyWhenConnectedToPowerLabel;
@property (nonatomic, strong) IBOutlet AirFloatSwitch* keepScreenLitOnlyWhenConnectedToPowerSwitch;
@property (nonatomic, strong) IBOutlet AirFloatSwitch* ignoreSourceVolumeSwitch;

@property (nonatomic, strong) AirFloatSwitch* wifiAwakeSwitch;
@property (nonatomic, strong) AirFloatSwitch* autoRestartSwitch;
@property (nonatomic, strong) AirFloatSwitch* bitPerfectSwitch;
@property (nonatomic, strong) AirFloatSwitch* diagnosticLogSwitch;
@property (nonatomic, strong) UISegmentedControl* resyncControl;
@property (nonatomic, strong) UILabel* statusLabel;
@property (nonatomic, strong) NSTimer* statusTimer;

- (void)updateVisuals;

@end

@implementation SettingsViewController

- (void)viewDidLoad {
    
    [super viewDidLoad];
    
    ((UIScrollView*)self.view).contentSize = CGSizeMake(320, 358);
    
    [self buildExtendedSettings];
    
    self.nameField.text = NSStandardUserDefaults.name;
    self.authenticationField.text = NSStandardUserDefaults.password;
    self.authenticationEnabledSwitch.on = NSStandardUserDefaults.authenticationEnabled;
    self.keepScreenLitSwitch.on = NSStandardUserDefaults.keepScreenLit;
    self.keepScreenLitOnlyWhenReceivingSwitch.on = NSStandardUserDefaults.keepScreenLitOnlyWhenReceiving;
    self.keepScreenLitOnlyWhenConnectedToPowerSwitch.on = NSStandardUserDefaults.keepScreenLitOnlyWhenConnectedToPower;
    self.ignoreSourceVolumeSwitch.on = NSStandardUserDefaults.ignoreSourceVolume;
    
    [self updateVisuals];
    
    [self.authenticationEnabledSwitch addTarget:self action:@selector(authenticationSwitchValueChanged:) forControlEvents:UIControlEventValueChanged];
    [self.keepScreenLitSwitch addTarget:self action:@selector(litSwitchChangedValue:) forControlEvents:UIControlEventValueChanged];
    [self.keepScreenLitOnlyWhenReceivingSwitch addTarget:self action:@selector(litSwitchChangedValue:) forControlEvents:UIControlEventValueChanged];
    [self.keepScreenLitOnlyWhenConnectedToPowerSwitch addTarget:self action:@selector(litSwitchChangedValue:) forControlEvents:UIControlEventValueChanged];
    [self.ignoreSourceVolumeSwitch addTarget:self action:@selector(ignoreSourceVolumeChangedValue:) forControlEvents:UIControlEventValueChanged];
    
    [self updateExtendedVisuals];
    
}

- (void)viewWillAppear:(BOOL)animated {
    
    [super viewWillAppear:animated];
    
    [self centerContent];
    
    [self refreshStatus];
    [self.statusTimer invalidate];
    self.statusTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(refreshStatus) userInfo:nil repeats:YES];
    
}

- (void)viewWillDisappear:(BOOL)animated {
    
    [super viewWillDisappear:animated];
    
    [self.statusTimer invalidate];
    self.statusTimer = nil;
    
    [self.nameField resignFirstResponder];
    [self.authenticationField resignFirstResponder];
    
}

- (IBAction)clearButtonTouchedUpInside:(id)sender {
    
    UITextField* textField = (sender == self.nameClearButton ? self.nameField : self.authenticationField);
    
    textField.text = @"";
    [textField becomeFirstResponder];
    
}

- (void)updateVisuals {
    
    self.keepScreenLitOnlyWhenReceivingSwitch.userInteractionEnabled = self.keepScreenLitOnlyWhenConnectedToPowerSwitch.userInteractionEnabled = self.keepScreenLitSwitch.on;
    
    [UIView animateWithDuration:0.3f
                          delay:0.0f
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
                         self.keepScreenLitOnlyWhenConnectedToPowerLabel.alpha = self.keepScreenLitOnlyWhenConnectedToPowerSwitch.alpha = self.keepScreenLitOnlyWhenReceivingLabel.alpha = self.keepScreenLitOnlyWhenReceivingSwitch.alpha = (self.keepScreenLitSwitch.on ? 1.0f : 0.3f);
                     } completion:nil];
    
}

- (void)updateSettings {
    
    NSStandardUserDefaults.name = self.nameField.text;
    NSStandardUserDefaults.password = self.authenticationField.text;
    NSStandardUserDefaults.authenticationEnabled = self.authenticationEnabledSwitch.on;
    NSStandardUserDefaults.keepScreenLit = self.keepScreenLitSwitch.on;
    NSStandardUserDefaults.keepScreenLitOnlyWhenReceiving = self.keepScreenLitOnlyWhenReceivingSwitch.on;
    NSStandardUserDefaults.keepScreenLitOnlyWhenConnectedToPower = self.keepScreenLitOnlyWhenConnectedToPowerSwitch.on;
    NSStandardUserDefaults.ignoreSourceVolume = self.ignoreSourceVolumeSwitch.on;
    
    if (self.wifiAwakeSwitch != nil) {
        NSStandardUserDefaults.keepWifiAwake = self.wifiAwakeSwitch.on;
        NSStandardUserDefaults.autoRestartServer = self.autoRestartSwitch.on;
        NSStandardUserDefaults.bitPerfectMode = self.bitPerfectSwitch.on;
        NSStandardUserDefaults.diagnosticLog = self.diagnosticLogSwitch.on;
        NSStandardUserDefaults.resyncLevel = self.resyncControl.selectedSegmentIndex;
    }
    
    [self updateVisuals];
    [self updateExtendedVisuals];
    
    [AirFloatSharedAppDelegate applyRuntimeSettings];
    [AirFloatSharedAppDelegate updateRaopSeverSettings];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:SettingsUpdatedNotification object:nil userInfo:nil];
    
}

- (void)setAuthenticationEnabledSwitchOff {
    
    [self.authenticationEnabledSwitch setOn:NO animated:YES];
    
    [self.authenticationField becomeFirstResponder];
    
}

- (IBAction)authenticationSwitchValueChanged:(id)sender {
    
    if ([self.authenticationField.text length] == 0 && self.authenticationEnabledSwitch.on && !self.authenticationField.isFirstResponder) {
        
        [self.authenticationField shake];
        
        [self performSelector:@selector(setAuthenticationEnabledSwitchOff) withObject:nil afterDelay:0.5];
        
    }
    
    if (![self.authenticationField isFirstResponder])
        [self updateSettings];
    
}

- (IBAction)litSwitchChangedValue:(id)sender {
    
    [self updateSettings];
    
}

- (IBAction)ignoreSourceVolumeChangedValue:(id)sender {
    
    [self updateSettings];
    
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    
    UIButton* clearButton = (textField == self.nameField ? self.nameClearButton : self.authenticationClearButton);
    UIView* highlightedBackgroundView = (textField == self.nameField ? self.nameFieldHighlightedBackground : self.authenticationFieldHighlightedBackground);
    
    if (clearButton.hidden) {
        clearButton.alpha = 0.0;
        clearButton.hidden = NO;
    
        [UIView animateWithDuration:0.5
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
                             clearButton.alpha = 1.0;
                             highlightedBackgroundView.alpha = 1.0;
                         } completion:nil];
        
    }
    
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    
    UIButton* clearButton = (textField == self.nameField ? self.nameClearButton : self.authenticationClearButton);
    UIView* highlightedBackgroundView = (textField == self.nameField ? self.nameFieldHighlightedBackground : self.authenticationFieldHighlightedBackground);
    
    [self updateSettings];
    
    [UIView animateWithDuration:0.5
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
                         highlightedBackgroundView.alpha = 0.0;
                         if ([textField.text length] == 0)
                             clearButton.alpha = 0.0;
                     } completion:^(BOOL finished) {
                         if ([textField.text length] == 0)
                             clearButton.hidden = YES;
                     }];
    
    if (textField == self.authenticationField && [self.authenticationField.text length] == 0)
        [self.authenticationEnabledSwitch setOn:NO animated:YES];
    
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    
    [textField resignFirstResponder];
    
    return YES;
    
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    
    if (textField == self.authenticationField)
        [self.authenticationEnabledSwitch setOn:([[textField.text stringByReplacingCharactersInRange:range withString:string] length] > 0)
                                       animated:YES];
    
    return YES;
    
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    
    [self.nameField resignFirstResponder];
    [self.authenticationField resignFirstResponder];
    
}

#pragma mark - Reliability, audio quality and diagnostics

- (UILabel*)labelWithText:(NSString*)text frame:(CGRect)frame header:(BOOL)header {
    
    UILabel* label = [[UILabel alloc] initWithFrame:frame];
    
    label.text = text;
    label.backgroundColor = [UIColor clearColor];
    label.textColor = [UIColor whiteColor];
    label.font = (header ? [UIFont boldSystemFontOfSize:12] : [UIFont systemFontOfSize:13]);
    label.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.5];
    label.shadowOffset = CGSizeMake(0.0, 1.0);
    
    return label;
    
}

- (CGFloat)addGroupTitled:(NSString*)title rows:(NSInteger)rows atY:(CGFloat)y inContainer:(UIView*)container {
    
    [container addSubview:[self labelWithText:title frame:CGRectMake(21, y, 240, 18) header:YES]];
    
    UIImageView* background = [[UIImageView alloc] initWithImage:[[UIImage imageNamed:@"SettingsGroupBackground.png"] stretchableImageWithLeftCapWidth:25 topCapHeight:25]];
    background.frame = CGRectMake(12, y + 20, 300, 18 + 32 * rows);
    [container addSubview:background];
    
    return y + 20;
    
}

- (AirFloatSwitch*)addSwitchRow:(NSString*)title index:(NSInteger)index groupY:(CGFloat)groupY inContainer:(UIView*)container {
    
    [container addSubview:[self labelWithText:title frame:CGRectMake(22, groupY + 16 + 32 * index, 186, 18) header:NO]];
    
    AirFloatSwitch* control = [[AirFloatSwitch alloc] initWithFrame:CGRectMake(214, groupY + 11 + 32 * index, 88, 25)];
    [control awakeFromNib];
    [container addSubview:control];
    
    return control;
    
}

- (UISegmentedControl*)addSegmentedRow:(NSString*)title items:(NSArray*)items index:(NSInteger)index groupY:(CGFloat)groupY inContainer:(UIView*)container {
    
    [container addSubview:[self labelWithText:title frame:CGRectMake(22, groupY + 16 + 32 * index, 92, 18) header:NO]];
    
    UISegmentedControl* control = [[UISegmentedControl alloc] initWithItems:items];
    control.frame = CGRectMake(116, groupY + 10 + 32 * index, 186, 26);
    control.tintColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    [control setTitleTextAttributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:11] } forState:UIControlStateNormal];
    [container addSubview:control];
    
    return control;
    
}

- (AirFloatBarButton*)addButtonTitled:(NSString*)title action:(SEL)action frame:(CGRect)frame inContainer:(UIView*)container {
    
    AirFloatBarButton* button = [[AirFloatBarButton alloc] initWithFrame:frame];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:button];
    
    return button;
    
}

- (void)buildExtendedSettings {
    
    UIView* container = self.keepScreenLitSwitch.superview;
    if (container == nil)
        return;
    
    static const CGFloat statusLineHeight = 17.0;
    static const NSInteger statusLines = 7;
    static const CGFloat topMargin = 14.0;
    static const CGFloat buttonHeight = 28.0;
    CGFloat statusPanelHeight = 36 + statusLines * statusLineHeight + 12;
    CGFloat topBlockHeight = topMargin + statusPanelHeight + 10 + buttonHeight + 22;
    
    // The live status is the first thing shown, so the existing rows move down to make room.
    for (UIView* subview in container.subviews) {
        CGRect subviewFrame = subview.frame;
        subviewFrame.origin.y += topBlockHeight;
        subview.frame = subviewFrame;
    }
    
    CGFloat y = 0;
    for (UIView* subview in container.subviews)
        y = MAX(y, CGRectGetMaxY(subview.frame));
    y += 22;
    
    // Live status at the top
    UIView* statusPanel = [[UIView alloc] initWithFrame:CGRectMake(12, topMargin, 300, statusPanelHeight)];
    statusPanel.backgroundColor = [AirFloatHexColor(StatusPanelBackground) colorWithAlphaComponent:0.94];
    statusPanel.layer.cornerRadius = 7.0;
    statusPanel.layer.borderWidth = 1.0;
    statusPanel.layer.borderColor = AirFloatHexColor(StatusPanelBorder).CGColor;
    [container addSubview:statusPanel];
    
    UILabel* promptLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 9, 276, 16)];
    promptLabel.backgroundColor = [UIColor clearColor];
    promptLabel.attributedText = [self attributedPrompt];
    [self addGlowToLabel:promptLabel];
    [statusPanel addSubview:promptLabel];
    
    UIView* rule = [[UIView alloc] initWithFrame:CGRectMake(12, 29, 276, 1)];
    rule.backgroundColor = [AirFloatHexColor(StatusPanelBorder) colorWithAlphaComponent:0.8];
    [statusPanel addSubview:rule];
    
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 36, 276, statusLines * statusLineHeight)];
    self.statusLabel.backgroundColor = [UIColor clearColor];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.lineBreakMode = NSLineBreakByClipping;
    [self addGlowToLabel:self.statusLabel];
    [statusPanel addSubview:self.statusLabel];
    
    CGFloat buttonsY = topMargin + statusPanelHeight + 10;
    [self addButtonTitled:@"Reset counters" action:@selector(resetCountersTouchedUpInside:) frame:CGRectMake(12, buttonsY, 142, buttonHeight) inContainer:container];
    [self addButtonTitled:@"Clear log" action:@selector(clearLogTouchedUpInside:) frame:CGRectMake(170, buttonsY, 142, buttonHeight) inContainer:container];
    
    // Settings below the existing ones
    CGFloat groupY = [self addGroupTitled:@"RELIABILITY" rows:2 atY:y inContainer:container];
    self.wifiAwakeSwitch = [self addSwitchRow:@"Keep Wi-Fi awake" index:0 groupY:groupY inContainer:container];
    self.autoRestartSwitch = [self addSwitchRow:@"Auto-restart server" index:1 groupY:groupY inContainer:container];
    y = groupY + 18 + 32 * 2 + 14;
    
    groupY = [self addGroupTitled:@"AUDIO QUALITY" rows:2 atY:y inContainer:container];
    self.bitPerfectSwitch = [self addSwitchRow:@"Bit-perfect mode" index:0 groupY:groupY inContainer:container];
    self.resyncControl = [self addSegmentedRow:@"Resync" items:@[@"\u00B10.1 s", @"\u00B10.5 s", @"\u00B11 s"] index:1 groupY:groupY inContainer:container];
    y = groupY + 18 + 32 * 2 + 14;
    
    groupY = [self addGroupTitled:@"DIAGNOSTICS" rows:1 atY:y inContainer:container];
    self.diagnosticLogSwitch = [self addSwitchRow:@"Save log" index:0 groupY:groupY inContainer:container];
    y = groupY + 18 + 32 + 24;
    
    CGRect frame = container.frame;
    frame.size.height = y;
    container.frame = frame;
    
    ((UIScrollView*)self.view).contentSize = CGSizeMake(320, y);
    
    self.wifiAwakeSwitch.on = NSStandardUserDefaults.keepWifiAwake;
    self.autoRestartSwitch.on = NSStandardUserDefaults.autoRestartServer;
    self.bitPerfectSwitch.on = NSStandardUserDefaults.bitPerfectMode;
    self.diagnosticLogSwitch.on = NSStandardUserDefaults.diagnosticLog;
    self.resyncControl.selectedSegmentIndex = NSStandardUserDefaults.resyncLevel;
    
    // Targets are connected only now: setting 'on' sends a value changed event that would
    // otherwise overwrite the stored preferences with controls that are not initialized yet.
    for (UIControl* control in @[self.wifiAwakeSwitch, self.autoRestartSwitch, self.bitPerfectSwitch, self.diagnosticLogSwitch, self.resyncControl])
        [control addTarget:self action:@selector(extendedControlChanged:) forControlEvents:UIControlEventValueChanged];
    
}

- (void)updateExtendedVisuals {
    
    if (self.bitPerfectSwitch == nil)
        return;
    
    // Bit-perfect mode always ignores the source volume; the stored preference is left untouched.
    self.ignoreSourceVolumeSwitch.userInteractionEnabled = !self.bitPerfectSwitch.on;
    self.ignoreSourceVolumeSwitch.alpha = (self.bitPerfectSwitch.on ? 0.5f : 1.0f);
    
}

- (IBAction)extendedControlChanged:(id)sender {
    
    [self updateSettings];
    
}

- (IBAction)clearLogTouchedUpInside:(id)sender {
    
    [AirFloatSharedAppDelegate clearLog];
    [self refreshStatus];
    
}

- (IBAction)resetCountersTouchedUpInside:(id)sender {
    
    [AirFloatSharedAppDelegate resetCounters];
    [self refreshStatus];
    
}

- (void)refreshStatus {
    
    self.statusLabel.attributedText = [self attributedStatusForSnapshot:[AirFloatSharedAppDelegate statusSnapshot]];
    
}

#pragma mark - Status panel appearance

- (void)addGlowToLabel:(UILabel*)label {
    
    label.layer.shadowColor = AirFloatHexColor(StatusGlowColor).CGColor;
    label.layer.shadowOpacity = 0.45f;
    label.layer.shadowRadius = 2.0f;
    label.layer.shadowOffset = CGSizeZero;
    
}

- (NSDictionary*)statusAttributesWithColor:(UIColor*)color bold:(BOOL)bold {
    
    static NSParagraphStyle* paragraphStyle;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableParagraphStyle* style = [[NSMutableParagraphStyle alloc] init];
        style.minimumLineHeight = 17.0;
        style.maximumLineHeight = 17.0;
        style.lineBreakMode = NSLineBreakByClipping;
        paragraphStyle = style;
    });
    
    UIFont* font = [UIFont fontWithName:(bold ? @"Courier-Bold" : @"Courier") size:11.5];
    
    return @{ NSFontAttributeName: font, NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: paragraphStyle };
    
}

- (NSAttributedString*)attributedPrompt {
    
    NSMutableAttributedString* text = [[NSMutableAttributedString alloc] init];
    
    void (^add)(NSString*, uint32_t, BOOL) = ^(NSString* string, uint32_t color, BOOL bold) {
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:string attributes:[self statusAttributesWithColor:AirFloatHexColor(color) bold:bold]]];
    };
    
    add(@"airfloat@ipad", StatusValueColor, YES);
    add(@":~$ ", StatusLabelColor, NO);
    add(@"status ", StatusHighlightColor, NO);
    add(@"\u258C", StatusHighlightColor, NO);
    
    return text;
    
}

- (NSAttributedString*)attributedStatusForSnapshot:(NSDictionary*)snapshot {
    
    NSMutableAttributedString* text = [[NSMutableAttributedString alloc] init];
    
    void (^add)(NSString*, uint32_t, BOOL) = ^(NSString* string, uint32_t color, BOOL bold) {
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:string attributes:[self statusAttributesWithColor:AirFloatHexColor(color) bold:bold]]];
    };
    
    BOOL running = [snapshot[@"running"] boolValue];
    BOOL hasNetwork = [snapshot[@"hasNetwork"] boolValue];
    BOOL recording = [snapshot[@"recording"] boolValue];
    BOOL keepAlive = [snapshot[@"keepAlive"] boolValue];
    BOOL logEnabled = [snapshot[@"logEnabled"] boolValue];
    NSUInteger lost = [snapshot[@"lost"] unsignedIntegerValue];
    NSUInteger asked = [snapshot[@"asked"] unsignedIntegerValue];
    NSUInteger got = [snapshot[@"got"] unsignedIntegerValue];
    NSUInteger unrecovered = [snapshot[@"unrecovered"] unsignedIntegerValue];
    NSUInteger restarts = [snapshot[@"restarts"] unsignedIntegerValue];
    double delay = [snapshot[@"delay"] doubleValue];
    int uptime = (int)[snapshot[@"uptime"] doubleValue];
    
    // Server
    add(@"SRV   ", StatusLabelColor, NO);
    if (!running) {
        add(@"\u25CF ", StatusErrorColor, NO);
        add(@"STOPPED", StatusErrorColor, YES);
    } else if (!hasNetwork) {
        add(@"\u25CF ", StatusWarningColor, NO);
        add(@"NO NETWORK", StatusWarningColor, YES);
    } else {
        add(@"\u25CF ", StatusValueColor, NO);
        add([NSString stringWithFormat:@"%@:%u", snapshot[@"address"], [snapshot[@"port"] unsignedIntValue]], StatusAddressColor, NO);
    }
    add(@"\n", StatusValueColor, NO);
    
    // State
    add(@"STATE ", StatusLabelColor, NO);
    if (recording) {
        add(@"\u25CF ", StatusHighlightColor, NO);
        add(@"STREAMING", StatusHighlightColor, YES);
    } else {
        add(@"\u25CF ", StatusSeparatorColor, NO);
        add(@"IDLE", StatusValueColor, NO);
    }
    add(@"  up ", StatusLabelColor, NO);
    add([NSString stringWithFormat:@"%02d:%02d:%02d", uptime / 3600, (uptime / 60) % 60, uptime % 60], StatusValueColor, NO);
    add(@"\n", StatusValueColor, NO);
    
    // Network keep-alive
    add(@"NET   ", StatusLabelColor, NO);
    add(@"keep-alive ", StatusLabelColor, NO);
    if (keepAlive) {
        add(@"ON", StatusValueColor, YES);
        if ([snapshot[@"gateway"] length] > 0) {
            add(@" \u2192 ", StatusSeparatorColor, NO);
            add(snapshot[@"gateway"], StatusAddressColor, NO);
        }
    } else
        add(@"OFF", StatusWarningColor, YES);
    add(@"\n", StatusValueColor, NO);
    
    // Lost packets and their recovery
    add(@"LOSS  ", StatusLabelColor, NO);
    add(@"lost ", StatusLabelColor, NO);
    add([NSString stringWithFormat:@"%lu", (unsigned long)lost], (lost > 0 ? StatusWarningColor : StatusValueColor), NO);
    add(@" \u00B7 ", StatusSeparatorColor, NO);
    add(@"ask ", StatusLabelColor, NO);
    add([NSString stringWithFormat:@"%lu", (unsigned long)asked], StatusValueColor, NO);
    add(@" \u00B7 ", StatusSeparatorColor, NO);
    add(@"got ", StatusLabelColor, NO);
    add([NSString stringWithFormat:@"%lu", (unsigned long)got], (got >= asked ? StatusValueColor : StatusWarningColor), NO);
    add(@"\n", StatusValueColor, NO);
    
    // Queue and clock
    uint32_t delayColor = (fabs(delay) < 0.1 ? StatusValueColor : (fabs(delay) < 0.3 ? StatusWarningColor : StatusErrorColor));
    add(@"SYNC  ", StatusLabelColor, NO);
    add(@"queue ", StatusLabelColor, NO);
    add([NSString stringWithFormat:@"%u", [snapshot[@"queue"] unsignedIntValue]], StatusValueColor, NO);
    add(@" pk", StatusLabelColor, NO);
    add(@" \u00B7 ", StatusSeparatorColor, NO);
    add(@"delay ", StatusLabelColor, NO);
    add([NSString stringWithFormat:@"%+.3f s", delay], delayColor, NO);
    add(@"\n", StatusValueColor, NO);
    
    // Failures
    add(@"FAIL  ", StatusLabelColor, NO);
    add(@"unrecovered ", StatusLabelColor, NO);
    add([NSString stringWithFormat:@"%lu", (unsigned long)unrecovered], (unrecovered > 0 ? StatusErrorColor : StatusValueColor), unrecovered > 0);
    add(@" \u00B7 ", StatusSeparatorColor, NO);
    add(@"restarts ", StatusLabelColor, NO);
    add([NSString stringWithFormat:@"%lu", (unsigned long)restarts], (restarts > 0 ? StatusWarningColor : StatusValueColor), NO);
    add(@"\n", StatusValueColor, NO);
    
    // Log
    add(@"LOG   ", StatusLabelColor, NO);
    if (logEnabled) {
        add(@"ON", StatusWarningColor, YES);
        add([NSString stringWithFormat:@" \u00B7 %ld KB", (long)[snapshot[@"logKB"] longValue]], StatusLabelColor, NO);
    } else
        add(@"OFF", StatusSeparatorColor, NO);
    
    return text;
    
}

@end

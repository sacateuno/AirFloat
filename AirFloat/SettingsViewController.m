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
@property (nonatomic, strong) UISegmentedControl* latencyControl;
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
        NSStandardUserDefaults.latencyLevel = self.latencyControl.selectedSegmentIndex;
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

- (void)buildExtendedSettings {
    
    UIView* container = self.keepScreenLitSwitch.superview;
    if (container == nil)
        return;
    
    CGFloat y = 0;
    for (UIView* subview in container.subviews)
        y = MAX(y, CGRectGetMaxY(subview.frame));
    y += 22;
    
    CGFloat groupY = [self addGroupTitled:@"RELIABILITY" rows:2 atY:y inContainer:container];
    self.wifiAwakeSwitch = [self addSwitchRow:@"Keep Wi-Fi awake" index:0 groupY:groupY inContainer:container];
    self.autoRestartSwitch = [self addSwitchRow:@"Auto-restart server" index:1 groupY:groupY inContainer:container];
    y = groupY + 18 + 32 * 2 + 14;
    
    groupY = [self addGroupTitled:@"AUDIO QUALITY" rows:3 atY:y inContainer:container];
    self.bitPerfectSwitch = [self addSwitchRow:@"Bit-perfect mode" index:0 groupY:groupY inContainer:container];
    self.latencyControl = [self addSegmentedRow:@"Latency" items:@[@"0.25 s", @"1 s", @"2 s"] index:1 groupY:groupY inContainer:container];
    self.resyncControl = [self addSegmentedRow:@"Resync" items:@[@"\u00B10.1 s", @"\u00B10.5 s", @"\u00B11 s"] index:2 groupY:groupY inContainer:container];
    y = groupY + 18 + 32 * 3 + 14;
    
    groupY = [self addGroupTitled:@"DIAGNOSTICS" rows:1 atY:y inContainer:container];
    self.diagnosticLogSwitch = [self addSwitchRow:@"Save log" index:0 groupY:groupY inContainer:container];
    y = groupY + 18 + 32 + 10;
    
    AirFloatBarButton* clearButton = [[AirFloatBarButton alloc] initWithFrame:CGRectMake(12, y, 142, 28)];
    [clearButton setTitle:@"Clear log" forState:UIControlStateNormal];
    clearButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [clearButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [clearButton addTarget:self action:@selector(clearLogTouchedUpInside:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:clearButton];
    
    AirFloatBarButton* resetButton = [[AirFloatBarButton alloc] initWithFrame:CGRectMake(170, y, 142, 28)];
    [resetButton setTitle:@"Reset counters" forState:UIControlStateNormal];
    resetButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [resetButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [resetButton addTarget:self action:@selector(resetCountersTouchedUpInside:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:resetButton];
    y += 28 + 12;
    
    self.statusLabel = [self labelWithText:@"" frame:CGRectMake(14, y, 296, 104) header:NO];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont fontWithName:@"Courier" size:11];
    self.statusLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [container addSubview:self.statusLabel];
    y += 104 + 24;
    
    CGRect frame = container.frame;
    frame.size.height = y;
    container.frame = frame;
    
    ((UIScrollView*)self.view).contentSize = CGSizeMake(320, y);
    
    self.wifiAwakeSwitch.on = NSStandardUserDefaults.keepWifiAwake;
    self.autoRestartSwitch.on = NSStandardUserDefaults.autoRestartServer;
    self.bitPerfectSwitch.on = NSStandardUserDefaults.bitPerfectMode;
    self.diagnosticLogSwitch.on = NSStandardUserDefaults.diagnosticLog;
    self.latencyControl.selectedSegmentIndex = NSStandardUserDefaults.latencyLevel;
    self.resyncControl.selectedSegmentIndex = NSStandardUserDefaults.resyncLevel;
    
    // Targets are connected only now: setting 'on' sends a value changed event that would
    // otherwise overwrite the stored preferences with controls that are not initialized yet.
    for (UIControl* control in @[self.wifiAwakeSwitch, self.autoRestartSwitch, self.bitPerfectSwitch, self.diagnosticLogSwitch, self.latencyControl, self.resyncControl])
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
    
    self.statusLabel.text = [AirFloatSharedAppDelegate statusDescription];
    
}

@end

//
//  NSUserDefaults+AirFloatAdditions.h
//  AirFloat
//
//  Created by Kristian Trenskow on 13/11/2016.
//
//

#import <Foundation/Foundation.h>

#define NSStandardUserDefaults [NSUserDefaults standardUserDefaults]

@interface NSUserDefaults (AirFloatAdditions)

@property (nonatomic) NSString *name;
@property (nonatomic) NSString *password;
@property (nonatomic) BOOL authenticationEnabled;
@property (nonatomic) BOOL keepScreenLit;
@property (nonatomic) BOOL keepScreenLitOnlyWhenReceiving;
@property (nonatomic) BOOL keepScreenLitOnlyWhenConnectedToPower;
@property (nonatomic) BOOL ignoreSourceVolume;
@property (nonatomic) BOOL keepWifiAwake;
@property (nonatomic) BOOL autoRestartServer;
@property (nonatomic) BOOL bitPerfectMode;
@property (nonatomic) BOOL diagnosticLog;
@property (nonatomic) NSInteger latencyLevel;   // 0 = 0.25 s, 1 = 1 s, 2 = 2 s
@property (nonatomic) NSInteger resyncLevel;    // 0 = 0.1 s, 1 = 0.5 s, 2 = 1 s

@end

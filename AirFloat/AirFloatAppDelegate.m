//
//  AirFloatiOSAppDelegate.m
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

#import <ifaddrs.h>
#import <arpa/inet.h>
#import <sys/socket.h>
#import <sys/select.h>
#import <netinet/in.h>
#import <net/if.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>

#import "NSUserDefaults+AirFloatAdditions.h"

#import "AppViewController.h"
#import "AirFloatAppDelegate.h"
#import <libairfloat/audiooutput.h>

static const NSTimeInterval kWatchdogInterval = 5.0;
static const int kWatchdogProbeEveryTicks = 3;
static const uint16_t kFirstServerPort = 5000;
static const uint16_t kLastServerPort = 5010;

// Finds the IPv4 address of the Wi-Fi interface and, assuming the router is the first
// address of the subnet, the gateway used for the keep-alive packets.
static BOOL AirFloatCurrentNetwork(NSString** ip, struct sockaddr_in* gateway) {
    
    struct ifaddrs* list = NULL;
    BOOL found = NO;
    
    if (getifaddrs(&list) != 0)
        return NO;
    
    for (struct ifaddrs* a = list ; a != NULL ; a = a->ifa_next) {
        
        if (a->ifa_addr == NULL || a->ifa_netmask == NULL || a->ifa_addr->sa_family != AF_INET || strcmp(a->ifa_name, "en0") != 0)
            continue;
        
        uint32_t addr = ((struct sockaddr_in*)a->ifa_addr)->sin_addr.s_addr;
        uint32_t mask = ((struct sockaddr_in*)a->ifa_netmask)->sin_addr.s_addr;
        
        if (ip != NULL) {
            char buffer[INET_ADDRSTRLEN];
            inet_ntop(AF_INET, &addr, buffer, sizeof(buffer));
            *ip = [NSString stringWithUTF8String:buffer];
        }
        
        if (gateway != NULL) {
            memset(gateway, 0, sizeof(*gateway));
            gateway->sin_len = sizeof(*gateway);
            gateway->sin_family = AF_INET;
            gateway->sin_port = htons(7);
            gateway->sin_addr.s_addr = (addr & mask) | htonl(1);
        }
        
        found = YES;
        break;
        
    }
    
    freeifaddrs(list);
    
    return found;
    
}

// Connects to the local RAOP port and expects any answer (or an immediate close).
static BOOL AirFloatProbeServerPort(uint16_t port) {
    
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0)
        return YES;
    
    fcntl(fd, F_SETFL, O_NONBLOCK);
    
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons(port);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    
    BOOL ok = NO;
    
    int result = connect(fd, (struct sockaddr*)&address, sizeof(address));
    
    if (result == 0 || errno == EINPROGRESS) {
        
        fd_set writeSet;
        FD_ZERO(&writeSet);
        FD_SET(fd, &writeSet);
        struct timeval timeout = { 2, 0 };
        
        if (select(fd + 1, NULL, &writeSet, NULL, &timeout) > 0) {
            
            int error = 0;
            socklen_t length = sizeof(error);
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length);
            
            if (error == 0) {
                
                const char* request = "OPTIONS * RTSP/1.0\r\nCSeq: 1\r\n\r\n";
                send(fd, request, strlen(request), 0);
                
                fd_set readSet;
                FD_ZERO(&readSet);
                FD_SET(fd, &readSet);
                timeout.tv_sec = 3;
                timeout.tv_usec = 0;
                
                if (select(fd + 1, &readSet, NULL, NULL, &timeout) > 0)
                    ok = YES;
                
            }
            
        }
        
    }
    
    close(fd);
    
    return ok;
    
}

static bool AirFloatShouldIgnoreSourceVolume(void) {
    return NSStandardUserDefaults.ignoreSourceVolume || NSStandardUserDefaults.bitPerfectMode;
}

@interface AirFloatAppDelegate ()

@property (nonatomic, assign) raop_server_p server;

@end
    
@implementation AirFloatAppDelegate {
    UIBackgroundTaskIdentifier *_backgroundTask;
    dispatch_source_t _keepAliveTimer;
    dispatch_source_t _watchdogTimer;
    NSString* _lastIP;
    uint16_t _serverPort;
    NSDate* _serverStartedAt;
    NSUInteger _restartCount;
    int _probeTick;
    BOOL _probeInFlight;
    BOOL _keepAliveActive;
}


#pragma mark - NSApplication delegates

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    [NSStandardUserDefaults registerDefaults:@{
        @"keepWifiAwake": @YES,
        @"autoRestartServer": @YES,
        @"bitPerfectMode": @NO,
#ifdef AIRFLOAT_LOG_DEFAULT_ON
        @"diagnosticLog": @YES,
#else
        @"diagnosticLog": @NO,
#endif
        @"resyncLevel": @1
    }];
    
    [self applyRuntimeSettings];
    
    self.appViewController = [[AppViewController alloc] init];
    
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    
    if ([self.window respondsToSelector:@selector(setRootViewController:)])
        self.window.rootViewController = self.appViewController;
    else {
        self.appViewController.view.frame = CGRectMake(0, 20, 320, 460);
        [self.window addSubview:self.appViewController.view];
    }
    
    [self.window makeKeyAndVisible];
    
    if ([UIApplication instancesRespondToSelector:@selector(registerUserNotificationSettings:)]){
        [application registerUserNotificationSettings:[UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeAlert|UIUserNotificationTypeBadge|UIUserNotificationTypeSound categories:nil]];
    }
    
    audio_output_session_start();
    
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    [self startRaopServer];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    [self.appViewController handleForegroundTasks];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    [self.appViewController handleBackgroundTasks];
}

#pragma mark - RAOP Server interface

- (void)startRaopServer  {
    
    if (!self.server) {
        struct raop_server_settings_t settings;
        settings.name =  [NSStandardUserDefaults.name UTF8String];
        settings.password = (NSStandardUserDefaults.authenticationEnabled ? [NSStandardUserDefaults.password UTF8String] : NULL);
        settings.ignore_source_volume = AirFloatShouldIgnoreSourceVolume();
        self.server = raop_server_create(settings);
    }
    
    if (!raop_server_is_running(self.server)) {
        
        uint16_t port = kFirstServerPort;
        BOOL started = NO;
        
        while (port < kLastServerPort && !started)
            started = raop_server_start(_server, port++);
        
        if (started) {
            
            _serverPort = port - 1;
            _serverStartedAt = [NSDate date];
            
            NSString* ip = nil;
            AirFloatCurrentNetwork(&ip, NULL);
            _lastIP = ip;
            
        }
        
        self.appViewController.server = _server;
        
    }
    
}

- (void)updateRaopSeverSettings {
    
    if (self.server) {
        raop_server_set_settings(self.server, (struct raop_server_settings_t) {
            [NSStandardUserDefaults.name UTF8String],
            (NSStandardUserDefaults.authenticationEnabled ? [NSStandardUserDefaults.password UTF8String] : NULL),
            AirFloatShouldIgnoreSourceVolume()
        });
    }
    
}

- (void)restartRaopServer {
    
    if (!self.server) {
        [self startRaopServer];
        return;
    }
    
    _restartCount++;
    
    raop_runtime_log_message([[NSString stringWithFormat:@"Restarting RAOP server (restart #%lu)", (unsigned long)_restartCount] UTF8String]);
    
    raop_server_stop(self.server);
    
    [self startRaopServer];
    
}

#pragma mark - Runtime settings

- (void)applyRuntimeSettings {
    
    NSString* logPath = @"/var/tmp/airfloat.log";
    if (access("/var/tmp", W_OK) != 0)
        logPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"airfloat.log"];
    
    raop_runtime_set_log_path([logPath fileSystemRepresentation]);
    raop_runtime_set_log_enabled(NSStandardUserDefaults.diagnosticLog);
    
    static const double resyncWindows[] = { 0.1, 0.5, 1.0 };
    
    raop_runtime_set_resync_window(resyncWindows[NSStandardUserDefaults.resyncLevel]);
    
    [self updateWifiKeepAlive];
    [self updateWatchdog];
    
}

#pragma mark - Wi-Fi keep-alive

- (void)updateWifiKeepAlive {
    
    if (NSStandardUserDefaults.keepWifiAwake) {
        
        if (_keepAliveTimer != nil)
            return;
        
        int fd = socket(AF_INET, SOCK_DGRAM, 0);
        if (fd < 0)
            return;
        
        fcntl(fd, F_SETFL, O_NONBLOCK);
        
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), 2 * NSEC_PER_SEC, NSEC_PER_SEC / 2);
        
        dispatch_source_set_event_handler(timer, ^{
            
            struct sockaddr_in gateway;
            if (AirFloatCurrentNetwork(NULL, &gateway)) {
                char byte = 0;
                char sink[64];
                sendto(fd, &byte, 1, 0, (struct sockaddr*)&gateway, sizeof(gateway));
                while (recv(fd, sink, sizeof(sink), 0) > 0) { }
            }
            
        });
        
        dispatch_source_set_cancel_handler(timer, ^{
            close(fd);
        });
        
        _keepAliveTimer = timer;
        _keepAliveActive = YES;
        dispatch_resume(timer);
        
        raop_runtime_log_message("Wi-Fi keep-alive started");
        
    } else if (_keepAliveTimer != nil) {
        
        dispatch_source_cancel(_keepAliveTimer);
        _keepAliveTimer = nil;
        _keepAliveActive = NO;
        
        raop_runtime_log_message("Wi-Fi keep-alive stopped");
        
    }
    
}

#pragma mark - Server watchdog

- (void)updateWatchdog {
    
    if (NSStandardUserDefaults.autoRestartServer) {
        
        if (_watchdogTimer != nil)
            return;
        
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kWatchdogInterval * NSEC_PER_SEC)), (uint64_t)(kWatchdogInterval * NSEC_PER_SEC), NSEC_PER_SEC);
        
        __weak AirFloatAppDelegate* weakSelf = self;
        dispatch_source_set_event_handler(timer, ^{
            [weakSelf watchdogTick];
        });
        
        _watchdogTimer = timer;
        dispatch_resume(timer);
        
        raop_runtime_log_message("Server watchdog started");
        
    } else if (_watchdogTimer != nil) {
        
        dispatch_source_cancel(_watchdogTimer);
        _watchdogTimer = nil;
        
        raop_runtime_log_message("Server watchdog stopped");
        
    }
    
}

- (void)watchdogTick {
    
    if (!NSStandardUserDefaults.autoRestartServer || !self.server)
        return;
    
    if (!raop_server_is_running(self.server)) {
        raop_runtime_log_message("Watchdog: server is not running, starting it");
        [self startRaopServer];
        return;
    }
    
    BOOL recording = raop_server_is_recording(self.server);
    
    NSString* ip = nil;
    AirFloatCurrentNetwork(&ip, NULL);
    
    BOOL ipChanged = (ip != nil && ![ip isEqualToString:_lastIP]);
    
    if (ipChanged && !recording) {
        raop_runtime_log_message([[NSString stringWithFormat:@"Watchdog: network address changed (%@ -> %@), restarting the server", _lastIP ?: @"none", ip] UTF8String]);
        [self restartRaopServer];
        return;
    }
    
    if (ip == nil) {
        _lastIP = nil;
        return;
    }
    
    if (recording || _probeInFlight)
        return;
    
    if (++_probeTick % kWatchdogProbeEveryTicks != 0)
        return;
    
    _probeInFlight = YES;
    uint16_t port = _serverPort;
    
    __weak AirFloatAppDelegate* weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        BOOL ok = AirFloatProbeServerPort(port);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            
            AirFloatAppDelegate* strongSelf = weakSelf;
            if (strongSelf == nil)
                return;
            
            strongSelf->_probeInFlight = NO;
            
            if (!ok && strongSelf.server && !raop_server_is_recording(strongSelf.server)) {
                raop_runtime_log_message("Watchdog: the server does not answer on its port, restarting it");
                [strongSelf restartRaopServer];
            }
            
        });
        
    });
    
}

#pragma mark - Status

- (void)clearLog {
    raop_runtime_clear_log();
}

- (void)resetCounters {
    raop_runtime_reset_stats();
}

- (NSString*)statusDescription {
    
    NSString* ip = nil;
    struct sockaddr_in gateway;
    BOOL hasNetwork = AirFloatCurrentNetwork(&ip, &gateway);
    
    BOOL running = (self.server != NULL && raop_server_is_running(self.server));
    BOOL recording = (running && raop_server_is_recording(self.server));
    
    struct raop_runtime_stats_t stats;
    raop_runtime_get_stats(&stats);
    
    NSMutableArray* lines = [NSMutableArray array];
    
    if (running)
        [lines addObject:[NSString stringWithFormat:@"Server   %@:%u", (hasNetwork ? ip : @"no network"), _serverPort]];
    else
        [lines addObject:@"Server   stopped"];
    
    NSTimeInterval uptime = (running && _serverStartedAt != nil ? -[_serverStartedAt timeIntervalSinceNow] : 0);
    [lines addObject:[NSString stringWithFormat:@"State    %@   up %02d:%02d:%02d   restarts %lu", (recording ? @"streaming" : @"idle"), (int)uptime / 3600, ((int)uptime / 60) % 60, (int)uptime % 60, (unsigned long)_restartCount]];
    
    NSString* gatewayText = @"off";
    if (_keepAliveActive) {
        char buffer[INET_ADDRSTRLEN] = "?";
        if (hasNetwork)
            inet_ntop(AF_INET, &gateway.sin_addr, buffer, sizeof(buffer));
        gatewayText = [NSString stringWithFormat:@"on (%s)", buffer];
    }
    [lines addObject:[NSString stringWithFormat:@"Keep-alive %@", gatewayText]];
    
    [lines addObject:[NSString stringWithFormat:@"Lost %u   resend asked %u / got %u", stats.packets_lost, stats.resends_requested, stats.resends_received]];
    [lines addObject:[NSString stringWithFormat:@"Unrecovered %u   queue %u pk   delay %+.3f s", stats.unrecovered_packets, stats.queue_packets, stats.delay_seconds]];
    [lines addObject:[NSString stringWithFormat:@"Log %@ (%ld KB)", (raop_runtime_log_enabled() ? @"on" : @"off"), raop_runtime_log_size() / 1024]];
    
    return [lines componentsJoinedByString:@"\n"];
    
}

#pragma mark - Background Notifications

-(void) showNotification:(NSString*)messageTitle
{
    if (!messageTitle) {
        messageTitle = @"Stream started.";
    }
    
    UILocalNotification *notification = [[UILocalNotification alloc] init];
    notification.alertBody = messageTitle;
    notification.fireDate = [NSDate date];
    notification.soundName = UILocalNotificationDefaultSoundName;
    
    [[UIApplication sharedApplication] scheduleLocalNotification:notification];
}

@end

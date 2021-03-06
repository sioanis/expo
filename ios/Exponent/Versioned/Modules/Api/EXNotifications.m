// Copyright 2016-present 650 Industries. All rights reserved.

#import "EXNotifications.h"
#import "EXConstants.h"
#import "EXUnversioned.h"

#import <React/RCTUtils.h>
#import <React/RCTConvert.h>

@implementation RCTConvert (NSCalendarUnit)

RCT_ENUM_CONVERTER(NSCalendarUnit,
                   (@{
                      @"year": @(NSCalendarUnitYear),
                      @"month": @(NSCalendarUnitMonth),
                      @"week": @(NSCalendarUnitWeekOfYear),
                      @"day": @(NSCalendarUnitDay),
                      @"hour": @(NSCalendarUnitHour),
                      @"minute": @(NSCalendarUnitMinute)
                      }),
                   0,
                   integerValue);

@end

@interface EXNotifications ()

// unversioned EXRemoteNotificationManager instance
@property (nonatomic, weak) id <EXNotificationsScopedModuleDelegate> kernelNotificationsDelegate;

@end

@implementation EXNotifications

EX_EXPORT_SCOPED_MODULE(ExponentNotifications, RemoteNotificationManager);

@synthesize bridge = _bridge;

- (void)setBridge:(RCTBridge *)bridge
{
  _bridge = bridge;
}

- (instancetype)initWithExperienceId:(NSString *)experienceId kernelServiceDelegate:(id)kernelServiceInstance params:(NSDictionary *)params
{
  if (self = [super initWithExperienceId:experienceId kernelServiceDelegate:kernelServiceInstance params:params]) {
    _kernelNotificationsDelegate = kernelServiceInstance;
  }
  return self;
}

RCT_REMAP_METHOD(getDevicePushTokenAsync,
                 getDevicePushTokenAsyncWithResolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
  if (![_bridge.scopedModules.constants.appOwnership isEqualToString:@"standalone"]) {
    return reject(0, @"getDevicePushTokenAsync is only accessible within standalone applications", nil);
  }
  
  NSString *token = [_kernelNotificationsDelegate apnsTokenStringForScopedModule:self];
  if (!token) {
    return reject(0, @"APNS token has not been set", nil);
  }
  return resolve(@{ @"type": @"apns", @"data": token });
}

RCT_REMAP_METHOD(getExponentPushTokenAsync,
                 getExponentPushTokenAsyncWithResolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
  if (!self.experienceId) {
    reject(0, @"Requires experience Id", nil);
    return;
  }
  void (^success)(NSDictionary *) = ^(NSDictionary *result) {
    resolve([result objectForKey:@"exponentPushToken"]);
  };
  void (^failure)(NSString *) = ^(NSString *message) {
    reject(0, message, nil);
  };
  [_kernelNotificationsDelegate getExpoPushTokenForScopedModule:self
                                                        success:success
                                                        failure:failure];
}

RCT_EXPORT_METHOD(presentLocalNotification:(NSDictionary *)payload
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(__unused RCTPromiseRejectBlock)reject)
{
  UILocalNotification *notification = [self _localNotificationFromPayload:payload];

  [RCTSharedApplication() presentLocalNotificationNow:notification];

  resolve(notification.userInfo[@"id"]);
}

RCT_EXPORT_METHOD(scheduleLocalNotification:(NSDictionary *)payload
                  withOptions:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(__unused RCTPromiseRejectBlock)reject)
{
  UILocalNotification *notification = [self _localNotificationFromPayload:payload];

  notification.fireDate = [RCTConvert NSDate:options[@"time"]] ?: [NSDate new];
  notification.repeatInterval = [RCTConvert NSCalendarUnit:options[@"repeat"]] ?: 0;

  [RCTSharedApplication() scheduleLocalNotification:notification];

  resolve(notification.userInfo[@"id"]);
}

RCT_EXPORT_METHOD(cancelScheduledNotification:(NSString *)uniqueId)
{
  for (UILocalNotification *notification in [RCTSharedApplication() scheduledLocalNotifications]) {
    if ([notification.userInfo[@"id"] isEqualToString:uniqueId]) {
      [RCTSharedApplication() cancelLocalNotification:notification];
      break;
    }
  }
}

RCT_EXPORT_METHOD(cancelAllScheduledNotifications)
{
  for (UILocalNotification *notification in [RCTSharedApplication() scheduledLocalNotifications]) {
    if ([notification.userInfo[@"experienceId"] isEqualToString:self.experienceId]) {
      [RCTSharedApplication() cancelLocalNotification:notification];
    }
  }
}

#pragma mark - Badges

// TODO: Make this read from the kernel instead of UIApplication for the main Exponent app

RCT_REMAP_METHOD(getBadgeNumberAsync,
                 getBadgeNumberAsyncWithResolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(__unused RCTPromiseRejectBlock)reject)
{
  resolve(@(RCTSharedApplication().applicationIconBadgeNumber));
}

RCT_EXPORT_METHOD(setBadgeNumberAsync:(nonnull NSNumber *)number
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(__unused RCTPromiseRejectBlock)reject)
{
  RCTSharedApplication().applicationIconBadgeNumber = number.integerValue;
  resolve(nil);
}

#pragma mark - internal

- (UILocalNotification *)_localNotificationFromPayload:(NSDictionary *)payload
{
  RCTAssert((payload[@"data"] != nil), @"Attempted to send a local notification with no `data` property.");
  UILocalNotification *localNotification = [UILocalNotification new];

  NSString *uniqueId = [[NSUUID new] UUIDString];

  localNotification.alertTitle = payload[@"title"];
  localNotification.alertBody = payload[@"body"];
  
  if ([payload[@"sound"] boolValue]) {
    localNotification.soundName = UILocalNotificationDefaultSoundName;
  }
  
  localNotification.applicationIconBadgeNumber = [RCTConvert NSInteger:payload[@"count"]] ?: 0;

  localNotification.userInfo = @{
                                 @"body": payload[@"data"],
                                 @"experienceId": self.experienceId,
                                 @"id": uniqueId,
                                 };

  return localNotification;
}

@end

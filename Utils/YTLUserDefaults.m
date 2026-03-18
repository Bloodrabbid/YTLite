#import "YTLUserDefaults.h"

@implementation YTLUserDefaults

static NSString *const kDefaultsSuiteName = @"com.dvntm.ytlite";

+ (YTLUserDefaults *)standardUserDefaults {
    static dispatch_once_t onceToken;
    static YTLUserDefaults *defaults = nil;

    dispatch_once(&onceToken, ^{
        defaults = [[self alloc] initWithSuiteName:kDefaultsSuiteName];
        [defaults registerDefaults];
    });

    return defaults;
}

- (void)reset {
    [self removePersistentDomainForName:kDefaultsSuiteName];
}

- (void)registerDefaults {
    [self registerDefaults:@{
        @"noAds": @YES,
        @"backgroundPlayback": @YES,
        @"removeUploads": @YES,
        @"speedIndex": @1,
        @"autoSpeedIndex": @3,
        @"wiFiQualityIndex": @0,
        @"cellQualityIndex": @0,
        @"pivotIndex": @0,
        @"advancedMode": @YES,
        @"yandexTranslation": @YES
    }];

    // Migration: force-enable advancedMode and yandexTranslation for existing installs
    if (![self objectForKey:@"ytl_migrationVersion"] || [self integerForKey:@"ytl_migrationVersion"] < 2) {
        [self setBool:YES forKey:@"advancedMode"];
        [self setBool:YES forKey:@"yandexTranslation"];
        [self setInteger:2 forKey:@"ytl_migrationVersion"];
    }
}

+ (void)resetUserDefaults {
    [[self standardUserDefaults] reset];
}

@end

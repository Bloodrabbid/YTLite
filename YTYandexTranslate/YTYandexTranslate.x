#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import "YTLYandexTranslationFetcher.h"

// Minimal dummy interfaces to suppress compiler warnings
@interface MLVideo : NSObject
@property(nonatomic, readonly) NSTimeInterval totalMediaTime;
@property(nonatomic, readonly) float playbackRate;
@end

@interface YTMainAppVideoPlayerOverlayViewController : UIViewController
- (CGFloat)mediaTime;
@end

@interface YTPlayerViewController : UIViewController
@property (nonatomic, strong) AVPlayer *ytl_yandexPlayer;
@property (nonatomic, assign) BOOL ytl_isTranslating;
@property (nonatomic, strong) NSString *ytl_currentTranslatingVideoID;
@property(nonatomic, readonly) MLVideo *activeVideo;
@property(nonatomic, readonly) UIViewController *activeVideoPlayerOverlay;
- (NSString *)contentVideoID;
- (void)autoTranslateYandex;
@end

static void showNativeAlert(NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        UIWindow *window = [[UIApplication sharedApplication] keyWindow];
        UIViewController *rootVC = window.rootViewController;
        
        while (rootVC.presentedViewController) {
            rootVC = rootVC.presentedViewController;
        }
        
        [rootVC presentViewController:alert animated:YES completion:nil];
#pragma clang diagnostic pop
    });
}

%hook YTPlayerViewController
%property (nonatomic, strong) AVPlayer *ytl_yandexPlayer;
%property (nonatomic, assign) BOOL ytl_isTranslating;
%property (nonatomic, strong) NSString *ytl_currentTranslatingVideoID;

- (void)loadWithPlayerTransition:(id)arg1 playbackConfig:(id)arg2 {
    %orig;

    if (self.ytl_yandexPlayer) {
        [self.ytl_yandexPlayer pause];
        self.ytl_yandexPlayer = nil;
    }
    self.ytl_isTranslating = NO;
    self.ytl_currentTranslatingVideoID = nil;

    [self performSelector:@selector(autoTranslateYandex) withObject:nil afterDelay:1.5];
}

%new
- (void)autoTranslateYandex {
    if (self.ytl_isTranslating) return;

    NSString *videoID = [self contentVideoID];
    if (!videoID) {
        showNativeAlert(@"Yandex Error", @"videoID is nil");
        return;
    }
    
    self.ytl_isTranslating = YES;
    self.ytl_currentTranslatingVideoID = self.contentVideoID;
    
    showNativeAlert(@"Yandex Translator", [NSString stringWithFormat:@"Translating video: %@", videoID]);
    
    NSTimeInterval duration = self.activeVideo.totalMediaTime > 0 ? self.activeVideo.totalMediaTime : 600; 
    
    [YTLYandexTranslationFetcher requestTranslationForVideoID:self.contentVideoID duration:duration completionHandler:^(NSURL *audioURL, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.ytl_isTranslating = NO;
            if (error) {
                showNativeAlert(@"Yandex API Error", error.localizedDescription);
                if (error.code == 2) {
                    [self performSelector:@selector(autoTranslateYandex) withObject:nil afterDelay:20.0];
                }
                return;
            }
            if (audioURL && [self.contentVideoID isEqualToString:self.ytl_currentTranslatingVideoID]) {
                AVPlayerItem *item = [AVPlayerItem playerItemWithURL:audioURL];
                self.ytl_yandexPlayer = [AVPlayer playerWithPlayerItem:item];
                self.ytl_yandexPlayer.volume = 1.0;
                
                showNativeAlert(@"Yandex Status", @"Translation Audio Ready & Playing! 🎧");
                
                CGFloat mediaTime = 0;
                if ([self.activeVideoPlayerOverlay isKindOfClass:%c(YTMainAppVideoPlayerOverlayViewController)]) {
                    mediaTime = [(YTMainAppVideoPlayerOverlayViewController *)self.activeVideoPlayerOverlay mediaTime];
                }

                if (mediaTime > 0) {
                    [self.ytl_yandexPlayer seekToTime:CMTimeMakeWithSeconds(mediaTime, 1000)];
                }

                if (self.activeVideo.playbackRate > 0) {
                    self.ytl_yandexPlayer.rate = self.activeVideo.playbackRate;
                }
                
                [self.ytl_yandexPlayer play];
            } else if (!audioURL) {
                showNativeAlert(@"Yandex Error", @"No audio URL returned.");
            }
        });
    }];
}

// Sync translation playback state with main video
- (void)playbackDidPause {
    %orig;
    if (self.ytl_yandexPlayer) {
        [self.ytl_yandexPlayer pause];
    }
}

- (void)playbackDidPlay {
    %orig;
    if (self.ytl_yandexPlayer) {
        [self.ytl_yandexPlayer play];
    }
}

- (void)setPlaybackRate:(float)rate {
    %orig;
    if (self.ytl_yandexPlayer) {
        self.ytl_yandexPlayer.rate = rate;
    }
}

- (void)seekToTime:(double)time timeToleranceBefore:(double)before timeToleranceAfter:(double)after {
    %orig;
    if (self.ytl_yandexPlayer) {
        [self.ytl_yandexPlayer seekToTime:CMTimeMakeWithSeconds(time, 1000)];
    }
}
%end

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        showNativeAlert(@"YTYandexTranslate", @"Tweak successfully injected and initialized!");
    });
}

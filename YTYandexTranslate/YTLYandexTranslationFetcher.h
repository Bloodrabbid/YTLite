#import <Foundation/Foundation.h>

@interface YTLYandexTranslationFetcher : NSObject

/// Sends a request to Yandex to translate the specified YouTube video.
/// @param videoID The ID of the YouTube video.
/// @param duration The length of the video in seconds.
/// @param completion A block called with a URL to the translated audio track, or an error.
+ (void)requestTranslationForVideoID:(NSString *)videoID
                            duration:(NSTimeInterval)duration
                   completionHandler:(void(^)(NSURL *audioURL, NSError *error))completion;

@end

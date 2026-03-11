#import <UIKit/UIKit.h>
%hook YTPlayerViewController
- (void)play { %orig; }
- (void)pause { %orig; }
- (void)setPlaybackRate:(float)rate { %orig; }
%end

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

FOUNDATION_EXPORT NSString * const AwemeXSettingsChangedNotification;

@interface AwemeXSettingsHelper : NSObject
+ (instancetype)shared;
- (CGFloat)topAlpha;
- (CGFloat)globalAlpha;
- (CGFloat)avatarAlpha;
- (CGFloat)rightScale;
- (BOOL)hideTopSearch;
- (void)setFloat:(CGFloat)value forKey:(NSString *)key;
- (void)setBool:(BOOL)value forKey:(NSString *)key;
- (void)resetAll;
@end

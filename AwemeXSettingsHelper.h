#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

FOUNDATION_EXPORT NSString * const AwemeXSettingsChangedNotification;

@interface AwemeXSettingsHelper : NSObject
+ (instancetype)shared;

- (CGFloat)topAlpha;
- (CGFloat)rightAlpha;
- (CGFloat)likeAlpha;
- (CGFloat)avatarAlpha;
- (CGFloat)bottomTextAlpha;
- (CGFloat)musicAlpha;
- (CGFloat)rightScale;

- (BOOL)hideTopSearch;
- (BOOL)floatingButtonEnabled;

- (BOOL)newLongPressPanelEnabled;
- (BOOL)longPressPanelGlassEnabled;
- (BOOL)longPressPanelDarkModeEnabled;
- (BOOL)savePanelGlassEnabled;
- (CGFloat)panelGlassAlpha;
- (BOOL)longPressSaveVideoEnabled;
- (BOOL)longPressSaveCoverEnabled;
- (BOOL)longPressSaveAudioEnabled;
- (BOOL)longPressSaveImageEnabled;
- (BOOL)longPressSaveAllImagesEnabled;
- (BOOL)longPressGenerateVideoEnabled;
- (BOOL)longPressCopyTextEnabled;

- (void)setFloat:(CGFloat)value forKey:(NSString *)key;
- (void)setBool:(BOOL)value forKey:(NSString *)key;
- (void)resetAll;
@end
